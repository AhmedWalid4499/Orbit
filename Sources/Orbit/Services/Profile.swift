import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Your profile photo, stored as a small PNG next to Orbit's data. A small JPEG copy rides along with your synced
/// settings ("profile.photo"), so the photo you pick on the iPhone shows up on the Mac and the other way round.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var photo: PlatformImage?

    private let url = URL.applicationSupportDirectory.appending(path: "Orbit/profile.png")

    static let syncKey = "profile.photo"
    private var observer: NSObjectProtocol?

    private init() {
        guard !Snapshot.isDemo else { return }
        photo = PlatformImage.load(url)
        if photo == nil { adoptSynced() }
        // A photo picked before sync carried it: share it now.
        else if UserDefaults.standard.string(forKey: Self.syncKey) == nil, let photo { UserDefaults.standard.set(Self.encode(photo), forKey: Self.syncKey) }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in ProfileStore.shared.adoptSynced() }
        }
    }

    private var adopted: String?

    /// Uses the photo that came in from another device (or removes ours if it was removed there).
    private func adoptSynced() {
        let synced = UserDefaults.standard.string(forKey: Self.syncKey)
        guard synced != adopted else { return }
        adopted = synced
        guard let synced else { return }
        if synced.isEmpty { try? FileManager.default.removeItem(at: url); photo = nil; return }
        guard let data = Data(base64Encoded: synced), let img = PlatformImage(data: data), let png = img.square(side: 512) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
        photo = img
    }

    private static func encode(_ image: PlatformImage) -> String {
        image.square(side: 320, type: .jpeg, quality: 0.78)?.base64EncodedString() ?? ""
    }

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
        let synced = Self.encode(image)
        adopted = synced
        UserDefaults.standard.set(synced, forKey: Self.syncKey)
    }

    /// Signing out clears this device: the photo goes from here only (it stays in your account and comes back
    /// when you sign in again, so nothing is written to the synced setting).
    func forgetLocal() {
        try? FileManager.default.removeItem(at: url)
        photo = nil
        adopted = nil
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: url)
        photo = nil
        adopted = ""
        UserDefaults.standard.set("", forKey: Self.syncKey)
    }
}
