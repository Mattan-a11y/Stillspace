import Foundation
import AppKit
import AVFoundation
@main struct PlaybackCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let engine = DesktopController()
        let originals = NSScreen.screens.map { NSWorkspace.shared.desktopImageURL(for: $0) }
        var failure: String?
        engine.onFailure = { failure = $0; engine.stop() }
        engine.show(Landscape(id: "missing", name: "Missing", subtitle: "", palette: 0, file: "/private/tmp/stillspace-does-not-exist.mp4"), widgets: [], corner: "Top right")
        precondition(failure != nil && engine.windowCount == 0 && engine.playerCount == 0)
        engine.show(Landscape.builtins[0], widgets: [], corner: "Top right")
        precondition(engine.windowCount == NSScreen.screens.count && engine.playerCount == 0)
        engine.pause(true); precondition(engine.isPaused)
        engine.pause(false); precondition(!engine.isPaused)
        if CommandLine.arguments.count > 1 {
            let video = Landscape(id: "test-video", name: "Test", subtitle: "", palette: 0, file: CommandLine.arguments[1])
            engine.show(video, widgets: [], corner: "Top right")
            let player = engine.previewPlayer
            precondition(player != nil && engine.playerCount == 1)
            engine.show(video, widgets: [DesktopWidget(kind: .text)], corner: "Top right", force: true)
            precondition(engine.previewPlayer === player && engine.playerCount == 1)
            engine.pause(true); precondition(player?.rate == 0)
            engine.pause(false)
            let id = ConnectedDisplay.all.first!.id
            engine.show(video, widgets: [], corner: "Top right", scenes: Landscape.builtins + [video], choices: [id: DisplayChoice(sceneID: "dawn", fit: .fit)])
            precondition(engine.playerCount == (NSScreen.screens.count > 1 ? 1 : 0))
            for n in 0..<15 { engine.show(n % 2 == 0 ? video : Landscape.builtins[1], widgets: [], corner: "Top right") }
            precondition(engine.playerCount <= 1)
        }
        engine.stop(); precondition(engine.playerCount == 0 && engine.windowCount == 0 && engine.previewPlayer == nil)
        precondition(NSScreen.screens.map { NSWorkspace.shared.desktopImageURL(for: $0) } == originals)
        let choice = DisplayChoice(sceneID: "night", fit: .fit)
        let decoded = try JSONDecoder().decode(DisplayChoice.self, from: JSONEncoder().encode(choice))
        precondition(decoded == choice)
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("Stillspace-storage-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Imports")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let used = folder.appendingPathComponent("used.mp4"), unused = folder.appendingPathComponent("unused.mp4")
        try Data([1]).write(to: used); try Data([2]).write(to: unused)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.mp4"), withDestinationURL: unused)
        failure = nil
        engine.show(Landscape(id: "broken", name: "Broken", subtitle: "", palette: 0, file: unused.path), widgets: [], corner: "Top right")
        for _ in 0..<50 { if failure != nil { break }; try await Task.sleep(for: .milliseconds(100)) }
        precondition(failure != nil && engine.playerCount == 0)
        let candidates = try MediaStorage.unused(in: root, referenced: [used.path])
        guard candidates.count == 1 && candidates.first?.url.path == unused.path else { throw NSError(domain: "StorageCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected candidates: \(candidates.map { $0.url.path }), root \(root.path), owned \(ManagedMedia.deletable(unused, in: folder))"]) }
        print("PASS: missing media, pause/resume, player reuse, rapid switches, per-display fit, stop cleanup, native wallpaper preservation, display preference roundtrip, and safe unused-media scan")
    }
}
