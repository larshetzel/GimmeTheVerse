import SwiftUI

struct ComposeView: View {
    @Environment(Engine.self) private var engine
    @Binding var route: Route
    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSubmit: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
    private let suggestions = ["Angst", "Trauer", "Dankbarkeit", "Entscheidung"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rubric(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Spacer()
                Label("Lokal & privat", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.bottom, 42)

            Text("Was bewegt dich gerade?")
                .font(Theme.serif(38, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)

            Text("Ein ehrlicher Satz genügt. Du musst nichts schön formulieren.")
                .font(Theme.serif(16))
                .foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 24)

            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { begin(with: suggestion) }
                        .buttonStyle(SuggestionChipStyle())
                }
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Schreib, was dir auf dem Herzen liegt …")
                            .font(Theme.serif(19))
                            .foregroundStyle(Theme.inkFaint)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .focused($focused)
                        .padding(.leading, -5)
                }
                .frame(minHeight: 150, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Rectangle()
                    .fill(Theme.rule.opacity(0.8))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                HStack {
                    Label("Zum Senden", systemImage: "command")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                    Text("↩")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            Text("Verse finden")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Theme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(focused ? Theme.accent.opacity(0.45) : Theme.rule, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 20, y: 8)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                Text("Deine Worte bleiben auf diesem Mac – ohne Cloud und ohne Konto.")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkFaint)
            .padding(.top, 14)
        }
        .padding(.horizontal, 48)
        .padding(.top, 48)
        .padding(.bottom, 30)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
    }

    private func begin(with suggestion: String) {
        switch suggestion {
        case "Angst": text = "Ich habe gerade Angst vor "
        case "Trauer": text = "Ich trauere um "
        case "Dankbarkeit": text = "Heute bin ich dankbar für "
        case "Entscheidung": text = "Ich stehe vor einer Entscheidung: "
        default: break
        }
        focused = true
    }

    private func submit() {
        guard canSubmit else { return }
        let id = engine.ask(text)
        text = ""
        route = .entry(id)
    }
}
