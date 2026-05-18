import SwiftUI

struct StatusPill: View {
    let detector: PIIDetector
    let pdfRedactor: PDFRedactor
    let imageRedactor: ImageRedactor
    let inputMode: InputMode
    let showingDocument: Bool

    @State private var dismissed = false

    private var resolvedContent: StatusPillContent? {
        StatusPillContent.resolve(
            detector: detector,
            pdfRedactor: pdfRedactor,
            imageRedactor: imageRedactor,
            inputMode: inputMode,
            showingDocument: showingDocument
        )
    }

    var body: some View {
        let content = resolvedContent
        let visible = (content?.autoDismissAfter != nil && dismissed) ? nil : content

        Group {
            if let visible {
                HStack(spacing: 8) {
                    visible.kind.icon
                    Text(visible.text)
                        .font(.callout)
                        .foregroundStyle(visible.kind.foreground)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(visible.kind.tint), in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.smooth(duration: 0.25), value: visible.text)
            }
        }
        .task(id: content) {
            dismissed = false
            guard let timeout = content?.autoDismissAfter else { return }
            try? await Task.sleep(for: timeout)
            dismissed = true
        }
    }
}

struct StatusPillContent: Equatable {
    enum Kind: Equatable {
        case progress
        case info(String)
        case success(String)
        case warning(String)

        @ViewBuilder var icon: some View {
            switch self {
            case .progress:
                ProgressView().controlSize(.small)
            case .info(let symbol):
                Image(systemName: symbol)
                    .foregroundStyle(StatusVisualSemantics.pillIconStyle(for: self))
            case .success(let symbol):
                Image(systemName: symbol)
                    .foregroundStyle(StatusVisualSemantics.pillIconStyle(for: self))
            case .warning(let symbol):
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

    static func resolve(
        detector: PIIDetector,
        pdfRedactor: PDFRedactor,
        imageRedactor: ImageRedactor,
        inputMode: InputMode,
        showingDocument: Bool
    ) -> StatusPillContent? {
        if let dpill = detector.statusPill { return dpill }
        guard showingDocument else { return nil }
        switch inputMode {
        case .pdf: return pdfRedactor.statusPill
        case .image: return imageRedactor.statusPill
        }
    }
}

private extension PIIDetector {
    var statusPill: StatusPillContent? {
        switch phase {
        case .ready: nil
        case .running:
            .init(kind: .progress, text: "Erkennung läuft…")
        case .loadingModel, .warmingUp:
            .init(kind: .progress, text: "\(statusText)")
        case .failed(let msg):
            .init(kind: .warning("exclamationmark.triangle.fill"), text: "\(msg)")
        default: nil
        }
    }
}

private extension PDFRedactor {
    var statusPill: StatusPillContent? {
        guard !statusText.isEmpty, phase != .empty else { return nil }
        return switch phase {
        case .redacted(_, let rects):
            StatusPillContent(
                kind: .success("checkmark.seal.fill"),
                text: "\(rects) Schwärzung\(rects == 1 ? "" : "en")",
                autoDismissAfter: .seconds(3)
            )
        case .saved(let url):
            StatusPillContent(
                kind: .success("tray.and.arrow.down.fill"),
                text: "\(lastExportReport?.shortStatusText ?? "Gespeichert → \(url.lastPathComponent)")"
            )
        case .detecting:
            StatusPillContent(kind: .progress, text: "Erkennung läuft…")
        case .failed(let msg):
            StatusPillContent(kind: .warning("exclamationmark.triangle.fill"), text: "\(msg)")
        default: nil
        }
    }
}

private extension ImageRedactor {
    var statusPill: StatusPillContent? {
        guard !statusText.isEmpty, phase != .empty else { return nil }
        return switch phase {
        case .redacted(_, let rects):
            StatusPillContent(
                kind: .success("checkmark.seal.fill"),
                text: "\(rects) Schwärzung\(rects == 1 ? "" : "en")",
                autoDismissAfter: .seconds(3)
            )
        case .saved(let url):
            StatusPillContent(
                kind: .success("tray.and.arrow.down.fill"),
                text: "\(lastExportReport?.shortStatusText ?? "Gespeichert → \(url.lastPathComponent)")"
            )
        case .detecting:
            StatusPillContent(kind: .progress, text: "Erkennung läuft…")
        case .failed(let msg):
            StatusPillContent(kind: .warning("exclamationmark.triangle.fill"), text: "\(msg)")
        default: nil
        }
    }
}
