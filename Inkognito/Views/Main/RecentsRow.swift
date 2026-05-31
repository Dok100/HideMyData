import CoreGraphics
import ImageIO
import SwiftUI

struct RecentsRow: View {
    @Bindable var store: RecentsStore
    let onOpen: (RecentItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tiles
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer(minLength: 0)

            Button("Alles löschen") {
                withAnimation(.smooth(duration: 0.22)) {
                    store.clearStoredItems()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private var tiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(store.items) { item in
                    RecentDocumentTile(
                        item: item,
                        thumbnailURL: store.thumbnailURL(for: item),
                        open: { onOpen(item) },
                        delete: {
                            withAnimation(.smooth(duration: 0.22)) {
                                store.remove(item)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}

private struct RecentDocumentTile: View {
    let item: RecentItem
    let thumbnailURL: URL
    let open: () -> Void
    let delete: () -> Void

    @State private var thumbnail: CGImage?
    @State private var hovering = false

    private let width: CGFloat = 132
    private let height: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tileButton

            Text(item.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: width, alignment: .leading)
                .padding(.horizontal, 2)
        }
        .onAppear(perform: loadThumbnailIfNeeded)
        .onHover { isHovering in
            withAnimation(.smooth(duration: 0.16)) {
                hovering = isHovering
            }
        }
    }

    private var tileButton: some View {
        Button(action: open) {
            ZStack(alignment: .topTrailing) {
                previewSurface
                    .frame(width: width, height: height)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }

                if hovering {
                    deleteButton
                        .padding(7)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .shadow(
                color: Color.black.opacity(hovering ? 0.32 : 0.18),
                radius: hovering ? 14 : 6,
                y: hovering ? 6 : 3
            )
            .scaleEffect(hovering ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    private var previewSurface: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.thinMaterial)
                    Image(systemName: item.kind == .pdf ? "doc.text" : "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(action: delete) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.black.opacity(0.62)))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
    }

    private func loadThumbnailIfNeeded() {
        guard thumbnail == nil else { return }
        guard let source = CGImageSourceCreateWithURL(thumbnailURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        thumbnail = image
    }
}
