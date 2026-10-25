import SwiftUI

/// Your books on a wooden bookshelf, covers facing out: each row stands on a plank against a warm wooden back,
/// with the title and author on a little label under each book.
struct BookshelfView<Menu: View>: View {
    let books: [Book]
    let onTap: (Book) -> Void
    @ViewBuilder var menu: (Book) -> Menu

    @State private var width: CGFloat = 0

    private var coverWidth: CGFloat { Platform.isPhone ? 96 : 124 }
    private var spacing: CGFloat { Platform.isPhone ? 14 : 22 }
    private var inset: CGFloat { Platform.isPhone ? 14 : 24 }
    private var perRow: Int { max(2, Int((width - inset * 2 + spacing) / (coverWidth + spacing))) }

    var body: some View {
        LazyVStack(spacing: Platform.isPhone ? 20 : 28) {
            if width > 0 {
                ForEach(Array(stride(from: 0, to: books.count, by: perRow)), id: \.self) { start in
                    shelf(Array(books[start..<min(start + perRow, books.count)]))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func shelf(_ row: [Book]) -> some View {
        VStack(spacing: 0) {
            // The back of the shelf, with the books standing in it.
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(row) { b in
                    ShelfBook(book: b, width: coverWidth)
                        .onTapGesture { onTap(b) }
                        .contextMenu { menu(b) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
            .padding(.top, Platform.isPhone ? 18 : 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShelfBack())
            Plank()
            // Little labels under each book.
            HStack(alignment: .top, spacing: spacing) {
                ForEach(row) { b in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).font(Theme.ui(Platform.isPhone ? 11 : 12, weight: .semibold)).lineLimit(2)
                        if !b.author.isEmpty {
                            Text(b.author).font(Theme.ui(Platform.isPhone ? 10 : 11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                        }
                        if b.rating > 0 { Stars(rating: b.rating, size: 9) }
                    }
                    .frame(width: coverWidth, alignment: .leading)
                    .onTapGesture { onTap(b) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
            .padding(.top, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// One book standing on the shelf, cover out, casting a soft shadow on the wood.
private struct ShelfBook: View {
    let book: Book
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        BookCover(book: book)
            .frame(width: width, height: width * 1.5)
            .overlay(alignment: .topTrailing) {
                if book.status != .toRead {
                    Image(systemName: book.status.symbol)
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.stickerInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(book.status == .read ? Theme.lime : book.status == .reading ? Theme.cyan : Theme.peach))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                if book.status == .reading, book.progress > 0 {
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.9)).frame(width: max(4, g.size.width * book.progress), height: 3)
                    }
                    .frame(height: 3).padding(.horizontal, 6).padding(.bottom, 6)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 6, x: 3, y: 4)
            .scaleEffect(hovering ? 1.04 : 1, anchor: .bottom)
            .offset(y: hovering ? -4 : 0)
            .animation(.spring(response: 0.25), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// Warm wood with a soft grain and a shadow at the top, like the inside of a real shelf.
private struct ShelfBack: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x5A3A22), Color(hex: 0x6E4A2C), Color(hex: 0x5C3B23)], startPoint: .leading, endPoint: .trailing)
            // Grain: thin, slightly wavy darker streaks.
            Canvas { ctx, size in
                var seed: UInt64 = 7
                func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max) }
                for _ in 0..<Int(size.width / 9) {
                    let x = rand() * size.width
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addCurve(to: CGPoint(x: x + (rand() - 0.5) * 14, y: size.height),
                               control1: CGPoint(x: x + (rand() - 0.5) * 20, y: size.height * 0.35),
                               control2: CGPoint(x: x + (rand() - 0.5) * 20, y: size.height * 0.7))
                    ctx.stroke(p, with: .color(.black.opacity(0.05 + rand() * 0.08)), lineWidth: 0.6 + rand() * 1.6)
                }
            }
            // Shadow under the shelf above, and the corners in shade.
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
            LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// The plank the books stand on: a lit top edge and a thick front.
private struct Plank: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(hex: 0xC9935C), Color(hex: 0xB07A45)], startPoint: .top, endPoint: .bottom).frame(height: 6)
            LinearGradient(colors: [Color(hex: 0x9A6435), Color(hex: 0x7B4D27), Color(hex: 0x5E3A1C)], startPoint: .top, endPoint: .bottom)
                .frame(height: Platform.isPhone ? 12 : 16)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 1) }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 4)
    }
}
