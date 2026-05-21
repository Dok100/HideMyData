import Foundation
import PDFKit

enum PDFAnnotationReviewLifecycleSupport {
    static func isRedaction(
        _ annotation: PDFAnnotation,
        redactionAnnotations: [PDFRedactor.RedactionEntry]
    ) -> Bool {
        redactionAnnotations.contains { $0.annotation === annotation }
    }

    static func findingID(
        at point: CGPoint,
        on page: PDFPage,
        redactionAnnotations: [PDFRedactor.RedactionEntry],
        previewAnnotations: [PDFRedactor.RedactionEntry]
    ) -> UUID? {
        let match = (redactionAnnotations + previewAnnotations)
            .filter { $0.page === page && $0.annotation.bounds.contains(point) }
            .min { lhs, rhs in
                let lhsArea = lhs.annotation.bounds.width * lhs.annotation.bounds.height
                let rhsArea = rhs.annotation.bounds.width * rhs.annotation.bounds.height
                if lhsArea == rhsArea {
                    return lhs.annotation.bounds.midY > rhs.annotation.bounds.midY
                }
                return lhsArea < rhsArea
            }
        return match?.findingID
    }

    static func pendingFindingIDs(reviewFindings: [ReviewFinding]) -> [UUID] {
        reviewFindings
            .filter { $0.status == .pending }
            .map(\.id)
    }

    static func clearAllVisuals(
        redactionAnnotations: inout [PDFRedactor.RedactionEntry],
        previewAnnotations: inout [PDFRedactor.RedactionEntry],
        dismissedPreviewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        for entry in redactionAnnotations {
            entry.page.removeAnnotation(entry.annotation)
        }
        for entry in previewAnnotations {
            entry.page.removeAnnotation(entry.annotation)
        }
        redactionAnnotations.removeAll()
        previewAnnotations.removeAll()
        dismissedPreviewAnnotations.removeAll()
    }

    static func clearReviewState(
        reviewFindings: inout [ReviewFinding],
        focusedFindingID: inout UUID?,
        focusTarget: inout PDFRedactor.FocusTarget?,
        currentPageIndex: inout Int,
        requestedPageIndex: inout Int?,
        debugEntries: inout [DetectionDebugEntry],
        dismissedPreviewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        reviewFindings.removeAll()
        focusedFindingID = nil
        focusTarget = nil
        currentPageIndex = 0
        requestedPageIndex = nil
        debugEntries.removeAll()
        dismissedPreviewAnnotations.removeAll()
    }

    static func removeRedactions(
        for findingID: UUID,
        redactionAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        let matching = redactionAnnotations.filter { $0.findingID == findingID }
        for entry in matching {
            entry.page.removeAnnotation(entry.annotation)
        }
        redactionAnnotations.removeAll { $0.findingID == findingID }
    }

    static func removePreviews(
        for findingID: UUID,
        previewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        let matching = previewAnnotations.filter { $0.findingID == findingID }
        for entry in matching {
            entry.page.removeAnnotation(entry.annotation)
        }
        previewAnnotations.removeAll { $0.findingID == findingID }
    }

    static func dismissPreviews(
        for findingID: UUID,
        previewAnnotations: inout [PDFRedactor.RedactionEntry],
        dismissedPreviewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        let matching = previewAnnotations.filter { $0.findingID == findingID }
        for entry in matching {
            entry.page.removeAnnotation(entry.annotation)
        }
        previewAnnotations.removeAll { $0.findingID == findingID }
        dismissedPreviewAnnotations.append(contentsOf: matching)
    }

    static func promotePreviewToRedaction(
        findingID: UUID,
        previewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) -> [PDFRedactor.RedactionEntry] {
        let matches = previewAnnotations.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return [] }
        for entry in matches {
            entry.page.removeAnnotation(entry.annotation)
        }
        previewAnnotations.removeAll { $0.findingID == findingID }
        return matches
    }

    static func restoreDismissedPreviews(
        for findingID: UUID,
        previewAnnotations: inout [PDFRedactor.RedactionEntry],
        dismissedPreviewAnnotations: inout [PDFRedactor.RedactionEntry]
    ) {
        let matches = dismissedPreviewAnnotations.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return }
        dismissedPreviewAnnotations.removeAll { $0.findingID == findingID }
        for entry in matches {
            entry.page.addAnnotation(entry.annotation)
        }
        previewAnnotations.append(contentsOf: matches)
    }

    static func reopenAcceptedFinding(
        _ findingID: UUID,
        redactionAnnotations: inout [PDFRedactor.RedactionEntry]
    ) -> [PDFRedactor.RedactionEntry] {
        let matches = redactionAnnotations.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return [] }
        for entry in matches {
            entry.page.removeAnnotation(entry.annotation)
        }
        redactionAnnotations.removeAll { $0.findingID == findingID }
        return matches
    }

    static func updateFinding(
        _ id: UUID,
        reviewFindings: inout [ReviewFinding],
        mutate: (inout ReviewFinding) -> Void
    ) {
        guard let index = reviewFindings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&reviewFindings[index])
    }

    static func syncFindingStateAfterRedactionRemoval(
        findingID: UUID,
        redactionAnnotations: [PDFRedactor.RedactionEntry],
        reviewFindings: inout [ReviewFinding]
    ) {
        guard !redactionAnnotations.contains(where: { $0.findingID == findingID }) else { return }
        updateFinding(findingID, reviewFindings: &reviewFindings) {
            if $0.status == .pending {
                $0.status = .rejected
            }
        }
    }

    static func firstFocusTarget(
        document: PDFDocument?,
        previewAnnotations: [PDFRedactor.RedactionEntry],
        redactionAnnotations: [PDFRedactor.RedactionEntry],
        findingID: UUID
    ) -> PDFRedactor.FocusTarget? {
        guard let document,
              let entry = (previewAnnotations + redactionAnnotations).first(where: { $0.findingID == findingID })
        else { return nil }
        let pageIndex = document.index(for: entry.page)
        guard pageIndex >= 0 else { return nil }
        return PDFRedactor.FocusTarget(pageIndex: pageIndex, rect: entry.annotation.bounds)
    }

    static func selectFinding(
        _ findingID: UUID,
        document: PDFDocument?,
        previewAnnotations: [PDFRedactor.RedactionEntry],
        redactionAnnotations: [PDFRedactor.RedactionEntry],
        focusedFindingID: inout UUID?,
        focusTarget: inout PDFRedactor.FocusTarget?,
        currentPageIndex: inout Int,
        focusRequestID: inout UUID
    ) {
        focusedFindingID = findingID
        focusTarget = nil
        guard let target = firstFocusTarget(
            document: document,
            previewAnnotations: previewAnnotations,
            redactionAnnotations: redactionAnnotations,
            findingID: findingID
        ) else { return }
        currentPageIndex = target.pageIndex
        focusTarget = target
        focusRequestID = UUID()
    }

    static func goToPage(
        _ pageIndex: Int,
        pageCount: Int,
        currentPageIndex: inout Int,
        requestedPageIndex: inout Int?,
        pageNavigationRequest: inout UUID
    ) {
        guard pageIndex >= 0, pageIndex < pageCount else { return }
        currentPageIndex = pageIndex
        requestedPageIndex = pageIndex
        pageNavigationRequest = UUID()
    }

    static func updateVisiblePage(
        index: Int,
        currentPageIndex: inout Int
    ) {
        guard index >= 0 else { return }
        currentPageIndex = index
    }
}
