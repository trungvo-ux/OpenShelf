import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for (name, side) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(side)
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x*scale, y: y*scale, width: w*scale, height: h*scale) }
    let tile = NSBezierPath(roundedRect: rect(0.06,0.06,0.88,0.88), xRadius: scale*0.20, yRadius: scale*0.20)
    NSGradient(starting: NSColor(srgbRed: 0.22, green: 0.59, blue: 1, alpha: 1), ending: NSColor(srgbRed: 0.08, green: 0.31, blue: 0.87, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect(0.28,0.22,0.45,0.59), xRadius: scale*0.06, yRadius: scale*0.06).fill()
    NSColor(srgbRed: 0.11, green: 0.38, blue: 0.9, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect(0.39,0.73,0.23,0.13), xRadius: scale*0.035, yRadius: scale*0.035).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect(0.43,0.77,0.15,0.045), xRadius: scale*0.015, yRadius: scale*0.015).fill()
    NSColor(srgbRed: 0.30, green: 0.48, blue: 0.77, alpha: 1).setFill()
    for y in [0.60,0.49,0.38] { NSBezierPath(roundedRect: rect(0.36,y,0.28,0.035), xRadius: scale*0.017, yRadius: scale*0.017).fill() }
    NSColor(srgbRed: 1, green: 0.65, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(ovalIn: rect(0.57,0.13,0.29,0.29)).fill()
    NSColor.white.setStroke()
    let hands = NSBezierPath(); hands.lineWidth = scale*0.025; hands.lineCapStyle = .round
    hands.move(to: NSPoint(x: scale*0.715,y: scale*0.35)); hands.line(to: NSPoint(x: scale*0.715,y: scale*0.275)); hands.line(to: NSPoint(x: scale*0.765,y: scale*0.245)); hands.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name+".png"))
}

let chunks: [(String,String)] = [("icp4","icon_16x16"),("icp5","icon_32x32"),("icp6","icon_32x32@2x"),("ic07","icon_128x128"),("ic08","icon_256x256"),("ic09","icon_512x512"),("ic10","icon_512x512@2x")]
func field(_ value: UInt32) -> Data { var big = value.bigEndian; return withUnsafeBytes(of: &big) { Data($0) } }
var payload = Data()
for (type,name) in chunks {
    let png = try Data(contentsOf: root.appendingPathComponent(name+".png"))
    payload.append(Data(type.utf8)); payload.append(field(UInt32(png.count+8))); payload.append(png)
}
var icon = Data("icns".utf8); icon.append(field(UInt32(payload.count+8))); icon.append(payload)
let destination = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : root.deletingPathExtension().appendingPathExtension("icns")
try icon.write(to: destination)
