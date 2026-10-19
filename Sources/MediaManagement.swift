import SwiftUI
import AppKit
import AVFoundation

struct VideoDetails {
    let resolution: String; let bytes: Int64; let duration: Double; let fps: Double
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    static func load(_ path: String) async throws -> VideoDetails {
        let url = URL(fileURLWithPath: path), asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Stillspace", code: 10, userInfo: [NSLocalizedDescriptionKey: "This file is not a playable video. Choose an MP4 encoded with H.264 or HEVC."])
        }
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let seconds = try await asset.load(.duration).seconds
        let fps = try await track.load(.nominalFrameRate)
        let bytes = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        return VideoDetails(resolution: "\(Int(abs(rect.width))) × \(Int(abs(rect.height)))", bytes: Int64(bytes), duration: seconds, fps: Double(fps))
    }
}
struct UnusedMedia: Identifiable { let url: URL; let bytes: Int64; var id: String { url.path } }
enum MediaStorage {
    static func unused(in support: URL, referenced: Set<String>) throws -> [UnusedMedia] {
        var results: [UnusedMedia] = []
        for name in ["Imports", "Audio"] {
            let folder = support.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
                guard !referenced.contains(url.path), ManagedMedia.deletable(url, in: folder) else { continue }
                results.append(UnusedMedia(url: url, bytes: Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)))
            }
        }
        return results.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}
@MainActor enum StillspaceLifecycle { static weak var studio: Studio?; static var showQuickControls: (() -> Void)? }
@MainActor final class StillspaceDelegate: NSObject, NSApplicationDelegate {
    private var quickControls: QuickControlsController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let studio = StillspaceLifecycle.studio {
            let controller = QuickControlsController(studio: studio); quickControls = controller
            StillspaceLifecycle.showQuickControls = { [weak controller] in controller?.show() }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
    func applicationWillTerminate(_ notification: Notification) { quickControls?.shutdown(); quickControls = nil; StillspaceLifecycle.showQuickControls = nil; StillspaceLifecycle.studio?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct DisplaySettingsView: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Your displays").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Text("Use the current wallpaper everywhere, or choose a scene for each screen.").foregroundStyle(.secondary)
            Form {
                ForEach(studio.displays) { display in
                    Section(display.name) {
                        Picker("Wallpaper", selection: Binding(get: { studio.displayChoices[display.id]?.sceneID ?? "" }, set: { studio.setDisplay(display.id, scene: $0.isEmpty ? nil : $0) })) {
                            Text("Follow current wallpaper").tag("")
                            ForEach(studio.scenes) { Text($0.name).tag($0.id) }
                        }
                        Picker("Scaling", selection: Binding(get: { studio.displayChoices[display.id]?.fit ?? .fill }, set: { studio.setDisplayFit(display.id, fit: $0) })) {
                            ForEach(WallpaperFit.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                }
            }.formStyle(.grouped)
            Text("Fill crops the edges. Fit keeps the whole image with black borders. Audio follows the current wallpaper; other scenes stay muted. Disconnected screens keep their choices.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 520, height: 450)
    }
}
struct StorageSettingsView: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var files: [UnusedMedia] = []
    @State private var message: String?
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Wallpaper storage").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Text("Unused imported videos and attached audio can be moved to the Mac’s Trash. Saved scene packs and your current library are preserved.").foregroundStyle(.secondary)
            Text("\(files.count) unused files · " + ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.bytes }, countStyle: .file)).font(.headline)
            List(files) { file in HStack { Text(file.url.lastPathComponent).lineLimit(1); Spacer(); Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)).foregroundStyle(.secondary) } }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Button("Move unused files to Trash…", role: .destructive) { confirm = true }.disabled(files.isEmpty)
        }.padding(24).frame(width: 560, height: 430)
        .task { reload() }
        .confirmationDialog("Move \(files.count) unused files to Trash?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                do { try studio.trashUnusedMedia(); message = "Moved to Trash. You can recover files in Finder." } catch { message = error.localizedDescription }; reload()
            }
        }
    }
    private func reload() { do { files = try studio.unusedMedia() } catch { message = error.localizedDescription } }
}
