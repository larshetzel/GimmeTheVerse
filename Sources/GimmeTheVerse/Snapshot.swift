import AppKit
import SwiftUI

/// Entwickler-Modus: `GimmeTheVerse --snapshot <ordner> "<anliegen>"`
/// Schickt das Anliegen durch die echte Pipeline (mit temporärem Journal) und speichert
/// die Oberfläche offscreen als PNG in Hell und Dunkel – ohne Bildschirmaufnahme-Rechte.
enum Snapshot {
    static var request: (dir: URL, text: String)? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 else { return nil }
        return (URL(fileURLWithPath: args[i + 1]), args[i + 2])
    }

    static var journalURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GimmeTheVerse-snapshot.json")
    }

    @MainActor
    static func run(engine: Engine, dir: URL, text: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = NSSize(width: 900, height: 900)

        func render(_ name: String, route: Route, dark: Bool) {
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
            exit(0)
        }
    }
}
