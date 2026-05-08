import SwiftUI
internal import UniformTypeIdentifiers

struct MainView: View {
    let detector: PIIDetector
    @Bindable var pdfRedactor: PDFRedactor
    @Bindable var imageRedactor: ImageRedactor
    @Bindable var recents: RecentsStore
    @Binding var inputMode: InputMode
    @State private var showHome: Bool = false
    @AppStorage("HMD.recents.enabled") private var recentsEnabled: Bool = true
    @State private var saveWarningPresented = false

    private var activeIsEmpty: Bool {
        switch inputMode {
        case .pdf: return pdfRedactor.document == nil
        case .image: return imageRedactor.image == nil
        }
    }

    private var shouldShowEmpty: Bool { showHome || activeIsEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            if shouldShowEmpty {
                EmptyState(
                    inputMode: $inputMode,
                    recents: recents,
                    recentsEnabled: $recentsEnabled,
                    onOpenPDF: openPDFAndAdd,
                    onOpenImage: openImageAndAdd,
                    onDropFile: handleDrop,
                    onOpenRecent: openRecent
                )
            } else {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    Group {
                        switch inputMode {
                        case .pdf:
                            DocumentSurface(redactor: pdfRedactor)
                        case .image:
                            ImageDocumentSurface(redactor: imageRedactor)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsReviewSidebar {
                        ReviewSidebar(
                            findings: currentReviewFindings,
                            pendingCount: currentPendingReviewCount,
                            onAcceptAll: acceptAllFindings,
                            onSelect: selectFinding,
                            onAccept: acceptFinding,
                            onReject: rejectFinding
                        )
                        .padding(EdgeInsets(top: 84, leading: 0, bottom: 18, trailing: 18))
                    }
                }

                FloatingToolbar(
                    detector: detector,
                    pdfRedactor: pdfRedactor,
                    imageRedactor: imageRedactor,
                    inputMode: inputMode,
                    onSaveRequest: requestSave
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }

            StatusPill(
                detector: detector,
                pdfRedactor: pdfRedactor,
                imageRedactor: imageRedactor,
                inputMode: inputMode,
                showingDocument: !shouldShowEmpty
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.horizontal, 22)
            .padding(.top, shouldShowEmpty ? 22 : 78)
            .allowsHitTesting(false)

            if !shouldShowEmpty {
                HomeButton { showHome = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(22)
            }
        }
        .onAppear { recents.setEnabled(recentsEnabled) }
        .onChange(of: recentsEnabled) { _, enabled in
            recents.setEnabled(enabled)
        }
        .alert("Prüfung erforderlich", isPresented: $saveWarningPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte bestätige oder lehne zuerst alle offenen Treffer ab, bevor du speicherst.")
        }
    }

    // MARK: - Open actions

    private func openPDFAndAdd() {
        guard pdfRedactor.openPDF(), let url = pdfRedactor.sourceURL else { return }
        recents.add(url: url, kind: .pdf)
        showHome = false
    }

    private func openImageAndAdd() {
        guard imageRedactor.openImage(), let url = imageRedactor.sourceURL else { return }
        recents.add(url: url, kind: .image)
        showHome = false
    }

    private func handleDrop(_ url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        if type.conforms(to: .pdf) {
            inputMode = .pdf
            if pdfRedactor.loadPDF(from: url) {
                recents.add(url: url, kind: .pdf)
                showHome = false
            }
        } else if type.conforms(to: .image) {
            inputMode = .image
            if imageRedactor.loadImage(from: url) {
                recents.add(url: url, kind: .image)
                showHome = false
            }
        }
    }

    private func openRecent(_ item: RecentItem) {
        guard let resolved = recents.resolve(item) else {
            recents.remove(item)
            return
        }
        defer { if resolved.didStartScope { resolved.url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: resolved.url) else {
            recents.remove(item)
            return
        }

        switch item.kind {
        case .pdf:
            inputMode = .pdf
            if pdfRedactor.loadPDF(data: data, originalURL: resolved.url) {
                recents.add(url: resolved.url, kind: .pdf)
                showHome = false
            }
        case .image:
            inputMode = .image
            if imageRedactor.loadImage(data: data, originalURL: resolved.url) {
                recents.add(url: resolved.url, kind: .image)
                showHome = false
            }
        }
    }

    private var showsReviewSidebar: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasReviewFindings
        case .image: imageRedactor.hasReviewFindings
        }
    }

    private var currentReviewFindings: [ReviewFinding] {
        switch inputMode {
        case .pdf: pdfRedactor.reviewFindings
        case .image: imageRedactor.reviewFindings
        }
    }

    private var currentPendingReviewCount: Int {
        switch inputMode {
        case .pdf: pdfRedactor.pendingReviewCount
        case .image: imageRedactor.pendingReviewCount
        }
    }

    private var hasPendingReview: Bool {
        switch inputMode {
        case .pdf: pdfRedactor.hasPendingReview
        case .image: imageRedactor.hasPendingReview
        }
    }

    private func requestSave() {
        guard !hasPendingReview else {
            saveWarningPresented = true
            return
        }
        switch inputMode {
        case .pdf: pdfRedactor.save()
        case .image: imageRedactor.save()
        }
    }

    private func selectFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.selectFinding(id)
        case .image: imageRedactor.selectFinding(id)
        }
    }

    private func acceptFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.acceptFinding(id)
        case .image: imageRedactor.acceptFinding(id)
        }
    }

    private func acceptAllFindings() {
        switch inputMode {
        case .pdf: pdfRedactor.acceptAllFindings()
        case .image: imageRedactor.acceptAllFindings()
        }
    }

    private func rejectFinding(_ id: UUID) {
        switch inputMode {
        case .pdf: pdfRedactor.rejectFinding(id)
        case .image: imageRedactor.rejectFinding(id)
        }
    }
}

