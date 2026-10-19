// Original procedural artwork for Stillspace. Demo outputs are dedicated to CC0.
import Foundation
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@main struct RenderDemo {
    static let w = 1920, h = 1080, fps: Int32 = 30, count = 240
    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r,g,b,a])!
    }
    static func draw(_ c: CGContext, _ phase: Double) {
        let W = Double(w), H = Double(h)
        let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0.015,0.035,0.10),color(0.055,0.19,0.25),color(0.07,0.29,0.31)] as CFArray, locations: [0,0.65,1])!
        c.drawLinearGradient(background,start:CGPoint(x:0,y:H),end:CGPoint(x:0,y:0),options:[])
        for i in 0..<105 {
            let x = Double((i*487+71)%1901), y = H * (0.42 + Double((i*157+31)%997)/1750)
            let alpha = 0.26 + 0.23 * (1 + sin(phase + Double(i)*1.7))/2
            c.setFillColor(color(0.85,0.94,1,alpha)); let d = i%5==0 ? 2.7 : 1.7
            c.fillEllipse(in:CGRect(x:x,y:y,width:d,height:d))
        }
        for ribbon in 0..<4 {
            let path=CGMutablePath()
            let base = 640.0 + Double(ribbon)*63
            let amplitude = 77.0 + Double(ribbon)*12
            for i in 0...160 {
                let x=Double(i)/160*W
                let y=base + sin(x/W*5.5 + phase + Double(ribbon)*0.6)*amplitude + cos(x/W*8-phase)*24
                if i==0 { path.move(to:CGPoint(x:x,y:y)) } else { path.addLine(to:CGPoint(x:x,y:y)) }
            }
            for i in (0...160).reversed() {
                let x=Double(i)/160*W
                let y=base + sin(x/W*5.5 + phase + Double(ribbon)*0.6)*amplitude + cos(x/W*8-phase)*24 + 80 + sin(x/W*7+phase)*28
                path.addLine(to:CGPoint(x:x,y:y))
            }
            path.closeSubpath(); c.saveGState(); c.addPath(path); c.clip()
            let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color(0.21,0.93,0.70,0),color(0.26,0.89,0.75,0.11),color(0.53,0.47,0.96,0.02)] as CFArray,locations:[0,0.62,1])!
            c.drawLinearGradient(gradient,start:CGPoint(x:0,y:base-120),end:CGPoint(x:0,y:base+170),options:[]); c.restoreGState()
        }
        c.setFillColor(color(0.88,0.94,0.88,0.9)); c.fillEllipse(in:CGRect(x:1450,y:790,width:52,height:52))
        for layer in 0..<4 {
            let path=CGMutablePath(); path.move(to:.zero)
            for i in 0...180 {
                let x=Double(i)/180*W
                let y=390-Double(layer)*83 + sin(x/W*6 + Double(layer)*1.8)*76 + cos(x/W*11+Double(layer))*30
                path.addLine(to:CGPoint(x:x,y:y))
            }
            path.addLine(to:CGPoint(x:W,y:0)); path.closeSubpath()
            c.setFillColor(color(0.025+Double(3-layer)*0.013,0.09+Double(3-layer)*0.025,0.14+Double(3-layer)*0.028)); c.addPath(path); c.fillPath()
        }
    }
    static func reduced(_ image: CGImage, width: Int, height: Int) -> CGImage {
        let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high; context.draw(image,in:CGRect(x:0,y:0,width:width,height:height)); return context.makeImage()!
    }
    static func main() async throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent("Northern-Drift.mp4")
        guard !FileManager.default.fileExists(atPath:url.path) else { throw NSError(domain:"DemoAlreadyExists",code:1) }
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:w,AVVideoHeightKey:h,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:6_000_000,AVVideoExpectedSourceFrameRateKey:fps,AVVideoMaxKeyFrameIntervalKey:60]])
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:w,kCVPixelBufferHeightKey as String:h,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        writer.add(input); guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime:.zero)
        let gif=CGImageDestinationCreateWithURL(folder.appendingPathComponent("Northern-Drift.gif") as CFURL,UTType.gif.identifier as CFString,24,nil)!
        CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frame in 0..<count {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for:.milliseconds(2)) }
            try autoreleasepool {
                var buffer:CVPixelBuffer?; guard CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)==kCVReturnSuccess,let buffer else { throw NSError(domain:"DemoBuffer",code:1) }
                CVPixelBufferLockBaseAddress(buffer,[]); defer {CVPixelBufferUnlockBaseAddress(buffer,[])}
                let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:w,height:h,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue)!
                draw(context,Double(frame)/Double(count)*2*Double.pi)
                if frame%10==0, let image=context.makeImage() {
                    CGImageDestinationAddImage(gif,reduced(image,width:640,height:360),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/3]] as CFDictionary)
                    if frame==0 {
                        let png=CGImageDestinationCreateWithURL(folder.appendingPathComponent("Northern-Drift.png") as CFURL,UTType.png.identifier as CFString,1,nil)!
                        CGImageDestinationAddImage(png,image,nil); guard CGImageDestinationFinalize(png) else {throw NSError(domain:"DemoPNG",code:1)}
                    }
                }
                guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:fps)) else { throw writer.error! }
            }
        }
        input.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else {throw writer.error!}
        guard CGImageDestinationFinalize(gif) else {throw NSError(domain:"DemoGIF",code:1)}
        let asset=AVURLAsset(url:url)
        let duration=try await asset.load(.duration).seconds
        let tracks=try await asset.loadTracks(withMediaType:.video)
        let size=try await tracks[0].load(.naturalSize)
        guard duration==8, size.width==1920, size.height==1080 else {throw NSError(domain:"DemoValidation",code:1)}
        print("Verified Northern Drift: 1920 × 1080, H.264, 30 fps, 8-second silent loop.")
    }
}
