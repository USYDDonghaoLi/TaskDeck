import SwiftUI

enum DeckTheme {
    static let void = Color(red: 0.018, green: 0.027, blue: 0.047)
    static let panel = Color(red: 0.035, green: 0.053, blue: 0.082)
    static let panelRaised = Color(red: 0.055, green: 0.078, blue: 0.114)
    static let cyan = Color(red: 0.0, green: 0.94, blue: 0.82)
    static let lime = Color(red: 0.68, green: 1.0, blue: 0.28)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let warning = Color(red: 1.0, green: 0.55, blue: 0.28)
    static let text = Color(red: 0.88, green: 0.94, blue: 1.0)
    static let muted = Color(red: 0.43, green: 0.52, blue: 0.63)
    static let border = Color.white.opacity(0.08)
}

struct DeckPanel: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DeckTheme.panel.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DeckTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func deckPanel(radius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(DeckPanel(radius: radius, padding: padding))
    }
}

struct GridBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var path = Path()
                let step: CGFloat = 28
                stride(from: CGFloat.zero, through: size.width, by: step).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat.zero, through: size.height, by: step).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(DeckTheme.cyan.opacity(0.026)), lineWidth: 0.5)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }
}
