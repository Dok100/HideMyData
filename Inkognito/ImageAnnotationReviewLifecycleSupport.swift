import Foundation
import CoreGraphics

enum ImageAnnotationReviewLifecycleSupport {
    static func pendingFindingIDs(reviewFindings: [ReviewFinding]) -> [UUID] {
        reviewFindings
            .filter { $0.status == .pending }
            .map(\.id)
    }

    static func findingID(
        at point: CGPoint,
        redactionEntries: [ImageRedactor.RedactionEntry],
        previewEntries: [ImageRedactor.RedactionEntry]
    ) -> UUID? {
        let match = (redactionEntries + previewEntries)
            .filter { $0.rect.contains(point) }
            .min { lhs, rhs in
                let lhsArea = lhs.rect.width * lhs.rect.height
                let rhsArea = rhs.rect.width * rhs.rect.height
                if lhsArea == rhsArea {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhsArea < rhsArea
            }
        return match?.findingID
    }

    static func totalVisibleRectCount(
        redactionEntries: [ImageRedactor.RedactionEntry],
        previewEntries: [ImageRedactor.RedactionEntry]
    ) -> Int {
        redactionEntries.count + previewEntries.count
    }

    static func clearRedactions(
        redactionEntries: inout [ImageRedactor.RedactionEntry],
        previewEntries: inout [ImageRedactor.RedactionEntry],
        dismissedPreviewEntries: inout [ImageRedactor.RedactionEntry]
    ) {
        redactionEntries.removeAll()
        previewEntries.removeAll()
        dismissedPreviewEntries.removeAll()
    }

    static func rejectFinding(
        _ findingID: UUID,
        previewEntries: inout [ImageRedactor.RedactionEntry],
        dismissedPreviewEntries: inout [ImageRedactor.RedactionEntry]
    ) {
        let matches = previewEntries.filter { $0.findingID == findingID }
        previewEntries.removeAll { $0.findingID == findingID }
        dismissedPreviewEntries.append(contentsOf: matches)
    }

    static func reopenAcceptedFinding(
        _ findingID: UUID,
        redactionEntries: inout [ImageRedactor.RedactionEntry],
        previewEntries: inout [ImageRedactor.RedactionEntry]
    ) -> Bool {
        let matches = redactionEntries.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return false }
        redactionEntries.removeAll { $0.findingID == findingID }
        previewEntries.append(contentsOf: matches)
        return true
    }

    static func reopenRejectedFinding(
        _ findingID: UUID,
        previewEntries: inout [ImageRedactor.RedactionEntry],
        dismissedPreviewEntries: inout [ImageRedactor.RedactionEntry]
    ) -> Bool {
        let matches = dismissedPreviewEntries.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return false }
        dismissedPreviewEntries.removeAll { $0.findingID == findingID }
        previewEntries.append(contentsOf: matches)
        return true
    }

    static func clearReviewState(
        reviewFindings: inout [ReviewFinding],
        focusedFindingID: inout UUID?,
        debugEntries: inout [DetectionDebugEntry],
        dismissedPreviewEntries: inout [ImageRedactor.RedactionEntry]
    ) {
        reviewFindings.removeAll()
        focusedFindingID = nil
        debugEntries.removeAll()
        dismissedPreviewEntries.removeAll()
    }

    static func promotePreviewToRedaction(
        findingID: UUID,
        previewEntries: inout [ImageRedactor.RedactionEntry]
    ) -> [CGRect] {
        let matches = previewEntries.filter { $0.findingID == findingID }
        guard !matches.isEmpty else { return [] }
        previewEntries.removeAll { $0.findingID == findingID }
        return matches.map(\.rect)
    }

    static func syncFindingStateAfterRedactionRemoval(
        findingID: UUID,
        redactionEntries: [ImageRedactor.RedactionEntry],
        reviewFindings: inout [ReviewFinding]
    ) {
        guard !redactionEntries.contains(where: { $0.findingID == findingID }) else { return }
        updateFinding(findingID, reviewFindings: &reviewFindings) {
            if $0.status == .pending {
                $0.status = .rejected
            }
        }
    }

    static func updateFinding(
        _ id: UUID,
        reviewFindings: inout [ReviewFinding],
        mutate: (inout ReviewFinding) -> Void
    ) {
        guard let index = reviewFindings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&reviewFindings[index])
    }
}
