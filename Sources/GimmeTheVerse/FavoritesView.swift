import SwiftUI

struct FavoritesView: View {
    @Environment(Journal.self) private var journal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rubric("Deine Sammlung").padding(.bottom, 18)
                Text("Lieblingsverse")
                    .font(Theme.serif(36, .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.bottom, 10)
                Text("Worte, zu denen du zurückkehren möchtest.")
                    .font(Theme.serif(16))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.bottom, 32)

                if journal.favorites.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "heart")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 54, height: 54)
                            .background(Theme.accentSoft, in: Circle())
                        Text("Deine Sammlung beginnt hier")
                            .font(Theme.serif(21, .medium))
                            .foregroundStyle(Theme.ink)
                        Text("Tippe bei einem Vers auf das Herz.\nSo bewahrst du ihn für später auf.")
                            .font(Theme.serif(15))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 46)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(journal.favorites, id: \.self) { VerseView(passage: $0) }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 48)
            .padding(.bottom, 56)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsView: View {
    @AppStorage(Defaults.modelKey) private var model = Defaults.model
    @State private var models: [String] = []
    @State private var status = "Prüfe Ollama …"

    var body: some View {
        Form {
            Picker("Sprachmodell", selection: $model) {
                ForEach(Array(Set(models + [model])).sorted(), id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("Suche", value: Ollama.embedModel)
            LabeledContent("Übersetzung", value: "Schlachter 1951")
            LabeledContent("Ollama", value: status)
        }
        .formStyle(.grouped)
        .task {
            do {
                models = try await Ollama().chatModels()
                status = "läuft"
            } catch {
                status = "nicht erreichbar"
            }
        }
    }
}
