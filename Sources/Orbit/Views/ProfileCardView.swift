import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The card itself: what people see when you share it.
struct CardFace: View {
    let card: ProfileCard
    let photo: NSImage?
    let qr: NSImage?

    private var ink: Color { card.isDark ? Color(hex: 0xF4F4F5) : Theme.stickerInk }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                if card.showPhoto, let photo {
                    Image(nsImage: photo).resizable().scaledToFill()
                        .frame(width: 86, height: 86).clipShape(Circle())
                        .overlay(Circle().strokeBorder(ink.opacity(0.15), lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name.isEmpty ? "Your name" : card.name).font(.system(size: 30, weight: .bold, design: .serif))
                        .lineLimit(2).minimumScaleFactor(0.6)
                    let sub = [card.headline, card.company].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(.system(size: 15, weight: .medium)).opacity(0.8).lineLimit(2) }
                    if !card.location.isEmpty {
                        Label(card.location, systemImage: "mappin").font(.system(size: 12, weight: .medium)).opacity(0.65)
                    }
                }
            }
            if !card.bio.isEmpty {
                Text(card.bio).font(.system(size: 14, design: .serif)).opacity(0.85).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 9) {
                if !card.email.isEmpty { row("envelope.fill", card.email) }
                if !card.phone.isEmpty { row("phone.fill", card.phone) }
                ForEach(card.filledLinks.prefix(7)) { row($0.kind.symbol, $0.display) }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.qrTarget == "contact" ? "Scan to save my contact" : "Scan to open").font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 2) {
                        Text("orbit").font(.system(size: 13, weight: .black, design: .rounded))
                        Circle().fill(card.isDark ? Theme.lime : ink).frame(width: 4, height: 4).offset(y: 3)
                    }
                    .opacity(0.5)
                }
                Spacer()
                if let qr {
                    Image(nsImage: qr).interpolation(.none).resizable()
                        .frame(width: 150, height: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                }
            }
        }
        .foregroundStyle(ink)
        .padding(30)
        .frame(width: 420, height: 620, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(card.color))
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(ink.opacity(0.1)))
            Text(text).font(.system(size: 14, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Edit your card on the left, see it on the right, share it as an image and a contact file.
struct ProfileCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile = ProfileStore.shared
    @State private var card = ProfileCard.load()
    @State private var files: (png: URL, vcf: URL)?
    @State private var copied: String?
    @ObservedObject private var cloud = CloudSync.shared
    @State private var publishStatus: String?
    @State private var publishTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            editor.frame(width: 420)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 18) {
                CardFace(card: card, photo: profile.photo, qr: qrImage)
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
                    .scaleEffect(0.9)
                    .frame(width: 380, height: 560)
                actions
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.card.opacity(0.5))
        }
        .frame(width: 900, height: 720)
        .onChange(of: card) { old, new in
            card.save()
            refreshFiles()
            schedulePublish(turnedOff: old.publishPublic && !new.publishPublic)
        }
        .onAppear(perform: refreshFiles)
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("My card").font(Theme.display(28))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                }
                Text("Add your links once, then share your card as an image or a contact anyone can save.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)

                group("About you") {
                    field("Name", $card.name, "Your name")
                    field("Headline", $card.headline, "Product designer, Founder…")
                    field("Company", $card.company, "Where you work (optional)")
                    field("Location", $card.location, "Cairo, Egypt")
                    TextField("A line about you (optional)", text: $card.bio, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                    Toggle("Show my profile photo", isOn: $card.showPhoto)
                    if profile.photo == nil {
                        Button("Add a profile photo…") { profile.choosePhoto() }.buttonStyle(.link).font(Theme.ui(12))
                    }
                }

                group("Contact") {
                    field("Email", $card.email, "you@example.com")
                    field("Phone", $card.phone, "+20 …")
                }

                group("Links") {
                    ForEach($card.links) { $link in
                        HStack(spacing: 8) {
                            Picker("", selection: $link.kind) {
                                ForEach(ProfileCard.Link.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                            }
                            .labelsHidden().frame(width: 130)
                            TextField(link.kind.placeholder, text: $link.value).textFieldStyle(.roundedBorder)
                            Button { card.links.removeAll { $0.id == link.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    Menu {
                        ForEach(ProfileCard.Link.Kind.allCases) { k in
                            Button { card.links.append(.init(kind: k, value: "")) } label: { Label(k.title, systemImage: k.symbol) }
                        }
                    } label: { Label("Add link", systemImage: "plus") }
                    .menuStyle(.button).fixedSize()
                }

                group("Public link") {
                    if !cloud.isSignedIn {
                        Text("Sign in under Settings › Account to get a web link for your card.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    } else {
                        Toggle("Publish my card on the web", isOn: $card.publishPublic)
                        if card.publishPublic {
                            HStack(spacing: 4) {
                                Text("…/card/?u=").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                                TextField("your-name", text: Binding(get: { card.publicSlug },
                                                                     set: { card.publicSlug = ProfileCard.slugify($0) }))
                                    .textFieldStyle(.roundedBorder)
                            }
                            Toggle("Show my email and phone on the page", isOn: $card.publicShowContact)
                            if let url = card.publicURL {
                                HStack {
                                    Link(url.replacingOccurrences(of: "https://", with: ""), destination: URL(string: url)!).font(Theme.ui(11)).lineLimit(1)
                                    Spacer()
                                    Button("Copy link") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url, forType: .string)
                                        copied = "Link copied."
                                    }
                                }
                            } else {
                                Text("Use 3–40 lowercase letters, numbers or dashes.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                            }
                            if let publishStatus { Text(publishStatus).font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary) }
                        }
                    }
                }

                group("Look") {
                    HStack(spacing: 8) {
                        ForEach(0..<ProfileCard.colors.count, id: \.self) { i in
                            Circle().fill(ProfileCard.colors[i]).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: card.colorIndex == i ? 2 : 0))
                                .onTapGesture { card.colorIndex = i }
                        }
                    }
                    Picker("QR code opens", selection: $card.qrTarget) {
                        Text("My contact card").tag("contact")
                        if card.publicURL != nil { Text("My web page").tag("web") }
                        ForEach(card.filledLinks) { Text($0.kind.title).tag($0.id.uuidString) }
                    }
                }
            }
            .font(Theme.ui(13))
            .padding(24)
        }
        .scrollIndicators(.never)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            content()
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ prompt: String) -> some View {
        TextField(label, text: value, prompt: Text(prompt)).textFieldStyle(.roundedBorder)
    }

    /// Publishes a moment after you stop typing; removes the page when you switch publishing off.
    private func schedulePublish(turnedOff: Bool) {
        publishTask?.cancel()
        guard cloud.isSignedIn else { return }
        if turnedOff {
            publishTask = Task { try? await cloud.unpublishCard(); publishStatus = "Your card is no longer on the web." }
            return
        }
        guard card.publishPublic else { return }
        if card.publicSlug.isEmpty { card.publicSlug = ProfileCard.slugify(card.name) }
        guard ProfileCard.isValidSlug(card.publicSlug) else { return }
        let snapshot = card, photo = profile.photo
        publishTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            publishStatus = "Publishing…"
            do {
                try await cloud.publishCard(slug: snapshot.publicSlug, data: snapshot.publicData(photo: photo))
                publishStatus = "Live: anyone with the link sees your latest card."
            } catch {
                publishStatus = error.localizedDescription
            }
        }
    }

    // MARK: Sharing

    private var qrImage: NSImage? { Self.qr(card.qrPayload) }

    /// Crisp QR code as a bitmap (CoreImage output drawn without smoothing).
    static func qr(_ text: String) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter?.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let files {
                    ShareLink(items: [files.png, files.vcf]) { Label("Share card…", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle()).frame(width: 170)
                }
                Button { copyImage() } label: { Label("Copy image", systemImage: "doc.on.doc") }.buttonStyle(SoftButtonStyle())
                Button { copyText() } label: { Label("Copy links", systemImage: "link") }.buttonStyle(SoftButtonStyle())
            }
            HStack(spacing: 10) {
                Button { save(files?.png, as: "\(fileStem).png", type: .png) } label: { Label("Save image…", systemImage: "photo") }
                    .buttonStyle(SoftButtonStyle())
                Button { save(files?.vcf, as: "\(fileStem).vcf", type: .vCard) } label: { Label("Save contact…", systemImage: "person.crop.square") }
                    .buttonStyle(SoftButtonStyle())
            }
            if let copied { Text(copied).font(Theme.ui(11, weight: .medium)).foregroundStyle(Theme.good) }
        }
    }

    private var fileStem: String {
        (card.name.isEmpty ? "My card" : card.name).replacingOccurrences(of: "/", with: "-")
    }

    /// Renders the card at 3x and writes the PNG and .vcf that the share menu sends.
    @MainActor private func refreshFiles() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "orbit-card", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = dir.appending(path: "\(fileStem).png"), vcf = dir.appending(path: "\(fileStem).vcf")
        if let data = renderPNG() { try? data.write(to: png) }
        try? card.vCard.data(using: .utf8)?.write(to: vcf)
        files = (png, vcf)
    }

    @MainActor private func renderPNG() -> Data? {
        let renderer = ImageRenderer(content: CardFace(card: card, photo: profile.photo, qr: qrImage).padding(20))
        renderer.scale = 3
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private func copyImage() {
        guard let data = renderPNG(), let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = "Card image copied. Paste it into a chat or email."
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.shareText, forType: .string)
        copied = "Links copied."
    }

    private func save(_ source: URL?, as name: String, type: UTType) {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: source, to: dest)
    }
}
