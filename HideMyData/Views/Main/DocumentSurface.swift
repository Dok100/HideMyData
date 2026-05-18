import SwiftUI

struct DocumentSurface: View {
    @Bindable var redactor: PDFRedactor

    var body: some View {
        if let document = redactor.document {
            ZStack(alignment: .topLeading) {
                PDFKitView(
                    document: document,
                    editingMode: redactor.editingMode,
                    redactor: redactor
                )
                .clipShape(.rect(cornerRadius: 18))

                if let notice = redactor.detectionNotice {
                    detectionNoticeCard(title: notice.title, message: notice.message)
                        .padding(18)
                }
            }
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.38), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }
}

func detectionNoticeCard(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(.orange)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }

        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: 320, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.orange.opacity(0.25), lineWidth: 0.8)
    )
}
