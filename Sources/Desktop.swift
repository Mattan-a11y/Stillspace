import SwiftUI
import AppKit
import AVFoundation

final class VideoSurface: NSView {
    let video = AVPlayerLayer()
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = true; layer?.addSublayer(video); video.videoGravity = .resizeAspectFill }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); video.frame = bounds }
}
struct MovieView: NSViewRepresentable {
    let player: AVPlayer
    var fit: WallpaperFit = .fill
    func makeNSView(context: Context) -> VideoSurface { let v = VideoSurface(); v.video.player = player; v.video.videoGravity = fit == .fill ? .resizeAspectFill : .resizeAspect; return v }
    func updateNSView(_ nsView: VideoSurface, context: Context) { nsView.video.player = player; nsView.video.videoGravity = fit == .fill ? .resizeAspectFill : .resizeAspect }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VideoSurface, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
    static func dismantleNSView(_ nsView: VideoSurface, coordinator: ()) { nsView.video.player = nil }
}
enum WallpaperFit: String, Codable, CaseIterable, Identifiable {
    case fill = "Fill", fit = "Fit"
    var id: String { rawValue }
}
struct DisplayChoice: Codable, Equatable { var sceneID: String?; var fit: WallpaperFit = .fill }
struct ConnectedDisplay: Identifiable {
    let id: String; let name: String
    static func id(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let display = CGDirectDisplayID(number?.uint32Value ?? 0)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() { return CFUUIDCreateString(nil, uuid) as String }
        return "display-" + String(display)
    }
    @MainActor static var all: [ConnectedDisplay] { NSScreen.screens.map { ConnectedDisplay(id: id(for: $0), name: $0.localizedName) } }
}
@MainActor final class DesktopController {
    @MainActor private final class Playback {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var observation: NSKeyValueObservation?
        var itemObservation: NSKeyValueObservation?
        var looperObservation: NSKeyValueObservation?
        var failureObserver: NSObjectProtocol?
        init(path: String) {
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: path)))
        }
        func stop() {
            observation = nil; itemObservation = nil; looperObservation = nil
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            failureObserver = nil
            player.pause(); looper?.disableLooping(); looper = nil; player.removeAllItems()
        }
    }
    private var windows: [String: NSWindow] = [:]
    private var playbacks: [String: Playback] = [:]
    private var primaryVisible = false
    private var primaryID: String?
    private var soundtrack: AVAudioPlayer?
    private var audioPath: String?
    private var paused = false
    var onFailure: ((String) -> Void)?
    var previewPlayer: AVPlayer? { primaryID.flatMap { playbacks[$0]?.player } }
    var playerCount: Int { playbacks.count }
    var windowCount: Int { windows.count }
    var isPaused: Bool { paused }
    func show(_ scene: Landscape, widgets: [DesktopWidget], corner: String, force: Bool = false, scenes: [Landscape] = [], choices: [String: DisplayChoice] = [:]) {
        let screens = NSScreen.screens
        let assignments = screens.map { screen -> (NSScreen, String, Landscape, WallpaperFit) in
            let id = ConnectedDisplay.id(for: screen); let choice = choices[id]
            let selected = scenes.first { $0.id == choice?.sceneID } ?? scene
            return (screen, id, selected, choice?.fit ?? .fill)
        }
        for (_, _, selected, _) in assignments {
            if let path = selected.file, !FileManager.default.fileExists(atPath: path) {
                onFailure?("“\(selected.name)” is missing. Import the MP4 again or choose another wallpaper."); return
            }
        }
        primaryID = scene.id
        primaryVisible = assignments.contains { $0.2.id == scene.id }
        let activeDisplays = Set(assignments.map { $0.1 })
        for id in Array(windows.keys) where !activeDisplays.contains(id) { windows.removeValue(forKey: id)?.close() }
        let required = Set(assignments.compactMap { $0.2.file == nil ? nil : $0.2.id })
        for id in Array(playbacks.keys) where !required.contains(id) { playbacks.removeValue(forKey: id)?.stop() }
        for (screen, id, selected, fit) in assignments {
            if let path = selected.file, playbacks[selected.id] == nil {
                let playback = Playback(path: path); playbacks[selected.id] = playback
                playback.looperObservation = playback.looper?.observe(\.status, options: [.new, .initial]) { [weak self, weak playback] looper, _ in
                    guard looper.status == .failed else { return }
                    Task { @MainActor in
                        guard let self, let playback, self.playbacks[selected.id] === playback else { return }
                        self.onFailure?("Could not loop “\(selected.name)”. Choose a playable MP4 encoded with H.264 or HEVC.")
                    }
                }
                playback.observation = playback.player.observe(\.currentItem, options: [.new, .initial]) { [weak self, weak playback] _, _ in
                    Task { @MainActor in
                        guard let self, let playback, self.playbacks[selected.id] === playback else { return }
                        playback.itemObservation = playback.player.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self, weak playback] item, _ in
                            guard item.status == .failed else { return }
                            Task { @MainActor in
                                guard let self, let playback, self.playbacks[selected.id] === playback else { return }
                                self.onFailure?("Could not play “\(selected.name)”. Try another MP4 encoded with H.264 or HEVC.")
                            }
                        }
                    }
                }
                playback.failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self, weak playback] notification in
                    guard let item = notification.object as? AVPlayerItem else { return }
                    Task { @MainActor in
                        guard let self, let playback, self.playbacks[selected.id] === playback, playback.player.items().contains(where: { $0 === item }) else { return }
                        self.onFailure?("Playback failed for “\(selected.name)”. Choose another video or import it again.")
                    }
                }
            }
            let window: NSWindow
            if let existing = windows[id] { window = existing }
            else {
                window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                window.isReleasedWhenClosed = false; window.ignoresMouseEvents = true; window.hasShadow = false
                windows[id] = window
            }
            let root = DesktopScene(scene: selected, player: playbacks[selected.id]?.player, widgets: widgets, corner: corner, animated: !paused, fit: fit)
            if let host = window.contentView as? NSHostingView<DesktopScene> { host.rootView = root }
            else { window.contentView = NSHostingView(rootView: root) }
            window.setFrame(screen.frame, display: true)
            if !paused { window.orderFrontRegardless() }
        }
        if !paused { playbacks.values.forEach { $0.player.play() } }
    }
    func stop() {
        windows.values.forEach { $0.orderOut(nil); $0.contentView = nil; $0.close() }; windows.removeAll()
        playbacks.values.forEach { $0.stop() }; playbacks.removeAll()
        soundtrack?.stop(); soundtrack = nil; audioPath = nil; primaryID = nil; paused = false
    }
    // Avoid closing windows reentrantly during Cocoa termination.
    func shutdown() {
        windows.values.forEach { $0.orderOut(nil); $0.contentView = nil }
        windows.removeAll(); playbacks.values.forEach { $0.stop() }; playbacks.removeAll()
        soundtrack?.stop(); soundtrack = nil; onFailure = nil
    }
    func pause(_ value: Bool) {
        guard value != paused else { return }; paused = value
        for window in windows.values {
            if let host = window.contentView as? NSHostingView<DesktopScene> { var scene = host.rootView; scene.animated = !value; host.rootView = scene }
        }
        if value { playbacks.values.forEach { $0.player.pause() }; soundtrack?.pause(); windows.values.forEach { $0.orderOut(nil) } }
        else { playbacks.values.forEach { $0.player.play() }; windows.values.forEach { $0.orderFrontRegardless() } }
    }
    func configureAudio(_ sound: WallpaperSound) {
        for (id, playback) in playbacks {
            playback.player.isMuted = id != primaryID || !sound.enabled || sound.file != nil
            playback.player.volume = Float(sound.volume)
        }
        if sound.file != audioPath {
            soundtrack?.stop(); soundtrack = nil; audioPath = sound.file
            if let file = sound.file { soundtrack = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: file)); soundtrack?.numberOfLoops = -1 }
        }
        soundtrack?.volume = Float(sound.volume)
        if sound.enabled && primaryVisible && !paused && !windows.isEmpty { if soundtrack?.isPlaying == false { soundtrack?.play() } }
        else { soundtrack?.pause() }
    }
}
struct DesktopScene: View {
    var scene: Landscape; var player: AVPlayer?; var widgets: [DesktopWidget]; var corner: String; var animated: Bool; var fit: WallpaperFit = .fill
    var body: some View {
        ZStack {
            Color.black
            if let player { MovieView(player: player, fit: fit) }
            else if fit == .fit { EfficientLandscape(palette: scene.palette, animated: animated).aspectRatio(16.0 / 9.0, contentMode: .fit) }
            else { EfficientLandscape(palette: scene.palette, animated: animated) }
            if animated { WidgetCanvas(items: widgets, corner: corner) }
        }.ignoresSafeArea()
    }
}
// Draw the backdrop once; Core Animation moves translucent clouds without CPU redraw loops.
@MainActor private enum LandscapeArtwork {
    static var cache: [Int: CGImage] = [:]
    static func image(_ palette: Int) -> CGImage? {
        if let image = cache[palette] { return image }
        let renderer = ImageRenderer(content: LandscapeView(palette: palette, fixedTime: 0).frame(width: 1600, height: 900))
        renderer.scale = 1
        let image = renderer.cgImage
        cache[palette] = image
        return image
    }
}
final class LandscapeSurface: NSView {
    private let backdrop = CALayer()
    private var clouds: [CALayer] = []
    private var animated = false
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = true
        backdrop.contentsGravity = .resizeAspectFill; layer?.addSublayer(backdrop)
        for _ in 0..<3 { let cloud = CALayer(); cloud.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor; clouds.append(cloud); layer?.addSublayer(cloud) }
    }
    required init?(coder: NSCoder) { fatalError() }
    @MainActor func configure(palette: Int, animated: Bool) {
        backdrop.contents = LandscapeArtwork.image(palette)
        if self.animated != animated { self.animated = animated; updateClouds() }
    }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); backdrop.frame = bounds; CATransaction.commit(); updateClouds() }
    private func updateClouds() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, cloud) in clouds.enumerated() {
            cloud.removeAllAnimations()
            cloud.frame = CGRect(x: bounds.width * CGFloat(index) * 0.36, y: bounds.height * (0.65 + CGFloat(index) * 0.08), width: bounds.width * 0.25, height: max(1, bounds.height * 0.005))
            cloud.cornerRadius = cloud.bounds.height / 2
            if animated && bounds.width > 0 {
                let animation = CABasicAnimation(keyPath: "position.x")
                animation.fromValue = -bounds.width * 0.25
                animation.toValue = bounds.width * 1.25
                animation.duration = 480 + Double(index) * 90
                animation.timeOffset = Double(index) * 120
                animation.repeatCount = .infinity
                cloud.add(animation, forKey: "drift")
            }
        }
        CATransaction.commit()
    }
    func stop() { animated = false; clouds.forEach { $0.removeAllAnimations() } }
}
struct EfficientLandscape: NSViewRepresentable {
    let palette: Int; let animated: Bool
    func makeNSView(context: Context) -> LandscapeSurface { let view = LandscapeSurface(); view.configure(palette: palette, animated: animated); return view }
    func updateNSView(_ view: LandscapeSurface, context: Context) { view.configure(palette: palette, animated: animated) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LandscapeSurface, context: Context) -> CGSize? { CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0) }
    static func dismantleNSView(_ view: LandscapeSurface, coordinator: ()) { view.stop() }
}

