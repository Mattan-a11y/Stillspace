import Foundation
import AVFoundation
import VideoToolbox

/// Encode with explicit temporal layering instead of AVAssetExportSession's
/// generic HEVC preset. The renderer integration remains experimental.
@available(macOS 26, *) enum LockScreenEncoder {
    private final class Sink: @unchecked Sendable {
        let writer: AVAssetWriter
        let transform: CGAffineTransform
        private let lock = NSLock()
        private var input: AVAssetWriterInput?
        private var failure: Error?
        private var checked = false
        init(url: URL, transform: CGAffineTransform) throws { writer = try AVAssetWriter(outputURL: url, fileType: .mov); self.transform = transform }
        var error: Error? { lock.lock(); defer { lock.unlock() }; return failure }
        func accept(_ sample: CMSampleBuffer?, status: OSStatus) {
            lock.lock(); defer { lock.unlock() }
            guard failure == nil else { return }
            do {
                guard status == noErr, let sample, let format = CMSampleBufferGetFormatDescription(sample) else { throw Self.problem("Video encoder failed (\(status)).") }
                if !checked {
                    var bytes: UnsafePointer<UInt8>?, size = 0
                    let result = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: &bytes, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                    guard result == noErr, let bytes, size >= 4, ((bytes[3] >> 1) & 7) == 1 else { throw Self.problem("The encoder did not produce the required two temporal layers.") }
                    checked = true
                }
                if input == nil {
                    let next = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                    next.transform = transform; next.expectsMediaDataInRealTime = false
                    guard writer.canAdd(next) else { throw Self.problem("Could not write encoded video.") }
                    writer.add(next); input = next
                    guard writer.startWriting() else { throw writer.error ?? Self.problem("Could not start encoded video.") }
                    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
                }
                let until = Date().addingTimeInterval(15)
                while input?.isReadyForMoreMediaData != true {
                    guard writer.status == .writing, Date() < until else { throw writer.error ?? Self.problem("The encoded video writer stopped responding.") }
                    Thread.sleep(forTimeInterval: 0.002)
                }
                guard input?.append(sample) == true else { throw writer.error ?? Self.problem("Could not append encoded frame.") }
            } catch { failure = error }
        }
        func finish() async throws {
            if let error { writer.cancelWriting(); throw error }
            guard let input else { throw Self.problem("No video frames were encoded.") }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? Self.problem("Could not finish encoded video.") }
        }
        static func problem(_ message: String) -> NSError { NSError(domain: "Stillspace.Encoder", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func transcode(_ asset: AVAsset, fps: Float, to output: URL) async throws {
        try await Task.detached(priority: .utility) {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Sink.problem("No video track.") }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let sink = try Sink(url: output, transform: transform)
            var compression: VTCompressionSession?
            let created = VTCompressionSessionCreate(allocator: nil, width: Int32(size.width), height: Int32(size.height), codecType: kCMVideoCodecType_HEVC, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: { refcon, _, status, _, sample in
                guard let refcon else { return }
                Unmanaged<Sink>.fromOpaque(refcon).takeUnretainedValue().accept(sample, status: status)
            }, refcon: Unmanaged.passUnretained(sink).toOpaque(), compressionSessionOut: &compression)
            guard created == noErr, let session = compression else { throw Sink.problem("Could not create HEVC encoder (\(created)).") }
            defer { VTCompressionSessionInvalidate(session) }
            let frameRate = fps > 0 ? Double(fps) : 30
            let settings: [(CFString, CFTypeRef)] = [
                (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel),
                (kVTCompressionPropertyKey_RealTime, kCFBooleanFalse),
                (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
                (kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: frameRate)),
                (kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: Int(frameRate * 2))),
                (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 2)),
                (kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: min(15_000_000, max(3_000_000, Int(size.width * size.height * frameRate * 0.12))))),
                ("NumberOfTemporalLayers" as CFString, NSNumber(value: 2)),
                (kVTCompressionPropertyKey_BaseLayerFrameRate, NSNumber(value: frameRate / 2))
            ]
            for (key, value) in settings {
                let status = VTSessionSetProperty(session, key: key, value: value)
                guard status == noErr else { throw Sink.problem("Lock-screen encoding is unavailable on this Mac (\(key): \(status)).") }
            }
            let reader = try AVAssetReader(asset: asset)
            let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            frames.alwaysCopiesSampleData = false; reader.add(frames)
            guard reader.startReading() else { throw reader.error ?? Sink.problem("Could not read video frames.") }
            do {
                var count = 0
                while let sample = frames.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    if let error = sink.error { throw error }
                    guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
                    let status = VTCompressionSessionEncodeFrame(session, imageBuffer: image, presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample), duration: CMSampleBufferGetDuration(sample), frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
                    guard status == noErr else { throw Sink.problem("Could not encode frame (\(status)).") }
                    count += 1; if count % 60 == 0 { await Task.yield() }
                }
                guard reader.status != .failed else { throw reader.error ?? Sink.problem("Video reader failed.") }
                let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
                guard status == noErr else { throw Sink.problem("Could not finish encoding (\(status)).") }
                try await sink.finish()
            } catch { reader.cancelReading(); sink.writer.cancelWriting(); throw error }
        }.value
    }
}
