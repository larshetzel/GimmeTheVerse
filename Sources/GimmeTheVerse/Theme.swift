import AppKit
import SwiftUI

/// Editorial / Papier: warmes Off-White, Tinte statt Schwarz, ein gedämpftes Ochsenblut als einziger Akzent.
enum Theme {
    static let paper = dynamic(light: 0xF6F1E7, dark: 0x1D1B18)
    static let paperDeep = dynamic(light: 0xEDE6D8, dark: 0x171512)
    static let ink = dynamic(light: 0x2A2521, dark: 0xE9E2D5)
    static let inkSoft = dynamic(light: 0x71675C, dark: 0x9C9284)
    static let inkFaint = dynamic(light: 0xA89C8C, dark: 0x6B6358)
    static let rule = dynamic(light: 0xDCD2C0, dark: 0x37312A)
    static let accent = dynamic(light: 0x8B3A2B, dark: 0xD69276)
    static let notice = dynamic(light: 0xF1E2D3, dark: 0x2E241E)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .semibold).width(.expanded)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Kleine, gesperrte Versalien – wie Rubriken in einem Buch.
struct Rubric: View {
    let text: String
    var color: Color = Theme.inkSoft

    init(_ text: String, color: Color = Theme.inkSoft) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label())
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// Text-Button mit Pfeil, ohne Kapsel oder Verlauf.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(16, .medium))
            .foregroundStyle(isEnabled ? Theme.accent : Theme.inkFaint)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(isEnabled ? Theme.accent : Theme.inkFaint).frame(height: 1)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? Theme.accent : Theme.inkFaint)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
