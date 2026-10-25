import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/// The card itself: what people see when you share it.
struct CardFace: View {
    let card: ProfileCard
    let photo: PlatformImage?
    let qr: PlatformImage?
    /// Links can be tapped (in the app); off when rendering the shareable image.
    var interactive = true
    /// The card's own background photo; falls back to the profile photo.
    var backdrop: PlatformImage? = CardPhoto.image
    /// Start on the QR side of the photo card (for screenshots).
    var startOnBack = false
    @Environment(\.openURL) private var openURL
    @State private var onBack: Bool?
    @State private var turn = 0.0

    private var ink: Color { card.isDark ? Color(hex: 0xF4F4F5) : Theme.stickerInk }
    private var cover: PlatformImage? { card.showPhoto ? (backdrop ?? photo) : nil }

    var body: some View {
        if card.style == "photo", let cover {
            Group {
                if onBack ?? startOnBack { qrBack } else { photoCard(cover) }
            }
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        } else {
            colorCard
        }
    }

    /// Turns the card over: a quarter turn out, swap sides, a quarter turn back in.
    private func flip() {
        withAnimation(.easeIn(duration: 0.16)) { turn = 90 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            onBack = !(onBack ?? startOnBack)
            turn = -90
            withAnimation(.easeOut(duration: 0.2)) { turn = 0 }
        }
    }

