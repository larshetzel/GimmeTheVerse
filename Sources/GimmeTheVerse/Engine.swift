import Foundation
import Observation

enum Defaults {
    static let modelKey = "chatModel"
    static let model = "gemma4:12b"
    static let translationKey = "bibleTranslation"
    static var chatModel: String { UserDefaults.standard.string(forKey: modelKey) ?? model }
    static var translation: BibleTranslation {
        BibleTranslation(rawValue: UserDefaults.standard.string(forKey: translationKey) ?? "") ?? .schlachter
    }
}

/// Ablauf:
/// 1. Analyse (LLM): passende Lebenslagen, Suchsätze, Überschrift, Krisen-Hinweis
/// 2. Kandidaten: kuratierte Stellen der Lebenslagen + semantische Vers-Suche
/// 3. Auswahl (LLM): die 4 passendsten Abschnitte – nur per Nummer, nie als Text
/// 4. Zuspruch (LLM, gestreamt)
@MainActor @Observable
final class Engine {
    let bible: BibleStore
    let journal: Journal
    private let ollama = Ollama()
    /// Einträge, in denen gerade eine Chat-Antwort entsteht.
    private(set) var chatting = Set<UUID>()

    init(bible: BibleStore, journal: Journal) {
        self.bible = bible
        self.journal = journal
    }

    func warmUp() {
        Task.detached { await Ollama().warmUp(model: Defaults.chatModel) }
    }

    @discardableResult
    func ask(_ text: String) -> UUID {
        let entry = Entry(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        journal.insert(entry)
        Task { await run(entry.id, text: entry.text) }
        return entry.id
    }

    func retry(_ id: UUID) {
        guard let e = journal.entry(id) else { return }
        journal.update(id) { $0 = Entry(id: e.id, date: e.date, text: e.text) }
        Task { await run(id, text: e.text) }
    }

    // MARK: - Gespräch

    func send(_ text: String, to id: UUID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatting.contains(id), let entry = journal.entry(id), entry.status == .done else { return }
        let reply = ChatMessage(role: .assistant, content: "")
        journal.update(id, save: true) {
            $0.chat = $0.messages + [ChatMessage(role: .user, content: text), reply]
            if Crisis.detect(text) { $0.crisis = true }
        }
        chatting.insert(id)
        Task { await runChat(id, replyID: reply.id) }
    }

    private func runChat(_ id: UUID, replyID: UUID) async {
        defer { chatting.remove(id) }
        guard let entry = journal.entry(id) else { return }

        // Kontext: Anliegen, Verse und Zuspruch wie im ersten Durchlauf, danach das bisherige Gespräch.
        var messages: [[String: String]] = [
            ["role": "system", "content": Prompts.chatSystem(crisis: entry.crisis)],
            ["role": "user", "content": Prompts.comfortUser(text: entry.text, passages: entry.passages.map {
                "\(bible.reference($0)): \(bible.text($0))"
            })],
            ["role": "assistant", "content": entry.zuspruch],
        ]
        let history = entry.messages.filter { $0.id != replyID && !$0.failed }.suffix(16)
        messages += history.map { ["role": $0.role.rawValue, "content": $0.content] }

        func updateReply(save: Bool = false, _ change: @escaping (inout ChatMessage) -> Void) {
            journal.update(id, save: save) { e in
                guard let i = e.chat?.firstIndex(where: { $0.id == replyID }) else { return }
                change(&e.chat![i])
            }
        }

        do {
            for try await chunk in ollama.chatStream(model: Defaults.chatModel, messages: messages) {
                updateReply { $0.content += chunk }
            }
            let content = journal.entry(id)?.messages.first { $0.id == replyID }?.content ?? ""
            let passages = ChatText.references(in: content).compactMap(bible.parseReference)
            updateReply(save: true) {
                $0.content = $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
                $0.passages = Array(NSOrderedSet(array: passages).array as! [Passage]).prefix(3).map { $0 }
            }
        } catch {
            updateReply(save: true) {
                $0.failed = true
                $0.content = error.localizedDescription
            }
        }
    }

    // MARK: - Erster Durchlauf

    private func run(_ id: UUID, text: String) async {
        let model = Defaults.chatModel
        do {
            // 1. Analyse
            let analysis = try await ollama.chatJSON(
                Analysis.self, model: model,
                system: Prompts.analyseSystem(themes: bible.themes.map(\.name)),
                user: text, schema: Analysis.schema, example: Analysis.example
            )
            let crisis = analysis.crisis || Crisis.detect(text)
            journal.update(id) {
                $0.theme = analysis.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                $0.crisis = crisis
                $0.status = .searching
            }

            // 2. Kandidaten
            let queries = try await ollama.embed(([text] + analysis.queries.prefix(4)).map { "task: search result | query: \($0)" })
            let semantic = bible.semantic(queries, k: 45)
            let candidates = bible.pool(themes: Array(analysis.themes.prefix(3)), semantic: semantic, limit: 32)
            journal.update(id) { $0.status = .choosing }

            // 3. Auswahl
            let pick = try await ollama.chatJSON(
                Pick.self, model: model,
                system: Prompts.selectSystem,
                user: Prompts.selectUser(text: text, candidates: candidates.enumerated().map {
                    "[\($0.offset + 1)] \(bible.reference($0.element)): \(bible.preview($0.element, words: 28))"
                }),
                schema: Pick.schema, example: Pick.example
            )
            var chosen: [Passage] = []
            for n in pick.numbers where (1...candidates.count).contains(n) {
                let p = candidates[n - 1]
                if !chosen.contains(p) { chosen.append(p) }
            }
            if chosen.isEmpty { chosen = Array(candidates.prefix(4)) }
            chosen = Array(chosen.prefix(5))
            journal.update(id) {
                $0.passages = chosen
                $0.status = .writing
            }

            // 4. Zuspruch
            let stream = ollama.chatStream(
                model: model,
                system: Prompts.comfortSystem(crisis: crisis),
                user: Prompts.comfortUser(text: text, passages: chosen.map { "\(bible.reference($0)): \(bible.text($0))" })
            )
            for try await chunk in stream {
                journal.update(id) { $0.zuspruch += chunk }
            }
            journal.update(id, save: true) {
                $0.zuspruch = $0.zuspruch.trimmingCharacters(in: .whitespacesAndNewlines)
                $0.status = .done
            }
        } catch {
            journal.update(id, save: true) {
                $0.status = .failed
                $0.error = error.localizedDescription
            }
        }
    }
}

struct Analysis: Decodable {
    let themes: [String]
    let queries: [String]
    let title: String
    let crisis: Bool