private struct ReviewSidebar: View {
    let findings: [ReviewFinding]
    let pendingCount: Int
    let onAcceptAll: () -> Void
    let onSelect: (UUID) -> Void
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    @State private var showOnlyPending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Treffer prüfen")
                            .font(.system(size: 16, weight: .semibold))
                        Text(headerText)
                            .font(.system(size: 12))
                            .foregroundStyle(pendingCount > 0 ? .orange : .secondary)
                    }

                    Spacer(minLength: 0)

                    if pendingCount > 0 {
                        Button("Alle bestätigen", action: onAcceptAll)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }

                Toggle("Nur offene Treffer", isOn: $showOnlyPending)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredFindings) { finding in
                        ReviewFindingRow(
                            finding: finding,
                            onSelect: { onSelect(finding.id) },
                            onAccept: { onAccept(finding.id) },
                            onReject: { onReject(finding.id) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(.white.opacity(0.06)), in: .rect(cornerRadius: 22))
    }

    private var headerText: String {
        if findings.isEmpty {
            return "Noch keine Treffer vorhanden."
        }
        if pendingCount > 0 {
            return "\(pendingCount) Treffer müssen vor dem Speichern bestätigt oder abgelehnt werden."
        }
        return "Alle Treffer wurden geprüft."
    }

    private var filteredFindings: [ReviewFinding] {
        if showOnlyPending {
            return findings.filter { $0.status == .pending }
        }
        return findings
    }
}

private struct ReviewFindingRow: View {
    let finding: ReviewFinding
    let onSelect: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(finding.category)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        statusBadge
                    }

                    Text(finding.snippet.isEmpty ? "Ohne Textausschnitt" : finding.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        sourceBadge
                        confidenceBadge
                        if let pageIndex = finding.pageIndex {
                            Text("Seite \(pageIndex + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.05), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if finding.status == .pending {
                HStack(spacing: 8) {
                    Button("Bestätigen", action: onAccept)
                        .buttonStyle(.glassProminent)
                    Button("Ablehnen", action: onReject)
                        .buttonStyle(.glass)
                }
                .controlSize(.small)
            }
        }
    }

    private var sourceBadge: some View {
        Text(finding.source.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(sourceColor.opacity(0.18), in: Capsule())
            .foregroundStyle(sourceColor)
    }

    private var confidenceBadge: some View {
        Text("Konf. \(confidenceText)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var statusBadge: some View {
        Text(finding.status.label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var sourceColor: Color {
        switch finding.source {
        case .model: .blue
        case .pattern: .mint
        }
    }

    private var statusColor: Color {
        switch finding.status {
        case .pending: .orange
        case .accepted: .green
        case .rejected: .red
        }
    }

    private var confidenceText: String {
        (Double(finding.confidence) * 100)
            .formatted(.number.precision(.fractionLength(0))) + "%"
    }
}
