import SwiftUI

struct StatusPill: View {
    let detector: PIIDetector
    let pdfRedactor: PDFRedactor
    let imageRedactor: ImageRedactor
    let inputMode: InputMode
    let showingDocument: Bool

    @State private var dismissedAutoMessage = false

    private var currentContent: StatusPillContent? {
        StatusPillContent.current(
            detector: detector,
            pdfRedactor: pdfRedactor,
            imageRedactor: imageRedactor,
            inputMode: inputMode,
            showingDocument: showingDocument
        )
    }

    var body: some View {
        let content = visibleContent

        Group {
            if let content {
                HStack(spacing: 8) {
                    content.kind.icon

                    Text(content.text)
                        .font(.callout)
                        .foregroundStyle(content.kind.foreground)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(content.kind.tint), in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.smooth(duration: 0.25), value: content)
            }
        }
        .task(id: currentContent) {
            await scheduleAutoDismissIfNeeded(for: currentContent)
        }
    }

    private var visibleContent: StatusPillContent? {
        guard let currentContent else { return nil }
        if currentContent.autoDismissAfter != nil, dismissedAutoMessage {
            return nil
        }
        return currentContent
    }

    private func scheduleAutoDismissIfNeeded(for content: StatusPillContent?) async {
        dismissedAutoMessage = false
        guard let timeout = content?.autoDismissAfter else { return }
        try? await Task.sleep(for: timeout)
        dismissedAutoMessage = true
    }
}

struct StatusPillContent: Equatable {
    enum Kind: Equatable {
        case progress
        case info(String)
        case success(String)
        case warning(String)

        @ViewBuilder
        var icon: some View {
            switch self {
            case .progress:
                ProgressView()
                    .controlSize(.small)
            case .info(let symbol), .success(let symbol), .warning(let symbol):
                Image(systemName: symbol)
                    .foregroundStyle(StatusVisualSemantics.pillIconStyle(for: self))
            }
        }

        var foreground: AnyShapeStyle {
            StatusVisualSemantics.pillForeground(for: self)
        }

        var tint: Color {
            StatusVisualSemantics.pillTint(for: self)
        }
    }

    let kind: Kind
    let text: LocalizedStringKey
    let autoDismissAfter: Duration?

    init(kind: Kind, text: LocalizedStringKey, autoDismissAfter: Duration? = nil) {
        self.kind = kind
        self.text = text
        self.autoDismissAfter = autoDismissAfter
    }

    static func current(
        detector: PIIDetector,
        pdfRedactor: PDFRedactor,
        imageRedactor: ImageRedactor,
        inputMode: InputMode,
        showingDocument: Bool
    ) -> StatusPillContent? {
        if let detectorContent = detector.statusPillContent {
            return detectorContent
        }

        guard showingDocument else { return nil }

        switch inputMode {
        case .pdf:
            return pdfRedactor.statusPillContent
        case .image:
            return imageRedactor.statusPillContent
        }
    }
}

private extension PIIDetector {
    var statusPillContent: StatusPillContent? {
        switch phase {
        case .ready:
            nil
        case .running:
            .init(kind: .progress, text: "Erkennung läuft…")
        case .loadingModel, .warmingUp:
            .init(kind: .progress, text: "\(statusText)")
        case .failed(let message):
            .init(kind: .warning("exclamationmark.triangle.fill"), text: "\(message)")
        default:
            nil
        }
    }
}

private extension PDFRedactor {
    var statusPillContent: StatusPillContent? {
        guard !statusText.isEmpty, phase != .empty else { return nil }

        switch phase {
        case .redacted(_, let rectCount):
            return StatusPillContent(
                kind: .success("checkmark.seal.fill"),
                text: "\(rectCount) Schwärzung\(rectCount == 1 ? "" : "en")",
                autoDismissAfter: .seconds(3)
            )
        case .saved(let url):
            return StatusPillContent(
                kind: .success("tray.and.arrow.down.fill"),
                text: "\(lastExportReport?.shortStatusText ?? "Gespeichert → \(url.lastPathComponent)")"
            )
        case .detecting:
            return StatusPillContent(kind: .progress, text: "Erkennung läuft…")
        case .failed(let message):
            return StatusPillContent(kind: .warning("exclamationmark.triangle.fill"), text: "\(message)")
        default:
            return nil
        }
    }
}

private extension ImageRedactor {
    var statusPillContent: StatusPillContent? {
        guard !statusText.isEmpty, phase != .empty else { return nil }

        switch phase {
        case .redacted(_, let rectCount):
            return StatusPillContent(
                kind: .success("checkmark.seal.fill"),
                text: "\(rectCount) Schwärzung\(rectCount == 1 ? "" : "en")",
                autoDismissAfter: .seconds(3)
            )
        case .saved(let url):
            return StatusPillContent(
                kind: .success("tray.and.arrow.down.fill"),
                text: "\(lastExportReport?.shortStatusText ?? "Gespeichert → \(url.lastPathComponent)")"
            )
        case .detecting:
            return StatusPillContent(kind: .progress, text: "Erkennung läuft…")
        case .failed(let message):
            return StatusPillContent(kind: .warning("exclamationmark.triangle.fill"), text: "\(message)")
        default:
            return nil
        }
    }
}
