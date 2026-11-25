import AppKit
import SwiftUI

@main
struct GimmeTheVerseApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        WindowGroup("GimmeTheVerse", id: "main") {
            Group {
                switch state {
                case let .ready(engine):
                    ContentView()
                        .environment(engine)
                        .environment(engine.journal)
                        .onAppear { if Snapshot.request == nil { engine.warmUp() } }
                case let .failed(message):
                    LoadErrorView(message: message)
                }
            }
            .frame(minWidth: 760, minHeight: 640)
            .background(Theme.paper)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neuer Eintrag") {
                    NotificationCenter.default.post(name: .newEntry, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(before: .sidebar) {
                Button("Seitenleiste ein-/ausblenden") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }

        Settings {
            Group {
                if case let .ready(engine) = state {
                    SettingsView().environment(engine)
                } else {
                    Text("Die Bibeldaten konnten nicht geladen werden.")
                }
            }
            .frame(width: 440)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_: Notification) {
        // Beim Start per `swift run` (ohne .app-Bundle) trotzdem als normale App erscheinen.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let snap = Snapshot.request, case let .ready(engine) = AppState.shared {
            Snapshot.run(engine: engine, dir: snap.dir, text: snap.text, chat: snap.chat)
        }
    }
}

extension Notification.Name {
    static let newEntry = Notification.Name("GimmeTheVerse.newEntry")
    static let toggleSidebar = Notification.Name("GimmeTheVerse.toggleSidebar")
}

enum AppState {
    case ready(Engine)
    case failed(String)

    @MainActor static let shared = load()

    @MainActor static func load() -> AppState {
        do {
            var journal = Journal()
            if Snapshot.request != nil {
                try? FileManager.default.removeItem(at: Snapshot.journalURL)
                journal = Journal(url: Snapshot.journalURL)
            }
            return .ready(Engine(bible: try BibleStore(), journal: journal))
        } catch {
            return .failed("Die Bibeldaten konnten nicht geladen werden.\n\(error.localizedDescription)")
        }
    }
}

struct LoadErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Rubric("Fehler", color: Theme.accent)
            Text(message)
                .font(Theme.serif(16))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