    /// The back of the photo card: a big QR code, so it's easy to scan.
    private var qrBack: some View {
        VStack(spacing: 18) {
            HStack {
                HStack(spacing: 2) {
                    Text("orbit").font(.system(size: 15, weight: .black, design: .rounded))
                    Circle().fill(card.color).frame(width: 5, height: 5).offset(y: 4)
                }
                .opacity(0.85)
                Spacer()
                if interactive {
                    Button(action: flip) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 14, weight: .bold))
                            .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain).help("Back to the card")
                }
            }
            Spacer(minLength: 0)
            if let qr {
                qr.swiftUI.interpolation(.none).resizable()
                    .frame(width: 250, height: 250)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white))
            }
            VStack(spacing: 6) {
                Text(card.name.isEmpty ? "Your name" : card.name).font(.system(size: 26, weight: .bold, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(card.qrTarget == "contact" ? "Scan to save my contact" : "Scan to open my link")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(card.isDark ? .white : card.color)
            }
            Spacer(minLength: 0)
            if interactive {
                Text("Tap anywhere to turn back").font(.system(size: 11, weight: .medium)).opacity(0.5)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 420, height: 620)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(hex: 0x141416)))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(card.color.opacity(0.5), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onTapGesture { if interactive { flip() } }
    }

    // MARK: Photo card

    /// Like a profile page: your photo fills the top and fades into a dark panel with where you're based, your name,
    /// what you do, a line about you and your links as pills. The QR code is on the back (the round button turns it over).
    private func photoCard(_ cover: PlatformImage) -> some View {
        let accent = card.isDark ? Theme.orange : card.color
        let role = [card.headline, card.company].filter { !$0.isEmpty }.joined(separator: card.headline.isEmpty || card.company.isEmpty ? "" : " at ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 2) {
                    Text("orbit").font(.system(size: 15, weight: .black, design: .rounded))
                    Circle().fill(accent).frame(width: 5, height: 5).offset(y: 4)
                }
                .shadow(color: .black.opacity(0.4), radius: 6)
                Spacer()
                if interactive, qr != nil {
                    Button(action: flip) {
                        Image(systemName: "qrcode").font(.system(size: 18, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain).help("Show my QR code")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                if !card.location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 13))
                        Text(card.location.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(2.2).lineLimit(1)
                    }
                    .opacity(0.85)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.name.isEmpty ? "Your name" : card.name).font(.system(size: 34, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(accent)
                }
                if !role.isEmpty {
                    Text(role).font(.system(size: 18, weight: .regular)).opacity(0.82).lineLimit(2).minimumScaleFactor(0.85)
                }
                if !card.bio.isEmpty {
                    Text(card.bio).font(.system(size: 14)).opacity(0.9).lineLimit(3).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
                FlowLayout(spacing: 8) {
                    if !card.email.isEmpty { pill("envelope.fill", "Email", accent, url: "mailto:\(card.email)") }
                    if !card.phone.isEmpty { pill("phone.fill", "Call", accent, url: "tel:\(card.phone.filter { $0.isNumber || $0 == "+" })") }
                    ForEach(card.filledLinks.prefix(6)) { link in
                        pill(link.kind.symbol, link.kind == .other ? (link.handle.isEmpty ? "Link" : link.handle) : link.kind.title, accent, url: link.url, brand: link.kind.brand)
                    }
                }
                .padding(.top, 8)
            }
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(width: 420, height: 620, alignment: .topLeading)
        .background {
            ZStack(alignment: .top) {
                Color(hex: 0x111113)
                cover.swiftUI.resizable().scaledToFill().frame(width: 420, height: 430).clipped()
                // A soft shade at the top for the buttons, then the photo melts into the dark panel.
                LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .clear, location: 0.16),
                                       .init(color: .clear, location: 0.36), .init(color: Color(hex: 0x111113).opacity(0.85), location: 0.58),
                                       .init(color: Color(hex: 0x111113), location: 0.7)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// A rounded link button, like the topic chips on a profile page.
    private func pill(_ symbol: String, _ title: String, _ accent: Color, url: String, brand: Brand? = nil) -> some View {
        Button { if interactive, let u = URL(string: url) { openURL(u) } } label: {
            HStack(spacing: 7) {
                if let brand { BrandLogo(brand: brand, size: 18) }
                else { Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(accent) }
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
    }

    // MARK: Colour card

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                if card.showPhoto, let photo {
                    photo.swiftUI.resizable().scaledToFill()
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
            if !card.email.isEmpty || !card.phone.isEmpty {
                HStack(spacing: 8) {
                    if !card.email.isEmpty { contact("envelope.fill", card.email, url: "mailto:\(card.email)") }
                    if !card.phone.isEmpty { contact("phone.fill", card.phone, url: "tel:\(card.phone.filter { $0.isNumber || $0 == "+" })") }
                }
            }
            VStack(spacing: 7) {
                ForEach(card.filledLinks.prefix(6)) { link in
                    linkRow(link)
                }
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
                    qr.swiftUI.interpolation(.none).resizable()
                        .frame(width: 124, height: 124)
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

    /// "LinkedIn" with the handle under it, like a button.
    private func linkRow(_ link: ProfileCard.Link) -> some View {
        Button { if interactive, let u = URL(string: link.url) { openURL(u) } } label: {
            HStack(spacing: 11) {
                if let brand = link.kind.brand {
                    BrandLogo(brand: brand, size: 30)
                } else {
                    Image(systemName: link.kind.symbol).font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ink.opacity(0.12)))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.kind == .other ? (link.handle.isEmpty ? "Link" : link.handle) : link.kind.title)
                        .font(.system(size: 14, weight: .semibold))
                    if link.kind != .other {
                        Text(link.handle).font(.system(size: 11, weight: .medium)).opacity(0.65).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).opacity(0.55)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
    }

    private func contact(_ symbol: String, _ text: String, url: String) -> some View {
        Button { if interactive, let u = URL(string: url) { openURL(u) } } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(ink.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
    }
}

/// Edit your card on the left, see it on the right, share it as an image and a contact file.
struct ProfileCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profile = ProfileStore.shared
    @State private var card = ProfileCard.load()
    @AppStorage(CardPhoto.key) private var cardPhotoData = ""
    #if os(iOS)
    @State private var pickedPhoto: PhotosPickerItem?
    #endif
    private var backdrop: PlatformImage? { cardPhotoData.isEmpty ? nil : CardPhoto.image }
    @State private var files: (png: URL, vcf: URL, html: URL)?
    @State private var copied: String?
    @ObservedObject private var cloud = CloudSync.shared
    @State private var publishStatus: String?
    @State private var publishTask: Task<Void, Never>?

    var body: some View {
        #if os(iOS)
        ScrollView {
            VStack(spacing: 16) {
                // The card fills the width (minus margins) and the buttons line up with its edges.
                GeometryReader { g in
                    CardFace(card: card, photo: profile.photo, qr: qrImage, backdrop: backdrop)
                        .scaleEffect(g.size.width / 420, anchor: .topLeading)
                        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                }
                .aspectRatio(420.0 / 620.0, contentMode: .fit)
                .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
                actions
                editor
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .onChange(of: card) { old, new in
            card.save()
            refreshFiles()
            schedulePublish(turnedOff: old.publishPublic && !new.publishPublic)
        }
        .onChange(of: cardPhotoData) { refreshFiles(); schedulePublish(turnedOff: false) }
        .onChange(of: pickedPhoto) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = PlatformImage(data: data) { CardPhoto.set(img) }
                pickedPhoto = nil
            }
        }
        .onAppear { refreshFiles() }
        #else
        macBody
        #endif
    }

    private var macBody: some View {
        HStack(spacing: 0) {
            editor.frame(width: 420)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 18) {
                CardFace(card: card, photo: profile.photo, qr: qrImage, backdrop: backdrop)
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 10)
                    .scaleEffect(0.9)
                    .frame(width: 380, height: 560)
                actions
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.card.opacity(0.5))
        }
        .sheetFrame(width: 900, height: 720)
        .onChange(of: card) { old, new in
            card.save()
            refreshFiles()
            schedulePublish(turnedOff: old.publishPublic && !new.publishPublic)
        }
        .onChange(of: cardPhotoData) { refreshFiles(); schedulePublish(turnedOff: false) }
        .onAppear(perform: refreshFiles)
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 0) {
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
                        #if os(macOS)
                        Button("Add a profile photo…") { profile.choosePhoto() }.buttonStyle(.orbitLink).font(Theme.ui(12))
                        #endif
                    }
                }

                group("Contact") {
                    field("Email", $card.email, "you@example.com")
                    field("Phone", $card.phone, "+20 …")
                }

                group("Links") {
                    ForEach($card.links) { $link in
                        let kindPicker = Picker("", selection: $link.kind) {
                            ForEach(ProfileCard.Link.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        let field = TextField(link.kind.placeholder, text: Binding(
                            get: { link.value },
                            set: { link.value = $0.trimmingCharacters(in: .newlines) }))
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            #endif
                        let remove = Button { card.links.removeAll { $0.id == link.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                        if Platform.isPhone {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { kindPicker; Spacer(); remove }
                                field
                            }
                            .padding(.vertical, 4)
                        } else {
                            HStack(spacing: 8) { kindPicker.frame(width: 130); field; remove }
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
                                        Platform.copy(url)
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
                    Picker("Style", selection: $card.style) {
                        Text("Photo").tag("photo")
                        Text("Colour").tag("color")
                    }
                    .pickerStyle(.segmented)
                    if card.style == "photo" {
                        HStack(spacing: 10) {
                            #if os(macOS)
                            Button(cardPhotoData.isEmpty ? "Choose a card photo…" : "Change card photo…") { chooseCardPhoto() }
                                .buttonStyle(SoftButtonStyle())
                            #else
                            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                                Text(cardPhotoData.isEmpty ? "Choose a card photo" : "Change card photo")
                            }
                            .buttonStyle(SoftButtonStyle())
                            #endif
                            if !cardPhotoData.isEmpty {
                                Button("Use my profile photo") { CardPhoto.clear() }.buttonStyle(.orbitLink).font(Theme.ui(12))
                            }
                        }
                        Text(backdrop == nil && profile.photo == nil
                             ? "Choose a photo to fill the card. A portrait photo with your face in the top half works best."
                             : "A portrait photo with your face in the top half works best. The colour below is used for your links.")
                            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
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
        .macScrollable()
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
    #if os(macOS)
    private func chooseCardPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo for your card"
        panel.prompt = "Use Photo"
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        CardPhoto.set(img)
    }
    #endif

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

    private var qrImage: PlatformImage? { Self.qr(card.qrPayload) }

    /// Crisp QR code as a bitmap (CoreImage output drawn without smoothing).
    static func qr(_ text: String) -> PlatformImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter?.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return PlatformImage.from(cg)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            #if os(iOS)
            if let files {
                ShareLink(items: [files.png, files.vcf, files.html]) { Label("Share card…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 10) {
                Button { copyImage() } label: { Label("Copy image", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle())
                Button { copyText() } label: { Label("Copy links", systemImage: "link").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle())
            }
            #else
            HStack(spacing: 10) {
                if let files {
                    ShareLink(items: [files.png, files.vcf, files.html]) { Label("Share card…", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle()).frame(width: 170)
                }
                Button { copyImage() } label: { Label("Copy image", systemImage: "doc.on.doc") }.buttonStyle(SoftButtonStyle())
                Button { copyText() } label: { Label("Copy links", systemImage: "link") }.buttonStyle(SoftButtonStyle())
            }
            #endif
            #if os(macOS)
            HStack(spacing: 10) {
                Button { save(files?.png, as: "\(fileStem).png", type: .png) } label: { Label("Save image…", systemImage: "photo") }
                    .buttonStyle(SoftButtonStyle())
                Button { save(files?.vcf, as: "\(fileStem).vcf", type: .vCard) } label: { Label("Save contact…", systemImage: "person.crop.square") }
                    .buttonStyle(SoftButtonStyle())
                Button { save(files?.html, as: "\(fileStem).html", type: .html) } label: { Label("Save web page…", systemImage: "globe") }
                    .buttonStyle(SoftButtonStyle()).help("Your card as a small web page you can open, email or put online")
            }
            #endif
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
        let png = dir.appending(path: "\(fileStem).png"), vcf = dir.appending(path: "\(fileStem).vcf"), html = dir.appending(path: "\(fileStem).html")
        if let data = renderPNG() { try? data.write(to: png) }
        try? card.vCard.data(using: .utf8)?.write(to: vcf)
        // Every version of the card also becomes its own little web page, kept in Orbit's folder too.
        let page = CardHTML.page(card, photo: profile.photo)
        try? page.data(using: .utf8)?.write(to: html)
        let kept = URL.applicationSupportDirectory.appending(path: "Orbit/My card.html")
        try? page.data(using: .utf8)?.write(to: kept)
        files = (png, vcf, html)
    }

    @MainActor private func renderPNG() -> Data? {
        let renderer = ImageRenderer(content: CardFace(card: card, photo: profile.photo, qr: qrImage, interactive: false, backdrop: backdrop).padding(20))
        renderer.scale = 3
        guard let cg = renderer.cgImage else { return nil }
        return ImageData.encode(cg, size: CGSize(width: cg.width, height: cg.height), type: .png, quality: 1, crop: nil)
    }

    private func copyImage() {
        guard let data = renderPNG(), let image = PlatformImage(data: data) else { return }
        Platform.copy(image: image)
        copied = "Card image copied. Paste it into a chat or email."
    }

    private func copyText() {
        Platform.copy(card.shareText)
        copied = "Links copied."
    }

    #if os(macOS)
    private func save(_ source: URL?, as name: String, type: UTType) {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: source, to: dest)
    }
    #endif
}
