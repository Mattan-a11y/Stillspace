// Original Stillspace icon paths, authored for this project on 2026-10-09.
import AppKit
import Foundation
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
    let image = NSImage(size: NSSize(width: pixels, height: pixels)); image.lockFocus()
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
    let enclosure = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedRed: 0.095, green: 0.12, blue: 0.14, alpha: 1), ending: NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.045, alpha: 1))!.draw(in: enclosure, angle: 85)
    NSColor.white.withAlphaComponent(0.12).setStroke(); enclosure.lineWidth = 5; enclosure.stroke()
    NSColor(calibratedWhite: 0.93, alpha: 1).setStroke()
    func line(_ points: [(CGFloat, CGFloat)]) {
        let path = NSBezierPath(); path.lineWidth = 32; path.lineJoinStyle = .round; path.lineCapStyle = .round
        path.move(to: NSPoint(x: points[0].0, y: points[0].1))
        for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }; path.stroke()
    }
    line([(192,342),(368,602),(478,458)])
    line([(304,342),(612,694),(832,342),(192,342)])
    line([(321,531),(369,501),(414,544)])
    line([(547,620),(607,568),(666,604)])
    image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to: folder.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to: folder.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
