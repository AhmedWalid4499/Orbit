import Foundation
import SwiftUI
import AppKit
import Security

/// Checks GitHub Releases for a newer Orbit, downloads it, verifies it was signed by the same
/// developer as the running app, swaps it in place and relaunches.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "AhmedWalid4499/Orbit"

    struct Release: Equatable {
        let version: String
        let notes: String
        let zipURL: URL
        let pageURL: URL
        let publishedAt: Date?
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), downloading(Double), installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?
    @AppStorage("autoCheckUpdates") var autoCheck = true

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var currentBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    var available: Release? {
        if case .available(let r) = state { return r }
        return nil
    }

    // MARK: Checking

    func checkIfDue() async {
        guard autoCheck, !Snapshot.isActive else { return }
        if let lastCheck, Date.now.timeIntervalSince(lastCheck) < 6 * 3600 { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if state == .installing { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: req)
            lastCheck = .now
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { state = .upToDate; return } // no releases yet
            guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UpdateError("GitHub returned an error (\(status)).")
            }
            let tag = (json["tag_name"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let zipString = zip["browser_download_url"] as? String, let zipURL = URL(string: zipString) else {
                state = .upToDate
                return
            }
            let release = Release(version: tag, notes: json["body"] as? String ?? "",
                                  zipURL: zipURL,
                                  pageURL: URL(string: json["html_url"] as? String ?? "") ?? URL(string: "https://github.com/\(Self.repo)/releases")!,
                                  publishedAt: (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
            state = Self.isNewer(tag, than: currentVersion) ? .available(release) : .upToDate
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Menu command: checks and always tells the user the result.
    func checkAndReport() async {
        await check(userInitiated: true)
        let alert = NSAlert()
        switch state {
        case .available(let r):
            alert.messageText = "Orbit \(r.version) is available"
            alert.informativeText = (r.notes.isEmpty ? "" : r.notes + "\n\n") + "You have \(currentVersion). Orbit will restart to finish."
            alert.addButton(withTitle: "Install Now")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { await install() }
        case .upToDate:
            alert.messageText = "You're up to date"
            alert.informativeText = "Orbit \(currentVersion) is the latest version."
            alert.runModal()
        case .failed(let message):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
            alert.runModal()
        default: break
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Installing

    func install() async {
        guard let release = available else { return }
        state = .downloading(0)
        do {
            let work = FileManager.default.temporaryDirectory.appending(path: "orbit-update-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appending(path: "Orbit.zip")
            try await Downloader.download(release.zipURL, to: zip) { [weak self] p in self?.state = .downloading(p) }

            state = .installing
            try await run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw UpdateError("The download didn't contain Orbit.app.") }

            // Only install builds signed by the same developer as this copy.
            let mine = Self.teamID(of: Bundle.main.bundleURL)
            let theirs = Self.teamID(of: newApp)
            guard theirs != nil, mine == nil || mine == theirs else {
                throw UpdateError("The downloaded app isn't signed by you, so it wasn't installed.")
            }

            try relaunch(replacing: Bundle.main.bundleURL, with: newApp)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Hands off to a tiny shell script that waits for Orbit to quit, swaps the bundle and reopens it.
    private func relaunch(replacing current: URL, with new: URL) throws {
        let script = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        DEST="\(current.path)"
        rm -rf "$DEST.previous"
        mv "$DEST" "$DEST.previous" && mv "\(new.path)" "$DEST" && rm -rf "$DEST.previous" || mv "$DEST.previous" "$DEST"
        xattr -cr "$DEST" 2>/dev/null
        open "$DEST"
        """
        let scriptURL = new.deletingLastPathComponent().appending(path: "install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [scriptURL.path]
        try p.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.terminationHandler = { proc in
                proc.terminationStatus == 0 ? cont.resume() : cont.resume(throwing: UpdateError("Couldn't unpack the update."))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    static func teamID(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// URLSession download with progress callbacks.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL!
    private var progress: (@MainActor (Double) -> Void)?

    static func download(_ url: URL, to destination: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        let d = Downloader()
        d.destination = destination
        d.progress = progress
        let session = URLSession(configuration: .ephemeral, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            d.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite expected: Int64) {
        guard expected > 0, let progress else { return }
        let value = Double(written) / Double(expected)
        Task { @MainActor in progress(value) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError("Download failed (\(http.statusCode)).")
            }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
    }
}

// MARK: - UI

/// Pill in the top bar when an update is ready.
struct UpdatePill: View {
    @ObservedObject private var updater = Updater.shared
    @State private var showing = false

    var body: some View {
        if let release = updater.available {
            Button { showing = true } label: {
                Label("Update to \(release.version)", systemImage: "arrow.down.circle.fill")
                    .font(Theme.ui(12, weight: .semibold))
                    .foregroundStyle(Theme.stickerInk)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .bottom) { UpdatePanel().frame(width: 380).padding(20) }
        } else if case .downloading(let p) = updater.state {
            ProgressView(value: p).frame(width: 80).help("Downloading update…")
        } else if updater.state == .installing {
            ProgressView().controlSize(.small).help("Installing update…")
        }
    }
}

/// Version info and the Check for Updates button; used in Settings and the update popover.
struct UpdatePanel: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Orbit \(updater.currentVersion)").font(.headline)
                    Text("Build \(updater.currentBuild)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                switch updater.state {
                case .checking:
                    ProgressView().controlSize(.small)
                case .downloading(let p):
                    ProgressView(value: p).frame(width: 120)
                case .installing:
                    Text("Installing…").font(.caption)
                case .available(let r):
                    Button("Download & install \(r.version)") { Task { await updater.install() } }
                        .buttonStyle(.borderedProminent)
                default:
                    Button("Check for Updates") { Task { await updater.check(userInitiated: true) } }
                }
            }
            switch updater.state {
            case .upToDate:
                Label("You're on the latest version.", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.good)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.critical)
            case .available(let r):
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's new in \(r.version)").font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(r.notes.isEmpty ? "Improvements and fixes." : r.notes)
                            .font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                    Link("View release on GitHub", destination: r.pageURL).font(.caption)
                }
            default:
                EmptyView()
            }
            Toggle("Check for updates automatically", isOn: $updater.autoCheck).font(.caption)
        }
    }
}
