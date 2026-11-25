import AppKit
import SwiftUI

/// Editorial / Papier: warmes Off-White, Tinte statt Schwarz, ein gedämpftes Ochsenblut als einziger Akzent.
enum Theme {
    static let paper = dynamic(light: 0xF7F3EC, dark: 0x1C1A17)
    static let paperDeep = dynamic(light: 0xEEE8DD, dark: 0x161411)
    static let surface = dynamic(light: 0xFCFAF6, dark: 0x24211D)
    static let ink = dynamic(light: 0x29241F, dark: 0xEDE6DA)
    static let inkSoft = dynamic(light: 0x71675C, dark: 0xA69B8C)
    static let inkFaint = dynamic(light: 0xA39685, dark: 0x766C60)
    static let rule = dynamic(light: 0xDED4C5, dark: 0x3A332B)
    static let accent = dynamic(light: 0x914633, dark: 0xDE9B7E)
    static let accentSoft = dynamic(light: 0xEFE0D5, dark: 0x392821)
    static let onAccent = dynamic(light: 0xFFFDFC, dark: 0x241813)
    static let notice = dynamic(light: 0xF1E2D3, dark: 0x2E241E)
    /// Chat: eigene Nachrichten leicht ochsenblut-getönt, Antworten im Ton der Seitenleiste.
    static let bubbleMine = dynamic(light: 0xEBDCCD, dark: 0x3A2B24)
    static let bubbleTheirs = dynamic(light: 0xECE5D7, dark: 0x26231F)

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

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.inkFaint)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isEnabled ? Theme.accent : Theme.rule)
            )
            .shadow(color: .black.opacity(isEnabled ? 0.1 : 0), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}

struct SuggestionChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surface.opacity(0.75), in: Capsule())
            .overlay(Capsule().stroke(Theme.rule, lineWidth: 1))
            .foregroundStyle(configuration.isPressed ? Theme.accent : Theme.inkSoft)
            .contentShape(Capsule())
    }
}

struct IconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? Theme.accent : Theme.inkSoft)
            .frame(width: 28, height: 28)
            .background(Circle().fill(active ? Theme.accentSoft : .clear))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct PaperBackground: View {
    var body: some View {
        Theme.paper
            .overlay {
                RadialGradient(
                    colors: [Theme.accent.opacity(0.055), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 560
                )
            }
    }
}

struct BrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.accent)
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "book.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.onAccent)
            }
            .shadow(color: Theme.accent.opacity(0.18), radius: 8, y: 3)
    }
}
