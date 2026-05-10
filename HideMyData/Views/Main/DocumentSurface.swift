import SwiftUI

struct DocumentSurface: View {
    @Bindable var redactor: PDFRedactor

    var body: some View {
        if let document = redactor.document {
            PDFKitView(
                document: document,
                editingMode: redactor.editingMode,
                redactor: redactor
            )
            .clipShape(.rect(cornerRadius: 18))
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
