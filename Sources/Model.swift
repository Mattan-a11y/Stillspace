import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import ServiceManagement

struct Landscape: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var palette: Int
    var file: String? = nil
    static let builtins = [Landscape(id: "dawn", name: "First light", subtitle: "Alpine air · Morning", palette: 0), Landscape(id: "day", name: "Quiet tide", subtitle: "Coastal calm · Afternoon", palette: 1), Landscape(id: "night", name: "Blue hour", subtitle: "After the world slows down", palette: 2)]
}
enum WidgetKind: String, Codable, CaseIterable, Identifiable { case clock = "Clock", date = "Date", text = "Custom text", system = "Mac info"; var id: String { rawValue } }
enum WidgetFont: String, Codable, CaseIterable, Identifiable {
    case rounded = "Rounded", system = "System", serif = "Serif", mono = "Monospaced"
    var id: String { rawValue }
}
enum WidgetTint: String, Codable, CaseIterable, Identifiable {
    case white = "White", cream = "Cream", mint = "Mint", sky = "Sky", lavender = "Lavender", pink = "Pink"
    var id: String { rawValue }
}
struct WidgetPosition: Codable, Equatable { var x: Double; var y: Double }
struct DesktopWidget: Identifiable, Codable, Equatable {
    var id: String
    var kind: WidgetKind
    var text: String
    var size: Double
    var position: WidgetPosition?
    var font: WidgetFont
    var tint: WidgetTint
    init(id: String = UUID().uuidString, kind: WidgetKind, text: String = "Your thought here", size: Double = 28, position: WidgetPosition? = nil, font: WidgetFont = .rounded, tint: WidgetTint = .white) {
        self.id = id; self.kind = kind; self.text = text; self.size = size; self.position = position; self.font = font; self.tint = tint
    }
    enum CodingKeys: String, CodingKey { case id, kind, text, size, position, font, tint }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); kind = try values.decode(WidgetKind.self, forKey: .kind)
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? "Your thought here"
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? 28
        position = try values.decodeIfPresent(WidgetPosition.self, forKey: .position)
        font = try values.decodeIfPresent(WidgetFont.self, forKey: .font) ?? .rounded
        tint = try values.decodeIfPresent(WidgetTint.self, forKey: .tint) ?? .white
    }
}
struct WallpaperSound: Codable, Equatable {
    var enabled = true
    var volume: Double = 0.5
    var file: String? = nil
}
@MainActor final class Studio: ObservableObject {
    @Published var displays = ConnectedDisplay.all
    @Published var displayChoices: [String: DisplayChoice] = [:] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(displayChoices), forKey: "displayChoices"); refresh() } }
    @Published var packs: [SavedScenePack] = []
    @Published var packBusy = false
    @Published var packMessage: String?
    private var applyingPack = false
    let packStore = ScenePackStore()
    @Published var scenes = Landscape.builtins
    @Published var selected = "dawn" { didSet { save(); refresh() } }
    @Published var favorites: Set<String> = [] { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    @Published var running = false { didSet { UserDefaults.standard.set(running, forKey: "wasPlaying") } }
    @Published var restorePlayback = true { didSet { UserDefaults.standard.set(restorePlayback, forKey: "restorePlayback") } }
    @Published var pauseInLowPowerMode = true { didSet { UserDefaults.standard.set(pauseInLowPowerMode, forKey: "pauseInLowPowerMode"); refresh() } }
    @Published var pauseOnBattery = true { didSet { UserDefaults.standard.set(pauseOnBattery, forKey: "pauseOnBattery"); refresh() } }
    @Published private(set) var pauseReason: String?
    var previewsAllowed: Bool { appActive && pauseReason == nil }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var lockBusy = false
    @Published var lockMessage: String?
    let lockScreen = LockScreenLibrary()
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { self.error = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    func prepareLockScreen(_ scene: Landscape) {
        guard !lockBusy else { return }; lockBusy = true; lockMessage = "Preparing \(scene.name)…"
        Task {
            defer { lockBusy = false }
            do { try await lockScreen.prepare(scene); lockMessage = "Prepared \(scene.name). Open macOS Wallpaper → Screen Saver → Custom and choose it under Stillspace. If the picker was already open, close and reopen it. Do not change the desktop wallpaper selection. Lock-screen sound and widgets are excluded."; NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!) }
            catch { lockMessage = nil; self.error = error.localizedDescription }
        }
    }
    func startScreenSaver() {
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"), configuration: NSWorkspace.OpenConfiguration())
            } catch { self.error = error.localizedDescription }
        }
    }
    func removeLockScreenLibrary() { do { try lockScreen.removeAll(); lockMessage = "Stillspace’s lock-screen entries were removed. Your other wallpapers were preserved." } catch { self.error = error.localizedDescription } }
    @Published var automatic = false { didSet { save(); configureScheduleTimer(); schedule() } }
    @Published var widgets = false { didSet { save(); refresh() } }
    @Published var widgetItems: [DesktopWidget] = [] { didSet { save(); refresh() } }
    @Published var widgetCorner = "Top right" { didSet { save(); refresh() } }
    @Published var sounds: [String: WallpaperSound] = [:] { didSet { save(); if running && !applyingPack { desktop.configureAudio(sound(for: selected)) } } }
    @Published var appActive = true
    func sound(for id: String) -> WallpaperSound { sounds[id] ?? WallpaperSound() }
    func updateSound(_ id: String, _ update: (inout WallpaperSound) -> Void) { var value = sound(for: id); update(&value); sounds[id] = value }
    func attachSound(to id: String) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                guard !(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)).isEmpty else { throw NSError(domain: "Stillspace", code: 2, userInfo: [NSLocalizedDescriptionKey: "This file has no playable audio track."]) }
                _ = try AVAudioPlayer(contentsOf: url)
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Stillspace/Audio")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                try FileManager.default.copyItem(at: url, to: target)
                let previous = sound(for: id).file
                updateSound(id) { $0.file = target.path; $0.enabled = true }
                deleteOwnedAudio(previous)
            } catch { self.error = error.localizedDescription }
        }
    }
    @Published var error: String?
    @Published var asleep = false
    private var sessionInactive = false
    private var rebuildDesktop = false
    let desktop = DesktopController()
    private var powerMonitor: PowerMonitor?
    private var timer: Timer?
    private var observations: [NSObjectProtocol] = []
    var current: Landscape { scenes.first { $0.id == selected } ?? scenes[0] }
    init() {
        let d = UserDefaults.standard
        StillspaceLifecycle.studio = self
        if let data = d.data(forKey: "displayChoices"), let choices = try? JSONDecoder().decode([String: DisplayChoice].self, from: data) { displayChoices = choices }
        desktop.onFailure = { [weak self] message in self?.running = false; self?.desktop.stop(); self?.error = message }
        packs = (try? packStore.list()) ?? []
        restorePlayback = d.object(forKey: "restorePlayback") == nil ? true : d.bool(forKey: "restorePlayback")
        pauseInLowPowerMode = d.object(forKey: "pauseInLowPowerMode") == nil ? true : d.bool(forKey: "pauseInLowPowerMode")
        pauseOnBattery = d.object(forKey: "pauseOnBattery") == nil ? true : d.bool(forKey: "pauseOnBattery")
        let resume = restorePlayback && d.bool(forKey: "wasPlaying")
        favorites = Set(d.stringArray(forKey: "favorites") ?? [])
        if let data = d.data(forKey: "imports"), let imported = try? JSONDecoder().decode([Landscape].self, from: data) { scenes += imported.filter { FileManager.default.fileExists(atPath: $0.file ?? "") } }
        selected = d.string(forKey: "scene") ?? "dawn"
        automatic = d.bool(forKey: "automatic")
        if let data = d.data(forKey: "customWidgets"), let items = try? JSONDecoder().decode([DesktopWidget].self, from: data) { widgetItems = items; widgets = d.bool(forKey: "widgets") }
        widgetCorner = d.string(forKey: "widgetCorner") ?? "Top right"
        if let data = d.data(forKey: "wallpaperSounds"), let value = try? JSONDecoder().decode([String: WallpaperSound].self, from: data) { sounds = value }
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.appActive = false } })
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.appActive = true } })
        configureScheduleTimer()
        powerMonitor = PowerMonitor()
        powerMonitor?.changed = { [weak self] in self?.refresh() }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        }
        let center = NSWorkspace.shared.notificationCenter
        observations.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sessionInactive = true; self?.refresh() } })
        observations.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sessionInactive = false; self?.refresh() } })
        observations.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.asleep = true; self?.refresh() } })
        observations.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.asleep = false; self?.refresh() } })
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.displays = ConnectedDisplay.all; self?.refresh(force: true) } })
        d.removeObject(forKey: "focusState")
        schedule(); refresh(); if resume { running = true; refresh() }
    }
    func save() {
        guard !applyingPack else { return }
        let d = UserDefaults.standard
        d.set(selected, forKey: "scene"); d.set(automatic, forKey: "automatic"); d.set(widgets, forKey: "widgets"); d.set(try? JSONEncoder().encode(sounds), forKey: "wallpaperSounds"); d.set(try? JSONEncoder().encode(widgetItems), forKey: "customWidgets"); d.set(widgetCorner, forKey: "widgetCorner")
        d.set(try? JSONEncoder().encode(scenes.filter { $0.file != nil }), forKey: "imports")
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }
    func apply(_ scene: Landscape) {
        automatic = false
        if selected != scene.id { selected = scene.id }
        if !running { running = true; refresh() }
    }
    func toggleDesktop() { running.toggle(); if running { refresh() } else { desktop.stop() } }
    func refresh(force: Bool = false) {
        let reason = PlaybackPolicy.reason(asleep: asleep, locked: sessionInactive, battery: PowerMonitor.onBattery,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            hot: ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical,
            pauseBattery: pauseOnBattery, pauseLowPower: pauseInLowPowerMode)
        if pauseReason != reason { pauseReason = reason }
        guard running && !applyingPack else { return }
        if force { rebuildDesktop = true }
        if reason != nil { desktop.pause(true); return }
        desktop.show(current, widgets: widgets ? widgetItems : [], corner: widgetCorner, force: rebuildDesktop, scenes: scenes, choices: displayChoices)
        rebuildDesktop = false
        guard running else { return }
        desktop.pause(false)
        desktop.configureAudio(sound(for: selected))
    }
    private func configureScheduleTimer() {
        timer?.invalidate(); timer = nil
        guard automatic else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.schedule() } }
        timer?.tolerance = 5
    }
    func schedule() {
        guard automatic && !applyingPack else { return }
        let h = Calendar.current.component(.hour, from: Date())
        let id = h < 6 || h >= 19 ? "night" : h < 12 ? "dawn" : "day"
        if selected != id { selected = id }
    }
    func useOriginalSound(_ id: String) { let previous = sound(for: id).file; updateSound(id) { $0.file = nil }; deleteOwnedAudio(previous) }
    private func deleteOwnedAudio(_ file: String?) {
        guard let file else { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Stillspace/Audio").standardizedFileURL
        let url = URL(fileURLWithPath: file).standardizedFileURL
        if ManagedMedia.deletable(url, in: folder) && !sounds.values.contains(where: { $0.file == file }) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
    func applyWidgetLayout(_ items: [DesktopWidget], enabled: Bool) {
        applyingPack = true
        widgetItems = items; widgets = enabled && !items.isEmpty
        applyingPack = false; save(); refresh()
    }
    func saveScenePack(named name: String, starter: Bool = false) {
        guard !packBusy else { return }
        let sceneList = starter ? [Landscape.builtins[2]] : automatic ? Landscape.builtins : [current]
        var sources: [String: URL] = [:]
        let entries: [PackedScene] = sceneList.map { scene in
            let id = UUID().uuidString
            var sound = starter ? WallpaperSound(enabled: false) : self.sound(for: scene.id)
            let video = scene.file.map { _ in id + ".mp4" }
            if let video, let file = scene.file { sources[video] = URL(fileURLWithPath: file) }
            if let file = sound.file {
                let source = URL(fileURLWithPath: file)
                let audio = id + "-audio." + source.pathExtension.lowercased()
                sources[audio] = source; sound.file = audio
            }
            return PackedScene(id: id, name: scene.name, palette: scene.palette, builtin: scene.file == nil ? scene.id : nil, video: video, sound: sound)
        }
        let chosen = starter ? entries[0].id : entries.first(where: { $0.builtin == selected })?.id ?? entries[0].id
        let pack = ScenePack(name: name.trimmingCharacters(in: .whitespacesAndNewlines), selected: chosen, scenes: entries, widgetsEnabled: starter || widgets, widgets: starter ? [DesktopWidget(kind: .clock)] : widgetItems, corner: starter ? "Top right" : widgetCorner, automatic: starter ? false : automatic)
        let mediaSources = sources
        packBusy = true
        Task {
            defer { packBusy = false }
            do {
                let saved = try await Task.detached(priority: .utility) { try ScenePackStore().save(pack, sources: mediaSources) }.value
                packs.insert(saved, at: 0); packMessage = "Saved “\(pack.name)”. Your media is included."
            } catch { self.error = error.localizedDescription }
        }
    }
    func importScenePack() {
        guard !packBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(importedAs: "studio.stillspace.scene-pack")]; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importScenePack(at: url)
    }
    func importScenePack(at url: URL) {
        guard !packBusy else { return }
        packBusy = true
        Task {
            defer { packBusy = false }
            do {
                let saved = try await Task.detached(priority: .utility) { try ScenePackStore().importPack(url) }.value
                packs.insert(saved, at: 0); packMessage = "Imported “\(saved.pack.name)”. Choose Apply when you’re ready."
            } catch { self.error = error.localizedDescription }
        }
    }
    func exportScenePack(_ item: SavedScenePack) {
        guard !packBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(importedAs: "studio.stillspace.scene-pack")]
        panel.nameFieldStringValue = "Scene Pack.stillscene"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        packBusy = true
        Task {
            defer { packBusy = false }
            do {
                try await Task.detached(priority: .utility) { try ScenePackStore().export(item, to: url) }.value
                packMessage = "Exported “\(item.pack.name)”. Share only media you have permission to distribute."
            } catch { self.error = error.localizedDescription }
        }
    }
    func applyScenePack(_ item: SavedScenePack) {
        guard !packBusy else { return }; packBusy = true
        Task {
            defer { packBusy = false }
            do {
                let installed = try await Task.detached(priority: .utility) { try await ScenePackInstaller.install(item) }.value
                applyingPack = true
                for entry in installed.scenes where !scenes.contains(where: { $0.id == entry.id }) { scenes.append(entry) }
                sounds.merge(installed.sounds) { _, next in next }
                widgetItems = installed.pack.widgets; widgetCorner = installed.pack.corner; widgets = installed.pack.widgetsEnabled
                selected = installed.selected; automatic = installed.pack.automatic
                applyingPack = false
                schedule(); save()
                if !running { running = true }; refresh()
                packMessage = "Applied “\(item.pack.name)”."
            } catch { applyingPack = false; self.error = error.localizedDescription }
        }
    }
    func removeScenePack(_ item: SavedScenePack) {
        guard !packBusy else { return }
        do { try packStore.remove(item); packs.removeAll { $0.id == item.id }; packMessage = "Removed saved pack. Applied wallpapers stay in your library." }
        catch { self.error = error.localizedDescription }
    }
    func importMovie() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                _ = try await VideoDetails.load(url.path)
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Stillspace/Imports")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let id = UUID().uuidString; let target = folder.appendingPathComponent(id + ".mp4")
                try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: url, to: target) }.value
                scenes.append(Landscape(id: id, name: url.deletingPathExtension().lastPathComponent, subtitle: "Your collection · MP4", palette: 2, file: target.path))
                automatic = false; selected = id; save()
            } catch { self.error = error.localizedDescription }
        }
    }
    func remove(_ scene: Landscape) {
        guard scene.file != nil else { return }
        if selected == scene.id { selected = "dawn" }
        let audio = sound(for: scene.id).file; sounds.removeValue(forKey: scene.id); deleteOwnedAudio(audio)
        for key in Array(displayChoices.keys) where displayChoices[key]?.sceneID == scene.id { var choice = displayChoices[key]!; choice.sceneID = nil; displayChoices[key] = choice }
        scenes.removeAll { $0.id == scene.id }; favorites.remove(scene.id); save()
        if let file = scene.file {
            let url = URL(fileURLWithPath: file)
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Stillspace/Imports")
            if !scenes.contains(where: { $0.file == file }) && ManagedMedia.deletable(url, in: folder) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
    }
    func shutdown() {
        timer?.invalidate(); timer = nil; powerMonitor = nil
        for observation in observations { NotificationCenter.default.removeObserver(observation); NSWorkspace.shared.notificationCenter.removeObserver(observation) }
        observations.removeAll(); desktop.shutdown()
    }
    func setDisplay(_ id: String, scene: String?) { var choice = displayChoices[id] ?? DisplayChoice(); choice.sceneID = scene; displayChoices[id] = choice }
    func setDisplayFit(_ id: String, fit: WallpaperFit) { var choice = displayChoices[id] ?? DisplayChoice(); choice.fit = fit; displayChoices[id] = choice }
    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 100, let index = scenes.firstIndex(where: { $0.id == id && $0.file != nil }) else { return }
        scenes[index].name = clean; save(); refresh()
    }
    private var referencedMedia: Set<String> { Set(scenes.compactMap(\.file) + sounds.values.compactMap(\.file)) }
    private var supportFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Stillspace") }
    func unusedMedia() throws -> [UnusedMedia] { try MediaStorage.unused(in: supportFolder, referenced: referencedMedia) }
    func trashUnusedMedia() throws {
        for file in try unusedMedia() {
            guard !referencedMedia.contains(file.url.path), ManagedMedia.deletable(file.url, in: file.url.deletingLastPathComponent()) else { continue }
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        }
    }

}
