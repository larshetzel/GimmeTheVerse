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
                    .frame(width: 236)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle().fill(Theme.rule).frame(width: 1)
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
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
            Color.clear.frame(height: 44)

            Text("GimmeTheVerse")
                .font(Theme.serif(17, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            SidebarRow(selected: route == .compose, action: { route = .compose }) {
                rowLabel("Neuer Eintrag", systemImage: "square.and.pencil")
            }
            SidebarRow(selected: route == .favorites, action: { route = .favorites }) {
                rowLabel("Lieblingsverse", systemImage: "heart", count: journal.favorites.count)
            }

            if !journal.entries.isEmpty {
                Rubric("Verlauf")
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
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
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.paperDeep)
    }

    private func rowLabel(_ title: String, systemImage: String, count: Int = 0) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(title)
                .font(Theme.serif(14))
                .foregroundStyle(Theme.ink)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
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
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Theme.rule.opacity(0.75) : hovering ? Theme.rule.opacity(0.35) : .clear)
                }
                .overlay(alignment: .leading) {
                    if selected {
                        Rectangle().fill(Theme.accent).frame(width: 2).padding(.vertical, 6)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(Theme.serif(14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(entry.date, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}
