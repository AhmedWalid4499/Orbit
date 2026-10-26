import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Brings your Google Keep notes into Orbit's Notes. Google only lets company (Workspace) accounts use the Keep API,
/// so this reads Google's own export: takeout.google.com › Keep, which gives one .json file per note.
/// Pick the Keep folder (or the notes) and Orbit adds them, with checklists and labels; running it again skips duplicates.
enum KeepImport {
    struct Result { var added = 0; var skipped = 0 }

    @MainActor
    static func run(_ urls: [URL], context: ModelContext) -> Result {
        var files: [URL] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let f as URL in e where f.pathExtension.lowercased() == "json" { files.append(f) }
            } else if url.pathExtension.lowercased() == "json" {
                files.append(url)
            }
        }
        let existing = Set(((try? context.fetch(FetchDescriptor<Note>())) ?? []).map { key($0.title, $0.createdAt) })
        var out = Result()
        for url in urls { _ = url.startAccessingSecurityScopedResource() }
        defer { for url in urls { url.stopAccessingSecurityScopedResource() } }
        for f in files {
            guard let data = try? Data(contentsOf: f),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  j["textContent"] != nil || j["listContent"] != nil || j["title"] != nil else { continue }
            if (j["isTrashed"] as? Bool) == true { continue }
            var body = (j["textContent"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let items = j["listContent"] as? [[String: Any]], !items.isEmpty {
                let list = items.map { "\(($0["isChecked"] as? Bool) == true ? "☑︎" : "☐") \($0["text"] as? String ?? "")" }.joined(separator: "\n")
                body = body.isEmpty ? list : body + "\n\n" + list
            }
            let labels = (j["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            if !labels.isEmpty { body += "\n\n" + labels.map { "#" + $0.replacingOccurrences(of: " ", with: "") }.joined(separator: " ") }
            var title = (j["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = String(body.split(separator: "\n").first ?? "Keep note").prefix(60).description }
            let created = (j["createdTimestampUsec"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000_000) } ?? .now
            let edited = (j["userEditedTimestampUsec"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000_000) } ?? created
            guard !existing.contains(key(title, created)) else { out.skipped += 1; continue }
            let n = Note(title: title, body: body, date: created)
            n.updatedAt = edited
            n.pinned = (j["isPinned"] as? Bool) == true
            context.insert(n)
            out.added += 1
        }
        try? context.save()
        return out
    }

    private static func key(_ title: String, _ date: Date) -> String { "\(title.lowercased())|\(Int(date.timeIntervalSince1970))" }
}

/// "Import from Google Keep" with a short how-to, for Notes on Mac and iPhone.
struct KeepImportButton: View {
    @Environment(\.modelContext) private var context
    @State private var picking = false
    @State private var help = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { help = true } label: {
                HStack(spacing: 8) {
                    BrandLogo(brand: .googleKeep, size: 20)
                    Text("Import from Google Keep").font(Theme.ui(13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle())
            if let message { Text(message).font(Theme.ui(11)).foregroundStyle(Theme.good) }
        }
        .alert("Import from Google Keep", isPresented: $help) {
            Button("Open Google Takeout") { Platform.open(URL(string: "https://takeout.google.com/settings/takeout/custom/keep")!) }
            Button("Choose the Keep folder…") { picking = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Google doesn't let apps sign in to Keep for personal accounts, so Joshu reads Google's export instead.\n\n1. Open Google Takeout, keep only Keep selected and export.\n2. Download and unzip it.\n3. Choose its Takeout › Keep folder here.\n\nYou can do it again any time; notes already imported are skipped.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder, .json], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let r = KeepImport.run(urls, context: context)
            message = r.added == 0 && r.skipped == 0 ? "No Keep notes found there. Pick the Keep folder from the export."
                : "Added \(r.added) note\(r.added == 1 ? "" : "s") from Keep\(r.skipped > 0 ? ", \(r.skipped) already here" : "")."
        }
    }
}
