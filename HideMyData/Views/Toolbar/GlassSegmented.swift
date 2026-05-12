import SwiftUI

struct GlassSegmented<T: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    enum VisualStyle {
        case standard
        case emphasized
    }

    struct Item: Identifiable {
        let value: T
        let image: String
        let label: String
        let help: String
        var id: T { value }
    }

    @Binding var selection: T
    let items: [Item]
    let style: VisualStyle
    @Namespace private var ns

    init(selection: Binding<T>, items: [Item], style: VisualStyle = .standard) {
        self._selection = selection
        self.items = items
        self.style = style
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Segment(
                    item: item,
                    isSelected: selection == item.value,
                    style: style,
                    namespace: ns,
                    action: { select(item.value) }
                )
            }
        }
        .padding(3)
        .background(backgroundColor, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: style == .emphasized ? 0.8 : 0.5)
        )
    }

    private var backgroundColor: Color {
        switch style {
        case .standard:
            colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color(nsColor: .controlBackgroundColor).opacity(0.92)
        case .emphasized:
            colorScheme == .dark
                ? Color.white.opacity(0.05)
                : Color(nsColor: .windowBackgroundColor).opacity(0.98)
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard:
            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
        case .emphasized:
            colorScheme == .dark ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.18)
        }
    }

    private func select(_ value: T) {
        withAnimation(.smooth(duration: 0.28)) {
            selection = value
        }
    }
}

private struct Segment<T: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: GlassSegmented<T>.Item
    let isSelected: Bool
    let style: GlassSegmented<T>.VisualStyle
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(item.label, systemImage: item.image)
                .labelStyle(.titleAndIcon)
                .font(style == .emphasized ? .system(size: 14, weight: .semibold) : .subheadline)
                .padding(.horizontal, style == .emphasized ? 12 : 9)
                .padding(.vertical, style == .emphasized ? 7 : 6)
                .frame(maxWidth: .infinity)
                .foregroundStyle(foregroundColor)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(selectedFill)
                            .overlay(
                                Capsule()
                                    .strokeBorder(selectedBorder, lineWidth: style == .emphasized ? 0.8 : 0.5)
                            )
                            .shadow(color: shadowColor, radius: style == .emphasized ? 8 : 6, y: 1)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(item.help)
    }

    private var foregroundColor: Color {
        if isSelected {
            return style == .emphasized ? .accentColor : .primary
        }
        return colorScheme == .dark ? Color.white.opacity(0.72) : .secondary
    }

    private var selectedFill: Color {
        switch style {
        case .standard:
            colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.94)
        case .emphasized:
            colorScheme == .dark ? Color.white.opacity(0.10) : Color.white
        }
    }

    private var selectedBorder: Color {
        switch style {
        case .standard:
            colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
        case .emphasized:
            Color.accentColor.opacity(0.35)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .standard:
            Color.black.opacity(0.05)
        case .emphasized:
            Color.accentColor.opacity(0.10)
        }
    }
}