struct LandscapeView: View {
    var palette: Int; var animated = false; var fixedTime: Double? = nil
    var colors: [Color] { palette == 0 ? [Color(red: 0.12, green: 0.20, blue: 0.32), Color(red: 0.69, green: 0.47, blue: 0.43), Color(red: 0.93, green: 0.75, blue: 0.55)] : palette == 1 ? [Color(red: 0.10, green: 0.34, blue: 0.40), Color(red: 0.43, green: 0.68, blue: 0.66), Color(red: 0.80, green: 0.86, blue: 0.72)] : [Color(red: 0.035, green: 0.06, blue: 0.15), Color(red: 0.17, green: 0.22, blue: 0.36), Color(red: 0.43, green: 0.37, blue: 0.49)] }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !animated)) { context in
            Canvas { c, size in
                let w = size.width, h = size.height, t = fixedTime ?? (animated ? context.date.timeIntervalSinceReferenceDate : 0)
                c.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                let sun = CGRect(x: w * 0.72, y: h * 0.22, width: h * 0.105, height: h * 0.105)
                c.fill(Path(ellipseIn: sun), with: .color(Color(red: 1, green: 0.87, blue: 0.68).opacity(palette == 2 ? 0.65 : 0.9)))
                if palette == 2 { for i in 0..<45 { let x = Double((i * 137 + 23) % 997) / 997 * w; let y = Double((i * 71 + 7) % 313) / 600 * h; c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.55))) } }
                for layer in 0..<4 {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: h))
                    for step in 0...60 {
                        let x = Double(step) / 60 * w
                        let drift = palette == 1 ? sin(t * 0.12 + Double(layer)) * 0.03 : 0.005 * sin(t * 0.06)
                        let ridge = sin(Double(step) * 0.108333333333 + Double(layer) * 1.9 + drift) * 0.09 + sin(Double(step) * 0.216666666667 + Double(layer)) * 0.035
                        p.addLine(to: CGPoint(x: x, y: h * (0.54 + Double(layer) * 0.11 + ridge)))
                    }
                    p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
                    c.fill(p, with: .color(Color(red: 0.06, green: 0.15 + Double(palette == 1 ? 1 : 0) * 0.06, blue: 0.21).opacity(0.35 + Double(layer) * 0.16)))
                }
                for i in 0..<6 { let x = (Double(i) * 0.23 + t * 0.002).truncatingRemainder(dividingBy: 1.4) * w - w * 0.2; let cloud = CGRect(x: x, y: h * (0.18 + Double(i % 3) * 0.10), width: w * 0.30, height: h * 0.008); c.fill(Path(ellipseIn: cloud), with: .color(.white.opacity(0.12))) }
            }
        }.accessibilityLabel("Animated \(palette == 0 ? "dawn mountains" : palette == 1 ? "coastal landscape" : "night mountains")")
    }
}
