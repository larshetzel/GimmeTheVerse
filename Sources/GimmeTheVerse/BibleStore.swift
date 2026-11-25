import Accelerate
import Foundation

/// Ein Bibelabschnitt: ein Vers oder mehrere aufeinanderfolgende Verse (Indizes in `verses`, inklusive).
struct Passage: Codable, Hashable {
    let start: Int
    let end: Int

    init(_ start: Int, _ end: Int? = nil) {
        self.start = start
        self.end = end ?? start
    }

    var indices: ClosedRange<Int> { start...end }
}

enum BibleTranslation: String, CaseIterable, Identifiable {
    case schlachter
    case hoffnungFuerAlle

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .schlachter: "Schlachter 1951"
        case .hoffnungFuerAlle: "Hoffnung für alle"
        }
    }
}

/// Bibeltexte, vorberechnete Vers-Embeddings und der kuratierte Lebenslagen-Index.
/// Alle Verstexte kommen ausschließlich von hier – das Sprachmodell erzeugt nie Bibeltext.
final class BibleStore: @unchecked Sendable {
    struct Verse {
        let book: Int
        let chapter: Int
        let verse: Int
        let text: String
    }

    struct Theme {
        let name: String
        let passages: [Passage]
    }

    static let dim = 768

    let books: [String]
    let verses: [Verse]
    let themes: [Theme]
    private let vectors: [Float]  // verses.count x dim, L2-normalisiert
    private let prior: [Float]    // je Vers: wie sehr er zuspricht (z-normalisiert)
    private let hfaVerses: [Verse]?
    private let hfaVectors: [Float]?
    private let hfaPrior: [Float]?
    private let lookup: [Int: Int]  // (Buch, Kapitel, Vers) → Index
    private let bookKeys: [String: Int]  // normalisierter Buchname/Alias → Buch

    var availableTranslations: [BibleTranslation] {
        BibleTranslation.allCases.filter { $0 == .schlachter || hfaVerses != nil }
    }

    var translationName: String { activeTranslation.displayName }

    private var activeTranslation: BibleTranslation {
        Defaults.translation == .hoffnungFuerAlle && hfaVerses != nil ? .hoffnungFuerAlle : .schlachter
    }

    init() throws {
        books = try JSONDecoder().decode([String].self, from: Data(contentsOf: Self.resource("books.json")))

        verses = try Self.loadVerses("verses.json")

        struct RawTheme: Decodable { let name: String; let passages: [[Int]] }
        themes = try JSONDecoder().decode([RawTheme].self, from: Data(contentsOf: Self.resource("themes.json")))
            .map { Theme(name: $0.name, passages: $0.passages.map { Passage($0[0], $0[1]) }) }

        let data = try Data(contentsOf: Self.resource("embeddings.f16"))
        precondition(data.count == verses.count * Self.dim * 2, "embeddings.f16 passt nicht zu verses.json")
        vectors = data.withUnsafeBytes { $0.bindMemory(to: Float16.self).map(Float.init) }

        let priorData = try Data(contentsOf: Self.resource("prior.f32"))
        precondition(priorData.count == verses.count * 4, "prior.f32 passt nicht zu verses.json")
        prior = priorData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        var lookup = [Int: Int](minimumCapacity: verses.count)
        for (i, v) in verses.enumerated() { lookup[Self.key(v.book, v.chapter, v.verse)] = i }
        self.lookup = lookup

        var keys = [String: Int]()
        for (i, name) in books.enumerated() { keys[Self.normalize(name)] = i }
        for (alias, name) in Self.aliases {
            if let i = books.firstIndex(of: name) { keys[Self.normalize(alias)] = i }
        }
        bookKeys = keys

        let hfaURL = Self.resource("verses-hfa.json")
        if FileManager.default.fileExists(atPath: hfaURL.path) {
            let translated = try Self.loadVerses("verses-hfa.json")
            precondition(translated.count == verses.count, "verses-hfa.json passt nicht zu verses.json")
            hfaVerses = translated
            let hfaData = try Data(contentsOf: Self.resource("embeddings-hfa.f16"))
            precondition(hfaData.count == verses.count * Self.dim * 2, "embeddings-hfa.f16 passt nicht zu verses.json")
            hfaVectors = hfaData.withUnsafeBytes { $0.bindMemory(to: Float16.self).map(Float.init) }
            let hfaPriorData = try Data(contentsOf: Self.resource("prior-hfa.f32"))
            precondition(hfaPriorData.count == verses.count * 4, "prior-hfa.f32 passt nicht zu verses.json")
            hfaPrior = hfaPriorData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        } else {
            hfaVerses = nil
            hfaVectors = nil
            hfaPrior = nil
        }
    }

