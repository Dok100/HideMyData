import SwiftUI
import AppKit

struct ImageDocumentSurface: View {
    @Bindable var redactor: ImageRedactor
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        if let image = redactor.image {
            GeometryReader { geo in
                let pixelSize = redactor.pixelSize
                let scale = min(geo.size.width / pixelSize.width,
                                geo.size.height / pixelSize.height,
                                1.0)
                let displaySize = CGSize(width: pixelSize.width * scale,
                                         height: pixelSize.height * scale)

                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displaySize.width, height: displaySize.height)

                    previewLayer(scale: scale)
                    redactionsLayer(image: image, scale: scale, displaySize: displaySize)
                    focusOverlay(scale: scale)

                    if redactor.editingMode == .add, let s = dragStart, let c = dragCurrent {
                        DragPreview(start: s, end: c)
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .local)
                        .onChanged { value in
                            guard redactor.editingMode == .add else { return }
                            dragStart = value.startLocation
                            dragCurrent = value.location
                        }
                        .onEnded { value in
                            defer { dragStart = nil; dragCurrent = nil }
                            guard redactor.editingMode == .add else { return }
                            let r = displayRect(from: value.startLocation, to: value.location)
                            let inImage = CGRect(
                                x: r.minX / scale,
                                y: r.minY / scale,
                                width: r.width / scale,
                                height: r.height / scale
                            ).intersection(CGRect(origin: .zero, size: pixelSize))
                            if inImage.width > 4 && inImage.height > 4 {
                                redactor.addRedaction(rect: inImage)
                            }
                        }
                )
                .onTapGesture(coordinateSpace: .local) { loc in
                    let p = CGPoint(x: loc.x / scale, y: loc.y / scale)
                    switch redactor.editingMode {
                    case .view:
                        if let findingID = redactor.findingID(at: p) {
                            redactor.selectFinding(findingID)
                        }
                    case .remove:
                        if let idx = redactor.redactionRects.firstIndex(where: { $0.contains(p) }) {
                            redactor.removeRedaction(at: idx)
                        }
                    case .add:
                        break
                    }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active:
                        switch redactor.editingMode {
                        case .view: NSCursor.arrow.set()
                        case .add: NSCursor.crosshair.set()
                        case .remove: NSCursor.disappearingItem.set()
                        }
                    case .ended:
                        NSCursor.arrow.set()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 18))
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.38), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func previewLayer(scale: CGFloat) -> some View {
        ForEach(Array(redactor.previewRectEntries.enumerated()), id: \.offset) { _, entry in
            let scaled = scaledRect(entry.rect, scale: scale)
            let accent = Color(nsColor: redactor.findingColor(for: entry.findingID))
            ZStack {
                Rectangle()
                    .fill(accent.opacity(0.18))
                Rectangle()
                    .strokeBorder(accent.opacity(0.88), lineWidth: 2)
            }
            .frame(width: scaled.width, height: scaled.height)
            .offset(x: scaled.minX, y: scaled.minY)
        }
    }

    @ViewBuilder
    private func redactionsLayer(image: CGImage, scale: CGFloat, displaySize: CGSize) -> some View {
        switch redactor.redactionStyle {
        case .blackRectangle:
            ForEach(Array(redactor.redactionRects.enumerated()), id: \.offset) { _, rect in
                let scaled = scaledRect(rect, scale: scale)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: scaled.width, height: scaled.height)
                    .offset(x: scaled.minX, y: scaled.minY)
            }
        case .blur:
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .interpolation(.high)
                .frame(width: displaySize.width, height: displaySize.height)
                .blur(radius: 14)
                .mask(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(redactor.redactionRects.enumerated()), id: \.offset) { _, rect in
                            let scaled = scaledRect(rect, scale: scale)
                            Rectangle()
                                .frame(width: scaled.width, height: scaled.height)
                                .offset(x: scaled.minX, y: scaled.minY)
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
                }
        }
    }

    @ViewBuilder
    private func focusOverlay(scale: CGFloat) -> some View {
        if let focused = redactor.focusedFindingID {
            ForEach(Array(redactor.findingRects(for: focused).enumerated()), id: \.offset) { _, rect in
                let scaled = scaledRect(rect, scale: scale)
                Rectangle()
                    .strokeBorder(Color(nsColor: redactor.findingColor(for: focused)).opacity(0.95), lineWidth: 2.4)
                    .frame(width: scaled.width, height: scaled.height)
                    .offset(x: scaled.minX, y: scaled.minY)
            }
        }
    }

    private func scaledRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func displayRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

}

private struct DragPreview: View {
    let start: CGPoint
    let end: CGPoint

    var body: some View {
        let r = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        Rectangle()
            .strokeBorder(.red, lineWidth: 1.5)
            .background(Color.red.opacity(0.18))
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
    }
}
