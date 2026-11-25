import SwiftUI

struct FavoritesView: View {
    @Environment(Journal.self) private var journal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rubric("Gesammelt").padding(.bottom, 18)
                Text("Lieblingsverse")
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.ink)
                    .padding(.bottom, 30)
                Rectangle().fill(Theme.rule).frame(height: 1).padding(.bottom, 30)

                if journal.favorites.isEmpty {
                    Text("Noch keine. Fahr mit der Maus über einen Vers und tippe auf das Herz, um ihn hier zu sammeln.")
                        .font(Theme.serif(16))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    VStack(alignment: .leading, spacing: 30) {
                        ForEach(journal.favorites, id: \.self) { VerseView(passage: $0) }
                    }
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, 44)
            .padding(.bottom, 56)
            .frame(maxWidth: 720, alignment: .leading)
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
