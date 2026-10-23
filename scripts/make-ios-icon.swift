// Draws the iPhone app icon: swiftc scripts/make-ios-icon.swift -o /tmp/icon && /tmp/icon iOS/OrbitPhone/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// iPhone app icon: the Mac icon's artwork, full-bleed and opaque (iOS adds the rounded corners).
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)
ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
ctx.setStrokeColor(CGColor(srgbRed: 0.90, green: 1.0, blue: 0.12, alpha: 1)); ctx.setLineWidth(80)
ctx.strokeEllipse(in: CGRect(x: 230, y: 230, width: s - 460, height: s - 460))
ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.76, blue: 0.93, alpha: 1))
ctx.fillEllipse(in: CGRect(x: s - 330, y: s - 330, width: 160, height: 160))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
