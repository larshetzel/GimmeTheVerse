import SwiftUI

enum Route: Hashable {
    case compose
    case favorites
    case entry(UUID)
}

/// Eigenes Zwei-Spalten-Layout statt NavigationSplitView: Unter macOS 26 wäre die Seitenleiste
/// ein Liquid-Glass-Panel – hier soll sie aussehen wie der Rand einer Buchseite.
struct ContentView: View {
    @Environment(Journal.self) private var journal
    @State private var route: Route
    @State private var showSidebar = true

    init(route: Route = .compose) {
        _route = State(initialValue: route)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                Sidebar(route: $route)
                    .frame(width: 250)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle().fill(Theme.rule.opacity(0.75)).frame(width: 1)
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PaperBackground())
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .newEntry)) { _ in route = .compose }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { showSidebar.toggle() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch route {
        case .compose:
            ComposeView(route: $route)
        case .favorites:
            FavoritesView()
        case let .entry(id):
            if journal.entry(id) != nil {
                EntryView(id: id, onDelete: {
                    route = .compose
                    journal.delete(id)
                })
            } else {
                ComposeView(route: $route)
            }
        }
    }
}

// MARK: - Seitenleiste

struct Sidebar: View {
    @Environment(Journal.self) private var journal
    @Binding var route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Platz für die Ampel-Knöpfe des Fensters
            Color.clear.frame(height: 52)

            HStack(spacing: 11) {
                BrandMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("GimmeTheVerse")
                        .font(Theme.serif(17, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Die Bibel zu deinem Tag.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)

            Rubric("Dein Raum")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 3) {
                SidebarRow(selected: route == .compose, action: { route = .compose }) {
                    rowLabel("Neuer Eintrag", systemImage: "square.and.pencil")
                }
                SidebarRow(selected: route == .favorites, action: { route = .favorites }) {
                    rowLabel("Lieblingsverse", systemImage: "heart", count: journal.favorites.count)
                }
            }

            if !journal.entries.isEmpty {
                HStack {
                    Rubric("Verlauf")
                    Spacer()
                    Text("\(journal.entries.count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(journal.entries) { entry in
                            SidebarRow(selected: route == .entry(entry.id), action: { route = .entry(entry.id) }) {
                                EntryRow(entry: entry)
                            }
                            .contextMenu {
                                Button("Löschen", role: .destructive) {
                                    if route == .entry(entry.id) { route = .compose }
                                    journal.delete(entry.id)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("Privat. Lokal. Nur deins.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .help("Alles läuft lokal über Ollama. Deine Einträge werden nur in ~/Library/Application Support/GimmeTheVerse gespeichert.")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.paperDeep)
    }

    private func rowLabel(_ title: String, systemImage: String, count: Int = 0) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 17)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            }
        }
    }
}

private struct SidebarRow<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? Theme.accentSoft.opacity(0.85) : hovering ? Theme.rule.opacity(0.4) : .clear)
                }
                .overlay(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent)
                            .frame(width: 3)
                            .padding(.vertical, 9)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

private struct EntryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(entry.date, format: .relative(presentation: .named))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}
