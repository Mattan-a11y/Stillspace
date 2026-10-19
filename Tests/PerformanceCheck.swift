import Foundation
import AppKit
import AVFoundation
import Darwin
@main struct PerformanceCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let mode = CommandLine.arguments[1]
        if mode == "generate" {
            let folder = URL(fileURLWithPath: CommandLine.arguments[2])
            for (name, w, h) in [("1080p", 1920, 1080), ("4K", 3840, 2160)] {
                try await Task.detached(priority: .utility) { try await generate(folder.appendingPathComponent(name + ".mp4"), w, h) }.value
            }
            print("Created temporary synthetic HEVC videos."); return
        }
        let engine = DesktopController()
        if mode == "builtin" { engine.show(Landscape.builtins[2], widgets: [], corner: "Top right") }
        else if mode != "idle" {
            engine.show(Landscape(id: "benchmark", name: mode, subtitle: "", palette: 2, file: CommandLine.arguments[2]), widgets: [], corner: "Top right")
            if mode == "paused" { engine.pause(true) }
        }
        try await Task.sleep(for: .seconds(5))
        let start = cpu(); let date = Date()
        try await Task.sleep(for: .seconds(12))
        let percent = (cpu() - start) / Date().timeIntervalSince(date) * 100
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-p", String(getpid()), "-o", "rss="]
        let pipe = Pipe(); process.standardOutput = pipe; try process.run(); process.waitUntilExit()
        let rss = Double(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let result: [String: Any] = ["mode": mode, "cpu_percent_one_core": percent, "resident_MB": rss / 1024, "display_count": NSScreen.screens.count, "players": engine.playerCount, "windows": engine.windowCount, "sample_seconds": 12]
        engine.stop()
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
    static func cpu() -> Double { var info = rusage(); getrusage(RUSAGE_SELF, &info); return Double(info.ru_utime.tv_sec + info.ru_stime.tv_sec) + Double(info.ru_utime.tv_usec + info.ru_stime.tv_usec) / 1_000_000 }
    static func generate(_ url: URL, _ w: Int, _ h: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input); guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime: .zero)
        for frame in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?; guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess, let buffer else { throw NSError(domain: "Benchmark", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!, stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<h {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt32.self)
                let color = UInt32(0xff000000) | UInt32((y + frame * 3) % 256) << 16 | UInt32((y / 5 + frame) % 256) << 8 | 96
                row.update(repeating: color, count: w)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
        }
        input.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else { throw writer.error! }
    }
}
