import SwiftUI

struct AdaptiveChromeSurface: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency, active {
            content.glassEffect(.regular.tint(.accentColor.opacity(0.16)).interactive(!reduceMotion),
                                in: .rect(cornerRadius: 8))
        } else {
            content.background(active ? Color.accentColor.opacity(0.14) : Color.clear,
                               in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

extension View {
    func adaptiveChromeSurface(active: Bool = false) -> some View {
        modifier(AdaptiveChromeSurface(active: active))
    }
}

struct AdaptiveGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content() }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func adaptiveScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .horizontal)
        } else {
            self
        }
    }
}
