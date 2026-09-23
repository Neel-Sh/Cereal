import AppKit
import CoreGraphics
import Foundation

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create icon canvas") }

let background = CGPath(roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960), cornerWidth: 220, cornerHeight: 220, transform: nil)
context.addPath(background)
context.setFillColor(CGColor(gray: 0.06, alpha: 1))
context.fillPath()

context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(66)
context.setLineCap(.round)
context.addArc(center: CGPoint(x: 512, y: 512), radius: 262, startAngle: .pi * 0.30, endAngle: .pi * 1.70, clockwise: false)
context.strokePath()

context.setFillColor(CGColor(gray: 1, alpha: 1))
let bars: [(CGFloat, CGFloat)] = [(418, 152), (516, 266), (614, 188)]
for (x, height) in bars {
    let rect = CGRect(x: x, y: 512 - height / 2, width: 58, height: height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 29, cornerHeight: 29, transform: nil))
    context.fillPath()
}

guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: destination, options: .atomic)
