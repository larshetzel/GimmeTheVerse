import SwiftUI

/// Gespräch unter dem Zuspruch: eigene Nachrichten rechts, Antworten links.
/// Stellen, die das Modell als [[…]] nennt, erscheinen wortgetreu als Vers in der Blase.
struct ChatSection: View {
    @Environment(Engine.self) private var engine
    let entry: Entry
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var busy: Bool { engine.chatting.contains(entry.id) }
    private var canSend: Bool { !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.bottom, 18)
            Rubric("Gespräch", color: Theme.accent)

            if entry.messages.isEmpty {
                Text("Möchtest du weiterreden? Schreib, was dich noch beschäftigt.")
                    .font(Theme.serif(15))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
            }

            ForEach(entry.messages) { message in
                ChatBubble(message: message, typing: busy && message.id == entry.messages.last?.id)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            input.padding(.top, 6)
        }
        .padding(.top, 36)
        .animation(.easeOut(duration: 0.25), value: entry.messages.count)
    }

    private var input: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $draft, prompt: Text("Schreib weiter …").foregroundStyle(Theme.inkFaint), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.serif(16))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .padding(.vertical, 3)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(canSend ? Theme.paper : Theme.inkFaint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(canSend ? Theme.accent : Theme.rule))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .help("Senden (↩)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.paper)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(focused ? Theme.inkFaint : Theme.rule, lineWidth: 1))
        )
    }

    private func send() {
        guard canSend else { return }
        engine.send(draft, to: entry.id)
        draft = ""
    }
}

private struct ChatBubble: View {
    @Environment(Engine.self) private var engine
    let message: ChatMessage
    let typing: Bool

    private var mine: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if mine { Spacer(minLength: 90) }
            VStack(alignment: .leading, spacing: 12) {
                if message.content.isEmpty && typing {
                    TypingDots()
                } else {
                    Text(mine ? message.content : ChatText.display(message.content, bible: engine.bible))
                        .font(Theme.serif(16))
                        .italic(message.failed)
                        .foregroundStyle(message.failed ? Theme.inkSoft : Theme.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(message.passages, id: \.self) { passage in
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle().fill(Theme.rule).frame(height: 1)
                        VerseView(passage: passage, size: 17)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: mine ? 16 : 4,
                    bottomTrailingRadius: mine ? 4 : 16,
                    topTrailingRadius: 16
                )
                .fill(mine ? Theme.bubbleMine : Theme.bubbleTheirs)
            )
            if !mine { Spacer(minLength: 90) }
        }
    }
}

private struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.inkSoft)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(.vertical, 6)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}
