import AppKit
import SwiftUI

/// Entwickler-Modus: `GimmeTheVerse --snapshot <ordner> "<anliegen>"`
/// Schickt das Anliegen durch die echte Pipeline (mit temporärem Journal) und speichert
/// die Oberfläche offscreen als PNG in Hell und Dunkel – ohne Bildschirmaufnahme-Rechte.
enum Snapshot {
    /// `--snapshot <ordner> "<anliegen>" ["<chat-nachricht>"]`
    static var request: (dir: URL, text: String, chat: String?)? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 else { return nil }
        return (URL(fileURLWithPath: args[i + 1]), args[i + 2], args.count > i + 3 ? args[i + 3] : nil)
    }

    static var journalURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GimmeTheVerse-snapshot.json")
    }

    @MainActor
    static func run(engine: Engine, dir: URL, text: String, chat: String? = nil) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func render(_ name: String, route: Route, dark: Bool, height: CGFloat = 900) {
            let size = NSSize(width: 900, height: height)
            let root = ContentView(route: route)
                .environment(engine)
                .environment(engine.journal)
                .frame(width: size.width, height: size.height)
                .background(Theme.paper)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))  // Layout und Animationen abwarten
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            print("→ \(dir.appendingPathComponent(name).path)")
        }

        render("compose-light.png", route: .compose, dark: false)
        let id = engine.ask(text)
        Task { @MainActor in
            while engine.journal.entry(id)?.isWorking == true {
                try? await Task.sleep(for: .milliseconds(300))
            }
            if let e = engine.journal.entry(id) {
                print("Status: \(e.status.rawValue) \(e.error ?? "")")
                print("Titel: \(e.theme)")
                for p in e.passages { print("  \(engine.bible.reference(p))") }
                print("Zuspruch: \(e.zuspruch)")
            }
            render("entry-light.png", route: .entry(id), dark: false)
            render("entry-dark.png", route: .entry(id), dark: true)

            if let chat {
                engine.send(chat, to: id)
                while engine.chatting.contains(id) {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                for m in engine.journal.entry(id)?.messages ?? [] {
                    print("[\(m.role.rawValue)] \(m.content)")
                    for p in m.passages { print("   → \(engine.bible.reference(p)): \(engine.bible.text(p))") }
                }
                // hoch genug, dass Zuspruch und Gespräch ganz zu sehen sind
                render("chat-light.png", route: .entry(id), dark: false, height: 2600)
                render("chat-dark.png", route: .entry(id), dark: true, height: 2600)
            }
            exit(0)
        }
    }
}
