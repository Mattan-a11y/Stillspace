import Foundation
import AppKit
import AVFoundation
@main struct Check {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Stillspace-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("aerials/manifest"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("aerials")
        let manifest = root.appendingPathComponent("manifest/entries.json")
        let liveCatalog = try Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json"))
        var clean = try JSONSerialization.jsonObject(with: liveCatalog) as! [String: Any]
        clean["assets"] = (clean["assets"] as! [[String: Any]]).filter { !($0["categories"] as? [String] ?? []).contains(LockScreenLibrary.categoryID) }
        clean["categories"] = (clean["categories"] as! [[String: Any]]).filter { $0["id"] as? String != LockScreenLibrary.categoryID }
        let original = try JSONSerialization.data(withJSONObject: clean)
        try original.write(to: manifest)
        let archiveURL = root.appendingPathComponent("manifest.tar")
        let liveArchive = try Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest.tar"))
        let originalArchive = try LockScreenLibrary.replacingCatalog(in: liveArchive, with: original)
        try originalArchive.write(to: archiveURL)
        func archiveEntry(_ data: Data) -> Data {
            let digits = String(decoding: data[124..<136], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
            let count = Int(digits, radix: 8)!
            return data.subdata(in: 512..<(512 + count))
        }
        let library = LockScreenLibrary(root: root, support: folder.appendingPathComponent("support"))
        try await library.prepare(Landscape.builtins[2])
        let data = try Data(contentsOf: manifest)
        let catalog = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let initial = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        let updatedArchive = try Data(contentsOf: archiveURL)
        let archiveCatalog = try JSONSerialization.jsonObject(with: archiveEntry(updatedArchive)) as! NSDictionary
        precondition(archiveCatalog == (catalog as NSDictionary))
        let oldPadding = ((archiveEntry(originalArchive).count + 511) / 512) * 512
        let newPadding = ((archiveEntry(updatedArchive).count + 511) / 512) * 512
        precondition(originalArchive.suffix(from: 512 + oldPadding) == updatedArchive.suffix(from: 512 + newPadding))
        let entries = catalog["assets"] as! [[String: Any]]
        let added = entries.first!
        precondition(added["accessibilityLabel"] as! String == "Blue hour")
        precondition(entries.count == (initial["assets"] as! [Any]).count + 1)
        let movie = URL(string: added["url-4K-SDR-240FPS"] as! String)!
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration)
        precondition(abs(duration.seconds - 120) < 0.1)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        precondition(audio.isEmpty)
        let thumbnail = URL(string: added["previewImage"] as! String)!
        try FileManager.default.copyItem(at: thumbnail, to: URL(fileURLWithPath: CommandLine.arguments[1]))
        try library.removeAll()
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! NSDictionary
        precondition(restored == (initial as NSDictionary))
        let restoredArchive = try JSONSerialization.jsonObject(with: archiveEntry(Data(contentsOf: archiveURL))) as! NSDictionary
        precondition(restoredArchive == restored)
        print("PASS: HEVC scene export, 120-second silent video, valid preview, catalog preservation and selective removal")
    }
}
