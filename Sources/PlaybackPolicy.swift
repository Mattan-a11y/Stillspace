import Foundation
import IOKit.ps

struct PlaybackPolicy {
    static func reason(asleep: Bool, locked: Bool, battery: Bool, lowPower: Bool, hot: Bool, pauseBattery: Bool, pauseLowPower: Bool) -> String? {
        if asleep { return "Display asleep" }
        if locked { return "Mac locked" }
        if hot { return "Mac needs to cool down" }
        if lowPower && pauseLowPower { return "Low Power Mode" }
        if battery && pauseBattery { return "On battery power" }
        return nil
    }
}

@MainActor final class PowerMonitor {
    private var source: CFRunLoopSource?
    var changed: (() -> Void)?
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return type as String == kIOPSBatteryPowerValue
    }
    init() {
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak monitor] in monitor?.changed?() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }
    deinit { if let source { CFRunLoopSourceInvalidate(source) } }
}

// Only app-managed regular files can be removed. Never follow a link into user media.
enum ManagedMedia {
    static func deletable(_ url: URL, in folder: URL) -> Bool {
        let path = url.standardizedFileURL
        let root = folder.standardizedFileURL
        guard path.deletingLastPathComponent().path == root.path,
              path.resolvingSymlinksInPath().path == path.path,
              root.resolvingSymlinksInPath().path == root.path,
              let info = try? path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return info.isRegularFile == true && info.isSymbolicLink != true
    }
}
