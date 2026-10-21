import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Your profile photo, stored as a small PNG next to Orbit's data.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var photo: NSImage?

    private let url = URL.applicationSupportDirectory.appending(path: "Orbit/profile.png")

    private init() { photo = NSImage(contentsOf: url) }

    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a profile photo"
        panel.prompt = "Use Photo"
        guard panel.runModal() == .OK, let picked = panel.url, let image = NSImage(contentsOf: picked) else { return }
        guard let png = Self.squarePNG(image, side: 512) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
        photo = NSImage(data: png)
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: url)
        photo = nil
    }

    /// Center-crops to a square and scales down so the stored file stays small.
    private static func squarePNG(_ image: NSImage, side: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let s = min(cg.width, cg.height)
        guard let cropped = cg.cropping(to: CGRect(x: (cg.width - s) / 2, y: (cg.height - s) / 2, width: s, height: s)) else { return nil }
        let out = Int(min(side, CGFloat(s)))
        guard let ctx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: out, height: out))
        guard let result = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
    }
}
