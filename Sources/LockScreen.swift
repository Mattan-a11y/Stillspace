import SwiftUI
import AppKit
import AVFoundation

/// The user-space aerial catalog is an undocumented macOS integration.
/// Never edits system files, login security, Apple's assets, or the desktop selection.
@MainActor final class LockScreenLibrary {
    static let categoryID = "0E2F9B8E-3C76-4DA1-A750-4C68A9D13F63"
    static let subcategoryID = "A9B8C7D6-0201-4F55-9163-794ED23FA892"
    let root: URL
    let support: URL
    private var manifestURL: URL { root.appendingPathComponent("manifest/entries.json") }
    init(root: URL? = nil, support: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.root = root ?? home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
        self.support = support ?? home.appendingPathComponent("Library/Application Support/Stillspace/LockScreen")
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "Stillspace.LockScreen", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    func prepare(_ scene: Landscape) async throws {
        guard #available(macOS 26, *) else { throw failure("Animated lock-screen preparation requires macOS 26.") }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw failure("Open System Settings → Wallpaper and choose an Apple aerial once to initialize the wallpaper library, then try again.") }
        if let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any], let assets = catalog["assets"] as? [[String: Any]], assets.contains(where: { entry in
            guard entry["shotID"] as? String == "STILLSPACE_V2_" + scene.id, let value = entry["url-4K-SDR-240FPS"] as? String, let url = URL(string: value) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }) { refreshPicker(); return }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let work = support.appendingPathComponent("Work-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let source: URL
        if let file = scene.file { source = URL(fileURLWithPath: file) }
        else { source = work.appendingPathComponent("scene.mov"); try await renderScene(scene.palette, to: source) }
        let output = work.appendingPathComponent("wallpaper.mov")
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw failure("No video track was found.") }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric && duration.seconds > 0 else { throw failure("This video has an invalid duration.") }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw failure("Could not prepare video.") }
        video.preferredTransform = try await track.load(.preferredTransform)
        // Aerials may freeze at the end. Provide a two-minute silent sequence,
        // rather than pretending this renderer has AVPlayerLooper semantics.
        var cursor = CMTime.zero
        let end = CMTime(seconds: 120, preferredTimescale: 600)
        while cursor < end {
            let length = CMTimeMinimum(duration, CMTimeSubtract(end, cursor))
            try video.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: cursor)
            cursor = CMTimeAdd(cursor, length)
        }
        let fps = try await track.load(.nominalFrameRate)
        try await LockScreenEncoder.transcode(composition, fps: fps, to: output)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 900, height: 580)
        let image = try await generator.image(at: .zero).image
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("Could not create the wallpaper preview.") }
        let id = UUID().uuidString.uppercased()
        try register(id: id, name: scene.name, sceneID: scene.id, movie: output, thumbnail: png)
        refreshPicker()
    }
    func register(id: String, name: String, sceneID: String, movie: URL, thumbnail: Data) throws {
        // Re-read immediately before editing; preserve all unknown fields and other entries.
        let original = try Data(contentsOf: manifestURL)
        guard var catalog = try JSONSerialization.jsonObject(with: original) as? [String: Any], var assets = catalog["assets"] as? [[String: Any]], var categories = catalog["categories"] as? [[String: Any]] else { throw failure("The macOS wallpaper catalog has changed. No catalog edits were made.") }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let backup = support.appendingPathComponent("Original-catalog.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        let movieURL = root.appendingPathComponent("videos/" + id + ".mov")
        let thumbURL = root.appendingPathComponent("thumbnails/" + id + ".png")
        try FileManager.default.createDirectory(at: movieURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: movie, to: movieURL)
        do {
            try thumbnail.write(to: thumbURL, options: .atomic)
            let sub: [String: Any] = ["id": Self.subcategoryID, "localizedNameKey": "Stillspace", "localizedDescriptionKey": "Your personal wallpapers", "preferredOrder": 0, "representativeAssetID": id, "previewImage": thumbURL.absoluteString]
            categories.removeAll { $0["id"] as? String == Self.categoryID }
            categories.insert(["id": Self.categoryID, "localizedNameKey": "Stillspace", "localizedDescriptionKey": "Your personal wallpapers", "preferredOrder": -1, "representativeAssetID": id, "previewImage": thumbURL.absoluteString, "subcategories": [sub]], at: 0)
            assets.insert(["id": id, "accessibilityLabel": name, "localizedNameKey": name, "shotID": "STILLSPACE_V2_" + sceneID, "preferredOrder": 0, "includeInShuffle": false, "showInTopLevel": true, "categories": [Self.categoryID], "subcategories": [Self.subcategoryID], "pointsOfInterest": [String: String](), "previewImage": thumbURL.absoluteString, "url-4K-SDR-240FPS": movieURL.absoluteString], at: 0)
            catalog["assets"] = assets; catalog["categories"] = categories
            let updated = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
            guard try Data(contentsOf: manifestURL) == original else { throw failure("macOS updated its wallpaper catalog while preparing. Try again.") }
            try writeCatalog(updated, expected: original)
        } catch { try? FileManager.default.removeItem(at: movieURL); try? FileManager.default.removeItem(at: thumbURL); throw error }
    }
    func removeAll() throws {
        let original = try Data(contentsOf: manifestURL)
        guard var catalog = try JSONSerialization.jsonObject(with: original) as? [String: Any], var assets = catalog["assets"] as? [[String: Any]], var categories = catalog["categories"] as? [[String: Any]] else { throw failure("The wallpaper catalog could not be read.") }
        let owned = assets.filter { ($0["categories"] as? [String])?.contains(Self.categoryID) == true }
        guard !owned.isEmpty else { return }
        assets.removeAll { ($0["categories"] as? [String])?.contains(Self.categoryID) == true }
        categories.removeAll { $0["id"] as? String == Self.categoryID }
        catalog["assets"] = assets; catalog["categories"] = categories
        let updated = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
        guard try Data(contentsOf: manifestURL) == original else { throw failure("macOS changed its catalog. Try again.") }
        try writeCatalog(updated, expected: original)
        // Keep video files while macOS may still have them selected. Their paths
        // are recorded for manual cleanup after selecting a different wallpaper.
        let paths = owned.compactMap { $0["id"] as? String }.flatMap { [root.appendingPathComponent("videos/" + $0 + ".mov").path, root.appendingPathComponent("thumbnails/" + $0 + ".png").path] }
        try JSONSerialization.data(withJSONObject: paths, options: .prettyPrinted).write(to: support.appendingPathComponent("Retired-files.json"), options: .atomic)
        refreshPicker()
    }
    private func writeCatalog(_ updated: Data, expected original: Data) throws {
        let archiveURL = root.appendingPathComponent("manifest.tar")
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            try updated.write(to: manifestURL, options: .atomic); return
        }
        let archive = try Data(contentsOf: archiveURL)
        let replacement = try Self.replacingCatalog(in: archive, with: updated)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let backup = support.appendingPathComponent("Original-manifest.tar")
        if !FileManager.default.fileExists(atPath: backup.path) { try archive.write(to: backup, options: .atomic) }
        guard try Data(contentsOf: archiveURL) == archive, try Data(contentsOf: manifestURL) == original else { throw failure("macOS changed the wallpaper cache. Try again.") }
        try replacement.write(to: archiveURL, options: .atomic)
        do {
            guard try Data(contentsOf: manifestURL) == original else { throw failure("macOS changed the wallpaper catalog. Try again.") }
            try updated.write(to: manifestURL, options: .atomic)
        } catch { try? archive.write(to: archiveURL, options: .atomic); throw error }
    }
    /// Replace only the first regular-file tar member; preserve every other byte,
    /// including localization bundles. No extraction or shell commands required.
    static func replacingCatalog(in archive: Data, with catalog: Data) throws -> Data {
        func invalid() -> NSError { NSError(domain: "Stillspace.LockScreen", code: 3, userInfo: [NSLocalizedDescriptionKey: "The macOS wallpaper archive format changed. Its contents were preserved."]) }
        guard archive.count >= 1024 else { throw invalid() }
        var header = Data(archive.prefix(512))
        let name = String(decoding: header.prefix(100).prefix { $0 != 0 }, as: UTF8.self)
        let sizeText = String(decoding: header[124..<136], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        guard name == "entries.json", header[156] == 0 || header[156] == 48, let oldSize = Int(sizeText, radix: 8) else { throw invalid() }
        let offset = 512 + ((oldSize + 511) / 512) * 512
        guard oldSize >= 0, offset <= archive.count, catalog.count < 8_589_934_592 else { throw invalid() }
        let size = String(catalog.count, radix: 8)
        header.replaceSubrange(124..<136, with: Data((String(repeating: "0", count: 11 - size.count) + size + "\0").utf8))
        header.replaceSubrange(148..<156, with: Data(repeating: 32, count: 8))
        let checksum = header.reduce(0) { $0 + Int($1) }
        let digits = String(checksum, radix: 8)
        header.replaceSubrange(148..<156, with: Data((String(repeating: "0", count: 6 - digits.count) + digits + "\0 ").utf8))
        var result = header; result.append(catalog)
        result.append(Data(count: (512 - catalog.count % 512) % 512)); result.append(archive.suffix(from: offset))
        return result
    }
    private func refreshPicker() {
        guard root == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials") else { return }
        for identifier in ["com.apple.wallpaper.extension.aerials", "com.apple.wallpaper.agent"] {
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).forEach { if !$0.terminate() { _ = $0.forceTerminate() } }
        }
    }
    private func renderScene(_ palette: Int, to url: URL) async throws {
        let width = 1280, height = 720, fps = 20, frames = 240
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Could not render scene.") }; writer.startSession(atSourceTime: .zero)
        do {
            for frame in 0..<frames {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? failure("Scene renderer stopped.") }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                guard let pool = adaptor.pixelBufferPool else { throw failure("No video frame buffer.") }
                var result: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &result)
                guard let buffer = result else { throw failure("Could not allocate video frame.") }
                CVPixelBufferLockBaseAddress(buffer, [])
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { CVPixelBufferUnlockBaseAddress(buffer, []); throw failure("Could not draw video frame.") }
                let view = LandscapeView(palette: palette, fixedTime: Double(frame) / Double(fps)).frame(width: CGFloat(width), height: CGFloat(height))
                let renderer = ImageRenderer(content: view); renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
                renderer.render { _, draw in draw(context) }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else { throw writer.error ?? failure("Could not encode video frame.") }
                if frame % 8 == 0 { await Task.yield() }
            }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? failure("Scene rendering failed.") }
        } catch { writer.cancelWriting(); throw error }
    }
}
