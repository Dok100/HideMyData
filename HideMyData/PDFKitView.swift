import SwiftUI
import PDFKit
import AppKit

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
                let current = nsView.currentPage ?? firstPage
                redactor.updateVisiblePage(index: max(document.index(for: current), 0))
            }
        }
        if nsView.editingMode != editingMode {
            nsView.editingMode = editingMode
        }
        if nsView.redactor !== redactor {
            nsView.redactor = redactor
        }
        nsView.navigateIfNeeded(requestID: redactor.pageNavigationRequest, pageIndex: redactor.requestedPageIndex)
        nsView.focusIfNeeded(requestID: redactor.focusRequestID, target: redactor.focusTarget)
    }
}

final class InteractivePDFView: PDFView {
    weak var redactor: PDFRedactor?

    var editingMode: EditingMode = .view {
        didSet {
            if oldValue != editingMode {
                applyCursor()
            }
        }
    }

    private var dragStart: NSPoint?
    private var dragPage: PDFPage?
    private var previewAnnotation: PDFAnnotation?
    private var cursorTrackingArea: NSTrackingArea?
    private var lastFocusRequestID: UUID?
    private var lastPageNavigationRequestID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearAnySelection),
            name: .PDFViewSelectionChanged,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageDidChange),
            name: .PDFViewPageChanged,
            object: self
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearAnySelection),
            name: .PDFViewSelectionChanged,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageDidChange),
            name: .PDFViewPageChanged,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func clearAnySelection() {
        if currentSelection != nil {
            setCurrentSelection(nil, animate: false)
        }
    }

    @objc private func pageDidChange() {
        guard let currentPage, let document = document else { return }
        let pageIndex = document.index(for: currentPage)
        if pageIndex >= 0 {
            redactor?.updateVisiblePage(index: pageIndex)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func setCursorFor(_ areaOfInterest: PDFAreaOfInterest) {
        if editingMode != .view {
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
        if editingMode == .view {
            super.cursorUpdate(with: event)
        } else {
            applyCursor()
        }
    }

    private func applyCursor() {
        switch editingMode {
        case .view: break // let PDFView decide
        case .add: NSCursor.crosshair.set()
        case .remove: NSCursor.pointingHand.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let redactor else { super.mouseDown(with: event); return }
        let viewLocation = convert(event.locationInWindow, from: nil)

        switch editingMode {
        case .view:
            if let page = page(for: viewLocation, nearest: true) {
                let pagePoint = convert(viewLocation, to: page)
                if let findingID = redactor.findingID(at: pagePoint, on: page) {
                    redactor.selectFinding(findingID)
                    return
                }
            }
            super.mouseDown(with: event)
            return

        case .remove:
            guard let page = page(for: viewLocation, nearest: true) else { return }
            let pagePoint = convert(viewLocation, to: page)
            if let ann = page.annotation(at: pagePoint), redactor.isRedaction(ann) {
                redactor.removeRedaction(ann, on: page)
            }

        case .add:
            guard let page = page(for: viewLocation, nearest: true) else { return }
            let pagePoint = convert(viewLocation, to: page)
            dragStart = pagePoint
            dragPage = page
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard editingMode == .add, let start = dragStart, let page = dragPage else {
            super.mouseDragged(with: event)
            return
        }
        let viewLocation = convert(event.locationInWindow, from: nil)
        let pagePoint = convert(viewLocation, to: page)
        let rect = makeRect(start, pagePoint)

        if let prev = previewAnnotation {
            page.removeAnnotation(prev)
        }
        let preview = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        preview.border = nil
        let previewTint = FindingVisualSemantics.nsColor(for: "private_address")
        preview.color = previewTint.withAlphaComponent(0.7)
        preview.interiorColor = previewTint.withAlphaComponent(0.25)
        page.addAnnotation(preview)
        previewAnnotation = preview
    }

    override func mouseUp(with event: NSEvent) {
        guard editingMode == .add, let start = dragStart, let page = dragPage, let redactor else {
            super.mouseUp(with: event)
            cleanupDrag()
            return
        }

        let viewLocation = convert(event.locationInWindow, from: nil)
        let pagePoint = convert(viewLocation, to: page)
        let rect = makeRect(start, pagePoint)

        if let prev = previewAnnotation {
            page.removeAnnotation(prev)
        }

        if rect.width > 4 && rect.height > 4 {
            redactor.addRedaction(rect: rect, on: page)
        }
        cleanupDrag()
    }

    private func cleanupDrag() {
        dragStart = nil
        dragPage = nil
        previewAnnotation = nil
    }

    private func makeRect(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    func focusIfNeeded(requestID: UUID, target: PDFRedactor.FocusTarget?) {
        guard lastFocusRequestID != requestID else { return }
        lastFocusRequestID = requestID
        guard let target, let page = document?.page(at: target.pageIndex) else { return }
        let contextRect = expandedContextRect(for: target.rect, on: page)
        go(to: contextRect, on: page)
    }

    func navigateIfNeeded(requestID: UUID, pageIndex: Int?) {
        guard lastPageNavigationRequestID != requestID else { return }
        lastPageNavigationRequestID = requestID
        guard let pageIndex, let page = document?.page(at: pageIndex) else { return }
        go(to: page)
    }

    private func expandedContextRect(for rect: CGRect, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .mediaBox)
        let expanded = rect.insetBy(dx: -80, dy: -110)
        let minWidth = max(rect.width + 100, pageBounds.width * 0.36)
        let minHeight = max(rect.height + 130, pageBounds.height * 0.20)
        let centered = CGRect(
            x: rect.midX - (minWidth / 2),
            y: rect.midY - (minHeight / 2),
            width: minWidth,
            height: minHeight
        )
        return expanded.union(centered).intersection(pageBounds)
    }
}
