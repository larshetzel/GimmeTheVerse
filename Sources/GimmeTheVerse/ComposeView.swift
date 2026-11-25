import SwiftUI

struct ComposeView: View {
    @Environment(Engine.self) private var engine
    @Binding var route: Route
    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSubmit: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rubric(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .padding(.bottom, 18)

            Text("Was bewegt dich gerade?")
                .font(Theme.serif(30, .regular))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 6)

            Text("Schreib es so auf, wie es dir auf dem Herzen liegt.")
                .font(Theme.serif(15))
                .italic()
                .foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 24)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Sorgen, Ängste, Dankbarkeit, eine Entscheidung …")
                        .font(Theme.serif(19))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 1)
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
            .frame(minHeight: 160, maxHeight: .infinity)

            Rectangle().fill(Theme.rule).frame(height: 1)
                .padding(.bottom, 14)

            HStack {
                Text("⌘ ↩")
                    .font(.system(size: 11, weight: .medium).monospaced())
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Button(action: submit) {
                    HStack(spacing: 6) {
                        Text("Verse finden")
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 44)
        .padding(.bottom, 32)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
    }

    private func submit() {
        guard canSubmit else { return }
        let id = engine.ask(text)
        text = ""
        route = .entry(id)
    }
}
