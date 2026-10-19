import Foundation
import SwiftUI
import AppKit
@main struct ScenePackCheck {
    @MainActor static func main() async throws {
        func check(_ condition: @autoclosure () throws -> Bool) rethrows {
            let result = try condition(); precondition(result)
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Stillspace-pack-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for asleep in [false, true] {
            for locked in [false, true] {
                for battery in [false, true] {
                    for lowPower in [false, true] {
                        for hot in [false, true] {
                            for pauseBattery in [false, true] {
                                for pauseLowPower in [false, true] {
                                    let reason = PlaybackPolicy.reason(asleep: asleep, locked: locked, battery: battery, lowPower: lowPower, hot: hot, pauseBattery: pauseBattery, pauseLowPower: pauseLowPower)
                                    check((reason != nil) == (asleep || locked || hot || (battery && pauseBattery) || (lowPower && pauseLowPower)))
                                }
                            }
                        }
                    }
                }
            }
        }
        let managed = root.appendingPathComponent("Imports")
        try fm.createDirectory(at: managed, withIntermediateDirectories: true)
        let owned = managed.appendingPathComponent("owned.mp4")
        let outside = root.appendingPathComponent("personal.mp4")
        try Data([1]).write(to: owned); try Data([2]).write(to: outside)
        check(ManagedMedia.deletable(owned, in: managed))
        check(!ManagedMedia.deletable(outside, in: managed))
        check(!ManagedMedia.deletable(managed, in: managed))
        let link = managed.appendingPathComponent("link.mp4")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        check(!ManagedMedia.deletable(link, in: managed))
        let linkedFolder = root.appendingPathComponent("LinkedImports")
        try fm.createSymbolicLink(at: linkedFolder, withDestinationURL: managed)
        check(!ManagedMedia.deletable(linkedFolder.appendingPathComponent("owned.mp4"), in: linkedFolder))
        check(fm.fileExists(atPath: outside.path))
        let legacy = try JSONDecoder().decode(DesktopWidget.self, from: Data("{\"id\":\"legacy\",\"kind\":\"Clock\",\"text\":\"\",\"size\":48}".utf8))
        precondition(legacy.position == nil && legacy.font == .rounded && legacy.tint == .white)
        let styled = DesktopWidget(kind: .text, text: "Make it yours", size: 44, position: WidgetPosition(x: 0.3, y: 0.6), font: .serif, tint: .mint)
        let roundtrip = try JSONDecoder().decode(DesktopWidget.self, from: JSONEncoder().encode(styled))
        precondition(roundtrip == styled)
        let canvas = CGSize(width: 960, height: 600)
        let box = WidgetLayout.box(styled, canvas: canvas, scale: 2.0 / 3.0)
        let edge = WidgetLayout.moved(styled.position!, translation: CGSize(width: 10000, height: -10000), box: box, canvas: canvas)
        let point = WidgetLayout.center(edge, box: box, canvas: canvas)
        precondition(point.x + box.width / 2 <= canvas.width && point.y - box.height / 2 >= 0)
        precondition(WidgetLayout.moved(styled.position!, translation: .zero, box: box, canvas: .zero) == styled.position!)
        _ = NSApplication.shared
        let image = ImageRenderer(content: ZStack {
            LandscapeView(palette: 2)
            WidgetCanvas(items: [DesktopWidget(kind: .clock, size: 56, position: WidgetPosition(x: 0.7, y: 0.2), font: .mono, tint: .cream), styled], corner: "Top right", referenceWidth: 1440)
        }.frame(width: 960, height: 600))
        if CommandLine.arguments.count > 2 {
            guard let result = image.cgImage, let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { fatalError("Widget preview did not render") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
        let store = ScenePackStore(root: root.appendingPathComponent("Library"))
        let sceneID = UUID().uuidString
        let pack = ScenePack(name: "Blue hour + clock", selected: sceneID, scenes: [PackedScene(id: sceneID, name: "Blue hour", palette: 2, builtin: "night", video: nil, sound: WallpaperSound(enabled: false))], widgetsEnabled: true, widgets: [styled], corner: "Top right", automatic: false)
        let saved = try store.save(pack, sources: [:])
        try check(try store.list().count == 1)
        let installed = try await ScenePackInstaller.install(saved, support: root.appendingPathComponent("Applied"))
        precondition(installed.selected == "night" && installed.sounds["night"]?.enabled == false)
        let exported = root.appendingPathComponent("Portable.stillscene")
        try "not exported".write(to: saved.url.appendingPathComponent("unexpected-script.sh"), atomically: true, encoding: .utf8)
        try store.export(saved, to: exported)
        precondition(!fm.fileExists(atPath: exported.appendingPathComponent("unexpected-script.sh").path))
        let imported = try store.importPack(exported)
        precondition(imported.id != saved.id && imported.pack.widgets == pack.widgets)
        try store.export(saved, to: exported) // Existing destination replaced safely.
        try check(try ScenePackStore.read(exported).pack.name == pack.name)
        let restarted = ScenePackStore(root: store.root)
        try check(try restarted.list().count == 2)
        let media = root.appendingPathComponent("source.mp4")
        let audio = root.appendingPathComponent("source.wav")
        try Data([0,1,2,3]).write(to: media); try Data([4,5,6]).write(to: audio)
        let mediaID = UUID().uuidString
        let mediaPack = ScenePack(name: "Portable media", selected: mediaID, scenes: [PackedScene(id: mediaID, name: "Video", palette: 0, builtin: nil, video: "video.mp4", sound: WallpaperSound(file: "audio.wav"))], widgetsEnabled: false, widgets: [], corner: "Bottom left", automatic: false)
        let mediaSaved = try store.save(mediaPack, sources: ["video.mp4": media, "audio.wav": audio])
        try fm.removeItem(at: media); try fm.removeItem(at: audio)
        let portable = try store.importPack(mediaSaved.url)
        try check(try Data(contentsOf: ScenePackStore.safeFile("video.mp4", in: portable.url)) == Data([0,1,2,3]))
        let serialized = try String(contentsOf: portable.url.appendingPathComponent("Scene.json"), encoding: .utf8)
        precondition(!serialized.contains(root.path))
        do { _ = try await ScenePackInstaller.install(portable, support: root.appendingPathComponent("Rejected")); fatalError("Invalid video accepted") } catch { }
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("Rejected").path))
        func reject(_ mutated: ScenePack) throws {
            let url = root.appendingPathComponent("Bad.stillscene")
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try JSONEncoder().encode(mutated).write(to: url.appendingPathComponent("Scene.json"))
            do { _ = try ScenePackStore.read(url); fatalError("Malformed pack accepted") } catch { }
        }
        var bad = mediaPack; bad.scenes[0].video = "../source.mp4"; try reject(bad)
        bad = pack; bad.version = 99; try reject(bad)
        bad = pack; bad.widgets = [pack.widgets[0], pack.widgets[0]]; try reject(bad)
        bad = pack; bad.widgets[0].position = WidgetPosition(x: -0.1, y: 0.5); try reject(bad)
        bad = pack; bad.id = UUID().uuidString; bad.version = 1; let legacyPackage = try store.save(bad, sources: [:]); try check(try ScenePackStore.read(legacyPackage.url).pack.version == 1)
        bad = pack; bad.automatic = true; try reject(bad)
        let victim = portable.url.appendingPathComponent("Assets/video.mp4")
        try fm.removeItem(at: victim)
        try fm.createSymbolicLink(at: victim, withDestinationURL: exported.appendingPathComponent("Scene.json"))
        do { _ = try ScenePackStore.read(portable.url); fatalError("Linked media accepted") } catch { }
        try store.remove(saved)
        try check(try ScenePackStore.read(exported).pack.name == pack.name)
        if CommandLine.arguments.count > 1 {
            let originalMovie = URL(fileURLWithPath: CommandLine.arguments[1])
            let realID = UUID().uuidString
            let realPack = ScenePack(name: "Real MP4 check", selected: realID, scenes: [PackedScene(id: realID, name: "Video", palette: 2, builtin: nil, video: "wallpaper.mp4", sound: WallpaperSound(enabled: false))], widgetsEnabled: true, widgets: [DesktopWidget(kind: .text, text: "Saved setup")], corner: "Bottom right", automatic: false)
            let real = try store.save(realPack, sources: ["wallpaper.mp4": originalMovie])
            let support = root.appendingPathComponent("AppliedVideo")
            let applied = try await ScenePackInstaller.install(real, support: support)
            let again = try await ScenePackInstaller.install(real, support: support)
            precondition(applied.selected == again.selected && applied.scenes[0].file == again.scenes[0].file)
            precondition(applied.pack.widgets[0].text == "Saved setup" && applied.pack.corner == "Bottom right")
            try store.remove(real)
            precondition(fm.fileExists(atPath: applied.scenes[0].file!))
            print("PASS: real MP4 preparation, stable repeated apply, widget/corner settings, and applied media survives pack removal")
        }
        print("PASS: pack persistence, portable media, fresh import IDs, built-in apply settings, export replacement, selective export, malformed manifests, traversal, symlinks, invalid video rollback, and independent removal")
    }
}
