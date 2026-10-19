import Foundation

struct PackedScene: Codable, Identifiable {
    var id: String
    var name: String
    var palette: Int
    var builtin: String?
    var video: String?
    var sound: WallpaperSound
}
struct ScenePack: Codable, Identifiable {
    var version = 2
    var id = UUID().uuidString
    var name: String
    var selected: String
    var scenes: [PackedScene]
    var widgetsEnabled: Bool
    var widgets: [DesktopWidget]
    var corner: String
    var automatic: Bool
    var created = Date()
}
struct SavedScenePack: Identifiable {
    let pack: ScenePack
    let url: URL
    var id: String { pack.id }
    var preview: Landscape {
        let scene = pack.scenes.first { $0.id == pack.selected } ?? pack.scenes[0]
        return Landscape(id: pack.id, name: pack.name, subtitle: "Scene pack", palette: scene.palette, file: scene.video.map { url.appendingPathComponent("Assets/" + $0).path })
    }
}

/// Local packages contain only a versioned manifest and flat media assets.
/// No scripts, network URLs, executable plugins, or absolute source paths.
struct ScenePackStore {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Stillspace/ScenePacks")
    }
    static func problem(_ message: String) -> NSError { NSError(domain: "Stillspace.ScenePacks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func list() throws -> [SavedScenePack] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "stillscene" }
            .compactMap { try? Self.read($0) }
            .sorted { $0.pack.created > $1.pack.created }
    }
    static func safeFile(_ name: String, in root: URL) throws -> URL {
        guard !name.isEmpty, name.count <= 100, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.hasPrefix(".") else { throw problem("This pack contains an invalid media path.") }
        let assetRoot = root.appendingPathComponent("Assets")
        guard assetRoot.resolvingSymlinksInPath().standardizedFileURL == assetRoot.standardizedFileURL else { throw problem("Linked media folders are not supported.") }
        let file = assetRoot.appendingPathComponent(name)
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, file.resolvingSymlinksInPath().standardizedFileURL == file.standardizedFileURL, (info.fileSize ?? 0) <= 2_000_000_000 else { throw problem("A media file is missing, linked, or larger than 2 GB.") }
        return file
    }
    static func read(_ url: URL) throws -> SavedScenePack {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw problem("Choose a Stillspace scene pack.") }
        let manifest = url.appendingPathComponent("Scene.json")
        let meta = try manifest.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard meta.isRegularFile == true, meta.isSymbolicLink != true, (meta.fileSize ?? 0) <= 1_000_000 else { throw problem("This scene pack has an invalid manifest.") }
        let pack = try JSONDecoder().decode(ScenePack.self, from: Data(contentsOf: manifest))
        guard (1...2).contains(pack.version) else { throw problem("This scene pack needs a newer version of Stillspace.") }
        guard UUID(uuidString: pack.id) != nil, !pack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, pack.name.count <= 80, (1...4).contains(pack.scenes.count), Set(pack.scenes.map(\.id)).count == pack.scenes.count, pack.scenes.contains(where: { $0.id == pack.selected }), pack.widgets.count <= 16, Set(pack.widgets.map(\.id)).count == pack.widgets.count, ["Top left", "Top right", "Bottom left", "Bottom right"].contains(pack.corner) else { throw problem("This scene pack has invalid settings.") }
        for widget in pack.widgets { guard widget.size.isFinite, (12...96).contains(widget.size), widget.text.count <= 1000, widget.position.map({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) ?? true else { throw problem("This pack contains an invalid widget.") } }
        for scene in pack.scenes {
            guard UUID(uuidString: scene.id) != nil, !scene.name.isEmpty, scene.name.count <= 200, (0...2).contains(scene.palette), scene.sound.volume.isFinite, (0...1).contains(scene.sound.volume) else { throw problem("This pack contains an invalid scene.") }
            if let builtin = scene.builtin {
                guard Landscape.builtins.contains(where: { $0.id == builtin }), scene.video == nil else { throw problem("Unknown built-in wallpaper.") }
            } else {
                guard let video = scene.video, video.hasSuffix(".mp4") else { throw problem("This pack is missing its MP4 wallpaper.") }
                _ = try safeFile(video, in: url)
            }
            if let audio = scene.sound.file { _ = try safeFile(audio, in: url) }
        }
        if pack.automatic { guard Set(pack.scenes.compactMap(\.builtin)).isSuperset(of: ["dawn", "day", "night"]) else { throw problem("This day/night pack is missing a scheduled scene.") } }
        return SavedScenePack(pack: pack, url: url)
    }
    func save(_ pack: ScenePack, sources: [String: URL]) throws -> SavedScenePack {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temporary = root.appendingPathComponent(".work-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        for (name, source) in sources {
            guard name == source.lastPathComponent || (!name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")) else { throw Self.problem("Invalid asset name.") }
            try FileManager.default.copyItem(at: source, to: temporary.appendingPathComponent("Assets/" + name))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pack).write(to: temporary.appendingPathComponent("Scene.json"), options: .atomic)
        _ = try Self.read(temporary)
        let target = root.appendingPathComponent(pack.id + ".stillscene")
        try FileManager.default.moveItem(at: temporary, to: target)
        return try Self.read(target)
    }
    func importPack(_ url: URL) throws -> SavedScenePack {
        let original = try Self.read(url)
        var pack = original.pack; pack.id = UUID().uuidString; pack.created = Date()
        var sources: [String: URL] = [:]
        for scene in pack.scenes {
            for name in [scene.video, scene.sound.file].compactMap({ $0 }) { sources[name] = try Self.safeFile(name, in: url) }
        }
        return try save(pack, sources: sources)
    }
    func export(_ item: SavedScenePack, to destination: URL) throws {
        let current = try Self.read(item.url)
        guard destination.standardizedFileURL != item.url.standardizedFileURL else { throw Self.problem("Choose another location for the exported copy.") }
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".stillspace-export-" + UUID().uuidString)
        let backup = parent.appendingPathComponent(".stillspace-backup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.createDirectory(at: stage.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: item.url.appendingPathComponent("Scene.json"), to: stage.appendingPathComponent("Scene.json"))
        let names = Set(current.pack.scenes.flatMap { [$0.video, $0.sound.file].compactMap { $0 } })
        for name in names { try FileManager.default.copyItem(at: Self.safeFile(name, in: item.url), to: stage.appendingPathComponent("Assets/" + name)) }
        let existed = FileManager.default.fileExists(atPath: destination.path)
        if existed { try FileManager.default.moveItem(at: destination, to: backup) }
        do { try FileManager.default.moveItem(at: stage, to: destination) }
        catch { if existed { try? FileManager.default.moveItem(at: backup, to: destination) }; throw error }
        if existed { try? FileManager.default.removeItem(at: backup) }
    }
    func remove(_ item: SavedScenePack) throws {
        guard item.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw Self.problem("This pack is outside the local library.") }
        try FileManager.default.removeItem(at: item.url)
    }
}

