#!/usr/bin/env swift
// Generates a 1024x1024 placeholder app icon PNG at the given path.
// Usage: swift scripts/make-icon.swift <out.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("failed to create context\n".utf8)); exit(1)
}

// Rounded-rect background with a diagonal gradient (dark blue -> magenta).
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let radius = CGFloat(size) * 0.22
let path = CGPath(roundedRect: rect.insetBy(dx: 40, dy: 40),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path); ctx.clip()
let colors = [CGColor(red: 0.10, green: 0.12, blue: 0.28, alpha: 1),
              CGColor(red: 0.55, green: 0.12, blue: 0.75, alpha: 1)] as CFArray
if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0), options: [])
}

// A bold "M" glyph drawn as a filled path (no font dependency).
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
let m = CGMutablePath()
let w = CGFloat(size)
m.move(to: CGPoint(x: w*0.24, y: w*0.30))
m.addLine(to: CGPoint(x: w*0.24, y: w*0.70))
m.addLine(to: CGPoint(x: w*0.33, y: w*0.70))
m.addLine(to: CGPoint(x: w*0.33, y: w*0.46))
m.addLine(to: CGPoint(x: w*0.46, y: w*0.64))
m.addLine(to: CGPoint(x: w*0.54, y: w*0.64))
m.addLine(to: CGPoint(x: w*0.67, y: w*0.46))
m.addLine(to: CGPoint(x: w*0.67, y: w*0.70))
m.addLine(to: CGPoint(x: w*0.76, y: w*0.70))
m.addLine(to: CGPoint(x: w*0.76, y: w*0.30))
m.addLine(to: CGPoint(x: w*0.66, y: w*0.30))
m.addLine(to: CGPoint(x: w*0.50, y: w*0.52))
m.addLine(to: CGPoint(x: w*0.34, y: w*0.30))
m.closeSubpath()
ctx.addPath(m); ctx.fillPath()

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("failed to render\n".utf8)); exit(1)
}
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("failed to open destination\n".utf8)); exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(out)")
} else {
    FileHandle.standardError.write(Data("failed to write png\n".utf8)); exit(1)
}
