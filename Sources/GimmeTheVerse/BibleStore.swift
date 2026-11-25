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

/// Die Bibel (Schlachter 1951), vorberechnete Vers-Embeddings und der kuratierte Lebenslagen-Index.
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

    init() throws {
        books = try JSONDecoder().decode([String].self, from: Data(contentsOf: Self.resource("books.json")))

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.resource("verses.json"))) as! [[Any]]
        verses = raw.map { Verse(book: $0[0] as! Int, chapter: $0[1] as! Int, verse: $0[2] as! Int, text: $0[3] as! String) }

        struct RawTheme: Decodable { let name: String; let passages: [[Int]] }
        themes = try JSONDecoder().decode([RawTheme].self, from: Data(contentsOf: Self.resource("themes.json")))
            .map { Theme(name: $0.name, passages: $0.passages.map { Passage($0[0], $0[1]) }) }

        let data = try Data(contentsOf: Self.resource("embeddings.f16"))
        precondition(data.count == verses.count * Self.dim * 2, "embeddings.f16 passt nicht zu verses.json")
        vectors = data.withUnsafeBytes { $0.bindMemory(to: Float16.self).map(Float.init) }

        let priorData = try Data(contentsOf: Self.resource("prior.f32"))
        precondition(priorData.count == verses.count * 4, "prior.f32 passt nicht zu verses.json")
        prior = priorData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Sucht Ressourcen im App-Bundle, beim Entwickeln (`swift run`) im Repo-Ordner.
    static func resource(_ name: String) -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) { return url }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent("Resources").appendingPathComponent(name)
    }

    // MARK: - Text

    func reference(_ p: Passage) -> String {
        let a = verses[p.start], b = verses[p.end]
        let base = "\(books[a.book]) \(a.chapter),\(a.verse)"
        return p.start == p.end ? base : "\(base)–\(b.verse)"
    }

    func text(_ p: Passage) -> String {
        p.indices.map { verses[$0].text }.joined(separator: " ")
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

    /// Kandidaten: zuerst die Stellen der gewählten Lebenslagen, dann semantische Treffer, ohne Dubletten.
    func pool(themes names: [String], semantic: [Int], limit: Int = 45) -> [Passage] {
        var out: [Passage] = []
        var covered = Set<Int>()
        for name in names {
            guard let theme = themes.first(where: { $0.name == name }) else { continue }
            for p in theme.passages where !covered.contains(p.start) {
                out.append(p)
                covered.formUnion(p.indices)
            }
        }
        for i in semantic where out.count < limit && !covered.contains(i) {
            out.append(Passage(i))
            covered.insert(i)
        }
        return Array(out.prefix(limit))
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