    private static func loadVerses(_ name: String) throws -> [Verse] {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: resource(name))) as! [[Any]]
        return raw.map { Verse(book: $0[0] as! Int, chapter: $0[1] as! Int, verse: $0[2] as! Int, text: $0[3] as! String) }
    }

    /// Sucht Ressourcen im App-Bundle, beim Entwickeln (`swift run`) im Repo-Ordner.
    static func resource(_ name: String) -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) { return url }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent("Resources").appendingPathComponent(name)
    }

    // MARK: - Stellenangaben

    private static func key(_ book: Int, _ chapter: Int, _ verse: Int) -> Int { book * 1_000_000 + chapter * 1000 + verse }

    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Gängige Abkürzungen und andere Namen, wie ein Sprachmodell sie schreiben könnte.
    private static let aliases: [String: String] = [
        "Genesis": "1. Mose", "Exodus": "2. Mose", "Levitikus": "3. Mose", "Numeri": "4. Mose", "Deuteronomium": "5. Mose",
        "Psalmen": "Psalm", "Ps": "Psalm", "Spr": "Sprüche", "Sprichwörter": "Sprüche", "Kohelet": "Prediger",
        "Pred": "Prediger", "Hoheslied": "Hohelied", "Jes": "Jesaja", "Jer": "Jeremia", "Klgl": "Klagelieder",
        "Ezechiel": "Hesekiel", "Hes": "Hesekiel", "Mt": "Matthäus", "Matth": "Matthäus", "Mk": "Markus",
        "Lk": "Lukas", "Joh": "Johannes", "Apg": "Apostelgeschichte", "Röm": "Römer", "Gal": "Galater",
        "Eph": "Epheser", "Phil": "Philipper", "Kol": "Kolosser", "Hebr": "Hebräer", "Hiob": "Hiob", "Ijob": "Hiob",
        "Jak": "Jakobus", "Offb": "Offenbarung", "Offenbarung des Johannes": "Offenbarung",
        "1 Kor": "1. Korinther", "2 Kor": "2. Korinther", "1 Petr": "1. Petrus", "2 Petr": "2. Petrus",
        "1 Joh": "1. Johannes", "1 Thess": "1. Thessalonicher", "2 Thess": "2. Thessalonicher",
        "1 Tim": "1. Timotheus", "2 Tim": "2. Timotheus", "1 Sam": "1. Samuel", "2 Sam": "2. Samuel",
        "1 Kön": "1. Könige", "2 Kön": "2. Könige", "1 Chr": "1. Chronik", "2 Chr": "2. Chronik",
        "1 Mo": "1. Mose", "2 Mo": "2. Mose", "3 Mo": "3. Mose", "4 Mo": "4. Mose", "5 Mo": "5. Mose",
    ]

    private static let refPattern = #/^\s*(.+?)\s+(\d+)\s*[,:]\s*(\d+)(?:\s*[-\x{2013}]\s*(\d+))?\s*$/#

    /// "Psalm 23,4", "Phil 4:6-7", "1. Mose 28,15" → Abschnitt; nil, wenn es die Stelle nicht gibt.
    func parseReference(_ ref: String) -> Passage? {
        guard let m = ref.wholeMatch(of: Self.refPattern),
              let book = bookKeys[Self.normalize(String(m.1))],
              let chapter = Int(m.2), let v1 = Int(m.3) else { return nil }
        let v2 = m.4.flatMap { Int($0) } ?? v1
        guard v2 >= v1, v2 - v1 < 8,
              let a = lookup[Self.key(book, chapter, v1)],
              let b = lookup[Self.key(book, chapter, v2)] else { return nil }
        return Passage(a, b)
    }

    // MARK: - Text

    func reference(_ p: Passage) -> String {
        let a = verses[p.start], b = verses[p.end]
        let base = "\(books[a.book]) \(a.chapter),\(a.verse)"
        return p.start == p.end ? base : "\(base)–\(b.verse)"
    }

    func verse(at index: Int) -> Verse {
        activeTranslation == .hoffnungFuerAlle ? hfaVerses![index] : verses[index]
    }

    func text(_ p: Passage) -> String {
        p.indices.map { verse(at: $0).text }.joined(separator: " ")
    }

    /// Die ersten Wörter eines Abschnitts – für kompakte Kandidatenlisten im Prompt (Prefill ist der Engpass).
    func preview(_ p: Passage, words: Int) -> String {
        let all = text(p).split(separator: " ")
        return all.count <= words ? all.joined(separator: " ") : all.prefix(words).joined(separator: " ") + " …"
    }

    /// Umgebende Verse im selben Kapitel.
    func context(of p: Passage, radius: Int = 3) -> ClosedRange<Int> {
        let v = verses[p.start]
        func same(_ i: Int) -> Bool { verses[i].book == v.book && verses[i].chapter == v.chapter }
        var lo = p.start, hi = p.end
        while lo > 0, p.start - lo < radius, same(lo - 1) { lo -= 1 }
        while hi < verses.count - 1, hi - p.end < radius, same(hi + 1) { hi += 1 }
        return lo...hi
    }

    // MARK: - Suche

    /// Reciprocal Rank Fusion über mehrere Anfragen; der Prior schiebt zusprechende Verse leicht nach vorn.
    func semantic(_ queries: [[Float]], k: Int, perQuery: Int = 60, priorWeight: Float = 0.01) -> [Int] {
        let vectors = activeTranslation == .hoffnungFuerAlle ? hfaVectors! : vectors
        let prior = activeTranslation == .hoffnungFuerAlle ? hfaPrior! : prior
        var fused = [Int: Float]()
        var scores = [Float](repeating: 0, count: verses.count)
        for q in queries where q.count == Self.dim {
            var q = q
            var norm: Float = 0
            vDSP_svesq(q, 1, &norm, vDSP_Length(Self.dim))
            var inv = 1 / max(norm.squareRoot(), 1e-9)
            vDSP_vsmul(q, 1, &inv, &q, 1, vDSP_Length(Self.dim))

            vDSP_mmul(vectors, 1, q, 1, &scores, 1, vDSP_Length(verses.count), 1, vDSP_Length(Self.dim))
            var w = priorWeight
            vDSP_vsma(prior, 1, &w, scores, 1, &scores, 1, vDSP_Length(verses.count))

            for (rank, i) in topK(scores, perQuery).enumerated() {
                fused[i, default: 0] += 1 / Float(10 + rank)
            }
        }
        return fused.sorted { $0.value > $1.value }.prefix(k).map(\.key)
    }

    /// Kandidaten: kuratierte Lebenslagen und semantische Treffer zu gleichen Teilen, ohne Dubletten.
    func pool(themes names: [String], semantic: [Int], limit: Int = 45) -> [Passage] {
        let groups = names.compactMap { name in themes.first(where: { $0.name == name })?.passages }
        var curated: [Passage] = []
        var known = Set<Int>()
        var position = 0
        while curated.count < groups.flatMap(\.self).count {
            var added = false
            for group in groups where position < group.count {
                let p = group[position]
                if !known.contains(p.start) {
                    curated.append(p)
                    known.formUnion(p.indices)
                    added = true
                }
            }
            if !added && groups.allSatisfy({ position >= $0.count }) { break }
            position += 1
        }

        var out = Array(curated.prefix(limit / 2))
        var covered = Set(out.flatMap(\.indices))
        for i in semantic where out.count < limit && !covered.contains(i) {
            out.append(Passage(i))
            covered.insert(i)
        }
        for p in curated where out.count < limit && !covered.contains(p.start) {
            out.append(p)
            covered.formUnion(p.indices)
        }
        return out
    }

    private func topK(_ scores: [Float], _ k: Int) -> [Int] {
        var top: [(Int, Float)] = []
        top.reserveCapacity(k + 1)
        var floor = -Float.infinity
        for (i, s) in scores.enumerated() where s > floor || top.count < k {
            let pos = top.firstIndex { $0.1 < s } ?? top.count
            top.insert((i, s), at: pos)
            if top.count > k { top.removeLast() }
            if top.count == k { floor = top[k - 1].1 }
        }
        return top.map(\.0)
    }
}
