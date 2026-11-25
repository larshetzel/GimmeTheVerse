import AppKit
import SwiftUI

struct EntryView: View {
    @Environment(Engine.self) private var engine
    @Environment(Journal.self) private var journal
    let id: UUID
    var onDelete: () -> Void = {}
    @State private var confirmDelete = false

    var body: some View {
        if let entry = journal.entry(id) {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(entry)

                    if entry.crisis {
                        CrisisNotice().padding(.bottom, 28)
                    }

                    if entry.passages.isEmpty {
                        if entry.isWorking { Working(status: entry.status) }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(entry.passages, id: \.self) { VerseView(passage: $0) }
                        }
                        .transition(.opacity)
                        comfort(entry)
                        if entry.status == .done {
                            ChatSection(entry: entry)
                        }
                    }

                    if entry.status == .failed {
                        failure(entry)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 48)
                .padding(.bottom, 56)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.35), value: entry.passages)
                Color.clear.frame(height: 1).id(Self.bottom)
            }
            // Während eine Antwort entsteht, unten mitlaufen
            .onChange(of: entry.messages.last?.content) {
                guard engine.chatting.contains(id) else { return }
                withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(Self.bottom, anchor: .bottom) }
            }
            .onChange(of: entry.messages.count) {
                withAnimation(.easeOut(duration: 0.25)) { scroller.scrollTo(Self.bottom, anchor: .bottom) }
            }
            }
        }
    }

    private static let bottom = "entry-bottom"

    private func header(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rubric(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                Spacer()
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle())
                    .help("Eintrag löschen")
                    .disabled(entry.isWorking)
                    .confirmationDialog("Diesen Eintrag löschen?", isPresented: $confirmDelete) {
                        Button("Löschen", role: .destructive, action: onDelete)
                    }
            }
            .padding(.bottom, 14)

            Text(entry.theme.isEmpty ? " " : entry.theme)
                .font(Theme.serif(36, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                Text(entry.text)
                    .font(Theme.serif(15))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 28)

            HStack(spacing: 8) {
                Image(systemName: "book")
                    .font(.system(size: 11, weight: .semibold))
                Rubric("Verse für dich", color: Theme.accent)
            }
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func comfort(_ entry: Entry) -> some View {
        if entry.status == .writing || !entry.zuspruch.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Rubric("Ein Zuspruch für dich", color: Theme.accent)
                }
                if entry.zuspruch.isEmpty {
                    Working(status: .writing)
                } else {
                    Text(entry.zuspruch)
                        .font(Theme.serif(18))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft.opacity(0.52), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
            }
            .padding(.top, 28)
        }
    }

    private func failure(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rubric("Das hat nicht geklappt", color: Theme.accent)
            Text(entry.error ?? "Unbekannter Fehler.")
                .font(Theme.serif(15))
                .foregroundStyle(Theme.inkSoft)
                .textSelection(.enabled)
            Button("Nochmal versuchen") { engine.retry(entry.id) }
                .buttonStyle(InkButtonStyle())
        }
        .padding(.top, 30)
    }
}

// MARK: - Vers

struct VerseView: View {
    @Environment(Engine.self) private var engine
    @Environment(Journal.self) private var journal
    let passage: Passage
    var size: CGFloat = 20
    var card = true
    @State private var hovering = false
    @State private var showContext = false

    private var bible: BibleStore { engine.bible }

    var body: some View {
        let favorite = journal.isFavorite(passage)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Rubric(bible.reference(passage), color: Theme.accent)
                Spacer()
                HStack(spacing: 0) {
                    Button { showContext.toggle() } label: {
                        Image(systemName: showContext ? "text.badge.minus" : "text.badge.plus")
                    }
                    .help(showContext ? "Zusammenhang ausblenden" : "Zusammenhang zeigen")
                    Button(action: copy) { Image(systemName: "doc.on.doc") }
                        .help("Kopieren")
                    Button { journal.toggleFavorite(passage) } label: {
                        Image(systemName: favorite ? "heart.fill" : "heart")
                    }
                    .buttonStyle(IconButtonStyle(active: favorite))
                    .help(favorite ? "Aus Lieblingsversen entfernen" : "Zu Lieblingsversen")
                }
                .buttonStyle(IconButtonStyle())
                .opacity(hovering || favorite || showContext ? 1 : 0.6)
            }

            if showContext {
                contextText
            } else {
                Text(bible.text(passage))
                    .font(Theme.serif(size))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(card ? 20 : 0)
        .background {
            if card {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.surface.opacity(0.88))
                    .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
            }
        }
        .overlay {
            if card {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(hovering ? Theme.accent.opacity(0.22) : Theme.rule.opacity(0.8), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    /// Umgebende Verse in Grau, der gewählte Vers hervorgehoben.
    private var contextText: some View {
        let parts = bible.context(of: passage).map { i -> Text in
            let v = bible.verse(at: i)
            let num = Text("\(v.verse) ").font(.system(size: 11, weight: .semibold)).baselineOffset(5)
            let body = Text(v.text + " ")
            return (num + body).foregroundColor(passage.indices.contains(i) ? Theme.ink : Theme.inkFaint)
        }
        return parts.reduce(Text(""), +)
            .font(Theme.serif(size - 2))
            .lineSpacing(6)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("„\(bible.text(passage))“ – \(bible.reference(passage)) (\(bible.translationName))", forType: .string)
    }
}

// MARK: - Bausteine

struct Working: View {
    let status: Entry.Status
    @State private var phase = false

    private var label: String {
        switch status {
        case .analysing: "Ich höre zu …"
        case .searching: "Ich suche in der Schrift …"
        case .choosing: "Ich wähle passende Verse aus …"
        case .writing: "Einen Moment …"
        default: ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
            Text(label)
                .font(Theme.serif(16))
                .italic()
                .foregroundStyle(Theme.inkSoft)
        }
        .opacity(phase ? 0.55 : 1)
        .animation(.easeInOut(duration: 1.1).repeatForever(), value: phase)
        .onAppear { phase = true }
    }
}

struct CrisisNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rubric("Du musst da nicht allein durch", color: Theme.accent)
            Text("Wenn du gerade daran denkst, dir etwas anzutun: Bitte sprich jetzt mit jemandem. Die Telefonseelsorge ist kostenlos, anonym und rund um die Uhr erreichbar.")
                .font(Theme.serif(15))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Link("0800 111 0 111", destination: URL(string: "tel:08001110111")!)
                Link("0800 111 0 222", destination: URL(string: "tel:08001110222")!)
                Link("online.telefonseelsorge.de", destination: URL(string: "https://online.telefonseelsorge.de")!)
            }
            .font(.system(size: 13, weight: .semibold))
            .tint(Theme.accent)
            Text("Akute Gefahr: Notruf 112")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.notice, in: RoundedRectangle(cornerRadius: 4))
    }
}