import AVFoundation
struct InstalledScenePack {
    var pack: ScenePack
    var scenes: [Landscape]
    var selected: String
    var sounds: [String: WallpaperSound]
}
enum ScenePackInstaller {
    static func install(_ item: SavedScenePack, support: URL? = nil) async throws -> InstalledScenePack {
        let verified = try ScenePackStore.read(item.url)
        let pack = verified.pack
        let support = support ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Stillspace")
        var result = InstalledScenePack(pack: pack, scenes: [], selected: "", sounds: [:])
        var copied: [URL] = []
        func copy(_ name: String, folder: String) throws -> String {
            let source = try ScenePackStore.safeFile(name, in: item.url)
            let destination = support.appendingPathComponent(folder + "/pack-" + pack.id + "-" + name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination); copied.append(destination)
            }
            return destination.path
        }
        do {
            // Validate every asset before copying or changing any desktop settings.
            for scene in pack.scenes {
                if let video = scene.video {
                    let asset = AVURLAsset(url: try ScenePackStore.safeFile(video, in: item.url))
                    guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw ScenePackStore.problem("A wallpaper in this pack is not a playable video.") }
                }
                if let audio = scene.sound.file { _ = try AVAudioPlayer(contentsOf: ScenePackStore.safeFile(audio, in: item.url)) }
            }
            for scene in pack.scenes {
                let id = scene.builtin ?? "pack-" + pack.id + "-" + scene.id
                let landscape = Landscape(id: id, name: scene.name, subtitle: "Scene pack · " + pack.name, palette: scene.palette, file: try scene.video.map { try copy($0, folder: "Imports") })
                result.scenes.append(landscape)
                var sound = scene.sound
                sound.file = try sound.file.map { try copy($0, folder: "Audio") }
                result.sounds[id] = sound
                if scene.id == pack.selected { result.selected = id }
            }
            return result
        } catch { copied.forEach { try? FileManager.default.removeItem(at: $0) }; throw error }
    }
}
