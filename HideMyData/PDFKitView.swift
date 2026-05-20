import AppKit
import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument?
    let editingMode: EditingMode
    let redactor: PDFRedactor

    func makeNSView(context: Context) -> InteractivePDFView {
        let view = InteractivePDFView()
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.backgroundColor = .clear
        view.redactor = redactor
        view.editingMode = editingMode
        return view
    }

    func updateNSView(_ nsView: InteractivePDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
            nsView.goToFirstPage(nil)

            if let document, let firstPage = document.page(at: 0) {
                let currentPage = nsView.currentPage ?? firstPage
                redactor.updateVisiblePage(index: max(document.index(for: currentPage), 0))
            }
        }

        if nsView.editingMode != editingMode {
            nsView.editingMode = editingMode
        }

        if nsView.redactor !== redactor {
            nsView.redactor = redactor
        }

        nsView.navigateIfNeeded(
            requestID: redactor.pageNavigationRequest,
            pageIndex: redactor.requestedPageIndex
        )
        nsView.focusIfNeeded(
            requestID: redactor.focusRequestID,
            target: redactor.focusTarget
        )
    }
}

final class InteractivePDFView: PDFView {
    weak var redactor: PDFRedactor?

    var editingMode: EditingMode = .view {
        didSet {
            guard oldValue != editingMode else { return }
            applyCursor()
        }
    }

    private var dragStart: NSPoint?
    private weak var dragPage: PDFPage?
    private var previewAnnotation: PDFAnnotation?
    private var cursorTrackingArea: NSTrackingArea?
    private var lastFocusRequestID: UUID?
    private var lastPageNavigationRequestID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func setCursorFor(_ areaOfInterest: PDFAreaOfInterest) {
        guard editingMode == .view else {
            applyCursor()
            return
        }
        super.setCursorFor(areaOfInterest)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        applyCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        applyCursor()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard editingMode == .view else {
            applyCursor()
            return
        }
        super.cursorUpdate(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let redactor else {
            super.mouseDown(with: event)
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)

        switch editingMode {
        case .view:
            guard let page = page(for: viewPoint, nearest: true) else {
                super.mouseDown(with: event)
                return
            }
            let pagePoint = convert(viewPoint, to: page)
            if let findingID = redactor.findingID(at: pagePoint, on: page) {
                redactor.selectFinding(findingID)
                return
            }
            super.mouseDown(with: event)

        case .remove:
            guard let page = page(for: viewPoint, nearest: true) else { return }
            let pagePoint = convert(viewPoint, to: page)
            if let annotation = page.annotation(at: pagePoint), redactor.isRedaction(annotation) {
                redactor.removeRedaction(annotation, on: page)
            }

        case .add:
            guard let page = page(for: viewPoint, nearest: true) else { return }
            dragStart = convert(viewPoint, to: page)
            dragPage = page
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard editingMode == .add,
              let dragStart,
              let dragPage else {
            super.mouseDragged(with: event)
            return
        }

        let pagePoint = convert(convert(event.locationInWindow, from: nil), to: dragPage)
        let rect = normalizedRect(from: dragStart, to: pagePoint)

        if let previewAnnotation {
            dragPage.removeAnnotation(previewAnnotation)
        }

        let preview = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        preview.border = nil
        preview.color = FindingVisualSemantics.previewStrokeNSColor(for: FindingVisualSemantics.manualPreviewCategory)
        preview.interiorColor = FindingVisualSemantics.previewFillNSColor(for: FindingVisualSemantics.manualPreviewCategory)
        dragPage.addAnnotation(preview)
        previewAnnotation = preview
    }

    override func mouseUp(with event: NSEvent) {
        guard editingMode == .add,
              let dragStart,
              let dragPage,
              let redactor else {
            super.mouseUp(with: event)
            clearDragState()
            return
        }

        let pagePoint = convert(convert(event.locationInWindow, from: nil), to: dragPage)
        let rect = normalizedRect(from: dragStart, to: pagePoint)

        if let previewAnnotation {
            dragPage.removeAnnotation(previewAnnotation)
        }

        if rect.width > 4, rect.height > 4 {
            redactor.addRedaction(rect: rect, on: dragPage)
        }

        clearDragState()
    }

    func focusIfNeeded(requestID: UUID, target: PDFRedactor.FocusTarget?) {
        guard lastFocusRequestID != requestID else { return }
        lastFocusRequestID = requestID

        guard let target, let page = document?.page(at: target.pageIndex) else { return }
        let focusRect = expandedContextRect(for: target.rect, on: page)
        go(to: focusRect, on: page)
    }

    func navigateIfNeeded(requestID: UUID, pageIndex: Int?) {
        guard lastPageNavigationRequestID != requestID else { return }
        lastPageNavigationRequestID = requestID

        guard let pageIndex, let page = document?.page(at: pageIndex) else { return }
        go(to: page)
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearSelectionIfNeeded),
            name: .PDFViewSelectionChanged,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageChange),
            name: .PDFViewPageChanged,
            object: self
        )
    }

    @objc
    private func clearSelectionIfNeeded() {
        if currentSelection != nil {
            setCurrentSelection(nil, animate: false)
        }
    }

    @objc
    private func handlePageChange() {
        guard let currentPage, let document else { return }
        let pageIndex = document.index(for: currentPage)
        if pageIndex >= 0 {
            redactor?.updateVisiblePage(index: pageIndex)
        }
    }

    private func applyCursor() {
        switch editingMode {
        case .view:
            break
        case .add:
            NSCursor.crosshair.set()
        case .remove:
            NSCursor.pointingHand.set()
        }
    }

    private func clearDragState() {
        dragStart = nil
        dragPage = nil
        previewAnnotation = nil
    }

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func expandedContextRect(for rect: CGRect, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .mediaBox)
        let outerPaddingRect = rect.insetBy(dx: -80, dy: -110)
        let minWidth = max(rect.width + 100, pageBounds.width * 0.36)
        let minHeight = max(rect.height + 130, pageBounds.height * 0.20)
        let centeredRect = CGRect(
            x: rect.midX - minWidth / 2,
            y: rect.midY - minHeight / 2,
            width: minWidth,
            height: minHeight
        )
        return outerPaddingRect.union(centeredRect).intersection(pageBounds)
    }
}
