import Foundation
import Observation

struct Entry: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case analysing, searching, choosing, writing, done, failed
    }

    var id = UUID()
    var date = Date()
    var text: String
    var theme: String = ""
    var passages: [Passage] = []
    var zuspruch: String = ""
    var crisis = false
    var status: Status = .analysing
    var error: String?

    var isWorking: Bool { [.analysing, .searching, .choosing, .writing].contains(status) }

    var title: String {
        if !theme.isEmpty { return theme }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
    }
}

/// Verlauf und Lieblingsverse, lokal gespeichert in ~/Library/Application Support/GimmeTheVerse.
@MainActor @Observable
final class Journal {
    private(set) var entries: [Entry] = []
    private(set) var favorites: [Passage] = []  // zuletzt markiert zuerst

    private struct Stored: Codable {
        var entries: [Entry]
        var favorites: [Passage]
    }

    private let url: URL

    nonisolated static let defaultURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GimmeTheVerse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.json")
    }()

    init(url: URL = Journal.defaultURL) {
        self.url = url
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder.iso.decode(Stored.self, from: data) else { return }
        entries = stored.entries.map { e in
            var e = e
            if e.isWorking { e.status = .failed; e.error = "Abgebrochen." }
            return e
        }
        favorites = stored.favorites
    }

    func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }

    func insert(_ entry: Entry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(_ id: UUID, save shouldSave: Bool = false, _ change: (inout Entry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
        if shouldSave { save() }
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func isFavorite(_ passage: Passage) -> Bool { favorites.contains(passage) }

    func toggleFavorite(_ passage: Passage) {
        if let i = favorites.firstIndex(of: passage) { favorites.remove(at: i) } else { favorites.insert(passage, at: 0) }
        save()
    }

    func save() {
        let stored = Stored(entries: entries, favorites: favorites)
        if let data = try? JSONEncoder.iso.encode(stored) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
