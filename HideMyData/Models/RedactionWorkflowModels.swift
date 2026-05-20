import Foundation

struct DocumentDetectionNotice: Equatable {
    let title: String
    let message: String
}

enum DocumentOpenResult {
    case cancelled
    case opened(URL)
    case failed(String)
}

enum DocumentSaveResult {
    case cancelled
    case saved(URL)
    case failed(String)
}

struct RedactionExportResult {
    let url: URL
    let report: ExportValidationReport
}

enum RedactionPhase: Equatable {
    case empty
    case loaded
    case detecting
    case redacted(spanCount: Int, rectCount: Int)
    case saved(URL)
    case failed(String)
}
