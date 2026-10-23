import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Your profile photo, stored as a small PNG next to Orbit's data.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var photo: PlatformImage?

    private let url = URL.applicationSupportDirectory.appending(path: "Orbit/profile.png")

    private init() { photo = Snapshot.isDemo ? nil : PlatformImage.load(url) }

    #if os(macOS)
    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a profile photo"
        panel.prompt = "Use Photo"
        guard panel.runModal() == .OK, let picked = panel.url, let image = NSImage(contentsOf: picked) else { return }
        setPhoto(image)
    }
    #endif

    /// Saves a photo (center-cropped, at most 512 px).
    func setPhoto(_ image: PlatformImage) {
        guard let png = image.square(side: 512) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
        photo = PlatformImage(data: png)
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: url)
        photo = nil
    }
}
