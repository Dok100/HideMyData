import AppKit
import SwiftUI

struct ImageDocumentSurface: View {
    @Bindable var redactor: ImageRedactor
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        if let image = redactor.image {
            GeometryReader { geometry in
                let layout = ImageSurfaceLayout(containerSize: geometry.size, pixelSize: redactor.pixelSize)

                ZStack(alignment: .topLeading) {
                    baseImage(image: image, displaySize: layout.displaySize)
                    previewLayer(scale: layout.scale)
                    redactionsLayer(image: image, scale: layout.scale, displaySize: layout.displaySize)
                    focusOverlay(scale: layout.scale)

                    if redactor.editingMode == .add, let dragStart, let dragCurrent {
                        DragPreview(start: dragStart, end: dragCurrent)
                    }

                    if let notice = redactor.detectionNotice {
                        detectionNoticeCard(title: notice.title, message: notice.message)
                            .padding(18)
                    }
                }
                .frame(width: layout.displaySize.width, height: layout.displaySize.height)
                .contentShape(Rectangle())
                .gesture(addGesture(scale: layout.scale, pixelSize: redactor.pixelSize))
                .onTapGesture(coordinateSpace: .local) { location in
                    handleTap(at: location, scale: layout.scale)
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    updateCursor(for: phase)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 18))
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.38), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func baseImage(image: CGImage, displaySize: CGSize) -> some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize.width, height: displaySize.height)
    }

    private func addGesture(scale: CGFloat, pixelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .onChanged { value in
                guard redactor.editingMode == .add else { return }
                dragStart = value.startLocation
                dragCurrent = value.location
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragCurrent = nil
                }

                guard redactor.editingMode == .add else { return }

                let displayRect = rectBetween(value.startLocation, value.location)
                let imageRect = CGRect(
                    x: displayRect.minX / scale,
                    y: displayRect.minY / scale,
                    width: displayRect.width / scale,
                    height: displayRect.height / scale
                ).intersection(CGRect(origin: .zero, size: pixelSize))

                if imageRect.width > 4, imageRect.height > 4 {
                    redactor.addRedaction(rect: imageRect)
                }
            }
    }

    private func handleTap(at location: CGPoint, scale: CGFloat) {
        let pixelPoint = CGPoint(x: location.x / scale, y: location.y / scale)

        switch redactor.editingMode {
        case .view:
            if let findingID = redactor.findingID(at: pixelPoint) {
                redactor.selectFinding(findingID)
            }
        case .remove:
            if let index = redactor.redactionRects.firstIndex(where: { $0.contains(pixelPoint) }) {
                redactor.removeRedaction(at: index)
            }
        case .add:
            break
        }
    }

    private func updateCursor(for phase: HoverPhase) {
        switch phase {
        case .active:
            switch redactor.editingMode {
            case .view:
                NSCursor.arrow.set()
            case .add:
                NSCursor.crosshair.set()
            case .remove:
                NSCursor.disappearingItem.set()
            }
        case .ended:
            NSCursor.arrow.set()
        }
    }

    @ViewBuilder
    private func previewLayer(scale: CGFloat) -> some View {
        ForEach(Array(redactor.previewRectEntries.enumerated()), id: \.offset) { _, entry in
            let scaledRect = scaledRect(entry.rect, scale: scale)
            let accent = Color(nsColor: redactor.findingColor(for: entry.findingID))

            ZStack {
                Rectangle()
                    .fill(accent.opacity(0.18))
                Rectangle()
                    .strokeBorder(accent.opacity(0.88), lineWidth: 2)
            }
            .frame(width: scaledRect.width, height: scaledRect.height)
            .offset(x: scaledRect.minX, y: scaledRect.minY)
        }
    }

    @ViewBuilder
    private func redactionsLayer(image: CGImage, scale: CGFloat, displaySize: CGSize) -> some View {
        switch redactor.redactionStyle {
        case .blackRectangle:
            ForEach(Array(redactor.redactionRects.enumerated()), id: \.offset) { _, rect in
                let scaledRect = scaledRect(rect, scale: scale)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: scaledRect.width, height: scaledRect.height)
                    .offset(x: scaledRect.minX, y: scaledRect.minY)
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
                            let scaledRect = scaledRect(rect, scale: scale)
                            Rectangle()
                                .frame(width: scaledRect.width, height: scaledRect.height)
                                .offset(x: scaledRect.minX, y: scaledRect.minY)
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
                }
        }
    }

    @ViewBuilder
    private func focusOverlay(scale: CGFloat) -> some View {
        if let focusedFindingID = redactor.focusedFindingID {
            ForEach(Array(redactor.findingRects(for: focusedFindingID).enumerated()), id: \.offset) { _, rect in
                let scaledRect = scaledRect(rect, scale: scale)
                Rectangle()
                    .strokeBorder(
                        Color(nsColor: redactor.findingColor(for: focusedFindingID)).opacity(0.95),
                        lineWidth: 2.4
                    )
                    .frame(width: scaledRect.width, height: scaledRect.height)
                    .offset(x: scaledRect.minX, y: scaledRect.minY)
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

    private func rectBetween(_ start: CGPoint, _ end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

private struct ImageSurfaceLayout {
    let scale: CGFloat
    let displaySize: CGSize

    init(containerSize: CGSize, pixelSize: CGSize) {
        let scale = min(
            containerSize.width / pixelSize.width,
            containerSize.height / pixelSize.height,
            1.0
        )
        self.scale = scale
        self.displaySize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }
}

private struct DragPreview: View {
    let start: CGPoint
    let end: CGPoint

    var body: some View {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        Rectangle()
            .strokeBorder(
                FindingVisualSemantics.previewStrokeColor(for: FindingVisualSemantics.manualPreviewCategory),
                lineWidth: 1.5
            )
            .background(FindingVisualSemantics.previewFillColor(for: FindingVisualSemantics.manualPreviewCategory))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