    static let example = #"{"themes": ["Angst und Sorgen", "Nicht schlafen können"], "queries": ["…", "…", "…"], "title": "Angst vor morgen", "crisis": false}"#

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "themes": ["type": "array", "items": ["type": "string"]],
            "queries": ["type": "array", "items": ["type": "string"]],
            "title": ["type": "string"],
            "crisis": ["type": "boolean"],
        ],
        "required": ["themes", "queries", "title", "crisis"],
    ]
}

struct Pick: Decodable {
    let numbers: [Int]

    static let example = #"{"numbers": [7, 2, 19, 11]}"#

    static let schema: [String: Any] = [
        "type": "object",
        "properties": ["numbers": ["type": "array", "items": ["type": "integer"]]],
        "required": ["numbers"],
    ]
}

/// Sicherheitsnetz zusätzlich zur Einschätzung des Modells.
enum Crisis {
    private static let patterns = [
        "suizid", "selbstmord", "umbringen", "mich töten", "mir das leben nehmen", "nicht mehr leben",
        "will sterben", "sterben will", "möchte sterben", "nicht mehr aufwachen", "ritzen", "mich verletzen",
        "allem ein ende", "ein ende machen", "keinen sinn mehr zu leben", "lebensmüde",
    ]

    static func detect(_ text: String) -> Bool {
        let t = text.lowercased()
        return patterns.contains { t.contains($0) }
    }
}

enum Prompts {
    static func analyseSystem(themes: [String]) -> String {
        """
        Ein Mensch schreibt, was ihn bewegt. Ordne sein Anliegen ein.

        "themes": 1 bis 3 Lebenslagen aus dieser Liste, die am besten passen (exakt wie geschrieben, die wichtigste zuerst):
        \(themes.map { "- \($0)" }.joined(separator: "\n"))

        "queries": 3 kurze Suchsätze (je 5 bis 12 Wörter) in schlichter, biblisch geprägter Sprache, die beschreiben, was ein Bibelvers aussagen müsste, der diesem Menschen jetzt guttut – konkret zu seinem Anliegen.
        "title": eine ruhige Überschrift aus 2 bis 4 Wörtern, die das Anliegen behutsam benennt.
        "crisis": true nur bei Hinweisen auf Suizidgedanken, Selbstverletzung oder akute Gefahr.
        """
    }

    static let selectSystem = """
    Du hilfst dabei, zu dem Anliegen eines Menschen passende Bibelstellen auszuwählen.
    Du bekommst das Anliegen und eine nummerierte Liste von Kandidaten in der eingestellten Bibelübersetzung.

    Wähle die 4 Stellen aus, die diesem Menschen in seiner konkreten Lage am meisten Trost, Hoffnung, Kraft oder Orientierung geben – oder, wenn er sich freut, die seine Freude und seinen Dank aufnehmen.
    - Bevorzuge Stellen, die für sich allein verständlich sind und den Leser direkt ansprechen oder eine Zusage Gottes enthalten.
    - Meide Stellen, die ohne Zusammenhang missverständlich, hart oder belehrend wirken.
    - Wähle möglichst verschiedene Blickwinkel, nicht viermal dieselbe Aussage.
    - Ordne sie so, dass die passendste Stelle zuerst kommt.

    "numbers": die Nummern der gewählten Stellen.
    """

    static func selectUser(text: String, candidates: [String]) -> String {
        "Anliegen:\n\(text)\n\nKandidaten:\n" + candidates.joined(separator: "\n")
    }

    static func comfortSystem(crisis: Bool) -> String {
        var s = """
        Du bist ein einfühlsamer, erfahrener Seelsorger. Ein Mensch hat dir anvertraut, was ihn gerade bewegt, und es wurden Bibelstellen für ihn ausgewählt.

        Schreib ihm einen kurzen Zuspruch auf Deutsch, in der Du-Form:
        - 3 bis 5 Sätze in einem einzigen Absatz, in heutiger, schlichter Sprache. Kurz ist besser als lang.
        - Nimm ernst, was er fühlt, und beziehe dich konkret auf seine Lage. Wenn er sich freut, freu dich mit ihm, statt zu trösten.
        - Greif ein oder zwei der Stellen auf und nenne sie mit Stellenangabe (z. B. "in Psalm 23,4"). Zitiere höchstens wenige Worte daraus, wortgetreu.
        - Nenne ausschließlich Stellenangaben aus der obigen Auswahl und führe keine neuen Bibelstellen ein.
        - Der erste Satz beginnt nicht mit "Es ist", "Ich verstehe" oder "Ich kann verstehen" – fang direkt bei ihm und seiner Lage an.
        - Keine Floskeln, keine Predigt, keine Ratschläge von oben herab, keine Diagnosen.
        - Keine Überschrift, keine Anrede wie "Lieber …", keine Aufzählung, keine Emojis, kein Gruß am Ende.
        """
        if crisis {
            s += """

            WICHTIG: Der Mensch könnte in akuter Not sein. Sag ihm behutsam und deutlich, dass er damit nicht allein bleiben muss und sich jetzt Hilfe holen darf: bei der Telefonseelsorge (0800 111 0 111, kostenlos, rund um die Uhr) oder bei einem Menschen, dem er vertraut. Bei akuter Gefahr: Notruf 112.
            """
        }
        return s
    }

    static func chatSystem(crisis: Bool) -> String {
        var s = """
        Du bist ein einfühlsamer, erfahrener Seelsorger. Ein Mensch hat dir anvertraut, was ihn bewegt; er hat dazu Bibelstellen in der eingestellten Übersetzung und einen ersten Zuspruch bekommen. Jetzt führt ihr ein Gespräch.

        So antwortest du:
        - Auf Deutsch, in der Du-Form, warm, ehrlich und in heutiger, schlichter Sprache.
        - Kurz: meist 2 bis 5 Sätze, ein Absatz. Höchstens eine Rückfrage pro Antwort.
        - Geh auf das ein, was er gerade schreibt. Nimm Gefühle ernst. Keine Predigt, keine Floskeln, keine Ratschläge von oben herab, keine Diagnosen.
        - Beginne nicht mit "Es ist (völlig/absolut) verständlich", "Ich verstehe" oder "Ich kann verstehen" – fang direkt bei dem an, was er geschrieben hat.
        - Bei medizinischen, rechtlichen oder seelischen Krisen ermutige behutsam, sich auch Hilfe bei Menschen oder Fachleuten zu holen.
        - Keine Überschriften, keine Aufzählungen, keine Emojis.

        Bibelstellen:
        - Wenn ein weiterer Vers ihm jetzt wirklich hilft, nenne höchstens zwei Stellen pro Antwort, jeweils in doppelten eckigen Klammern, z. B. [[Psalm 23,4]] oder [[Philipper 4,6-7]]. Die App zeigt den Verstext dann wortgetreu an.
        - Zitiere den Verstext dieser neuen Stellen nicht selbst und erfinde keine Stellen. Psalmen nach deutscher Zählung (z. B. Psalm 34,19).
        - Auf Stellen, die schon gezeigt wurden, kannst du dich ohne Klammern beziehen.
        """
        if crisis {
            s += """

            WICHTIG: Der Mensch könnte in akuter Not sein. Sag ihm behutsam und deutlich, dass er damit nicht allein bleiben muss und sich jetzt Hilfe holen darf: bei der Telefonseelsorge (0800 111 0 111, kostenlos, rund um die Uhr) oder bei einem Menschen, dem er vertraut. Bei akuter Gefahr: Notruf 112.
            """
        }
        return s
    }

    static func comfortUser(text: String, passages: [String]) -> String {
        "Was mich bewegt:\n\(text)\n\nAusgewählte Bibelstellen:\n" + passages.map { "- \($0)" }.joined(separator: "\n")
    }
}

/// [[Stelle]]-Marker in Chat-Antworten.
enum ChatText {
    private static let marker = #/\[\[([^\[\]]{3,40})\]\]/#

    static func references(in text: String) -> [String] {
        text.matches(of: marker).map { String($0.1) }
    }

    /// Anzeigetext: aufgelöste Marker werden zur sauberen Stellenangabe, nicht auflösbare fallen weg.
    static func display(_ text: String, bible: BibleStore) -> String {
        var out = text.replacing(marker) { m in
            bible.parseReference(String(m.1)).map(bible.reference) ?? ""
        }
        // Halbe Marker während des Streamens ausblenden
        if let open = out.range(of: "[[", options: .backwards), !out[open.upperBound...].contains("]]") {
            out = String(out[..<open.lowerBound])
        }
        for (a, b) in [("  ", " "), (" .", "."), (" ,", ","), ("()", ""), ("( )", "")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
