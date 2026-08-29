import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case dashboard, sessions, search, live, stats
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: "Dashboard"
        case .sessions: "Sessions"
        case .search: "Recherche"
        case .live: "Live"
        case .stats: "Stats"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .sessions: "bubble.left.and.bubble.right"
        case .search: "magnifyingglass"
        case .live: "dot.radiowaves.left.and.right"
        case .stats: "chart.bar.xaxis"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var section: MainSection = .dashboard

    var body: some View {
        if let error = appState.loadError {
            ContentUnavailableView(
                "Base de données indisponible",
                systemImage: "exclamationmark.triangle",
                description: Text(error))
        } else {
            NavigationSplitView {
                List(MainSection.allCases, selection: Binding(
                    get: { Optional(section) },
                    set: { if let s = $0 { section = s } })
                ) { s in
                    Label(s.label, systemImage: s.systemImage).tag(s)
                }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
                .safeAreaInset(edge: .bottom) {
                    syncFooter
                }
            } detail: {
                switch section {
                case .dashboard: DashboardView()
                case .sessions: SessionsView()
                case .search: SearchView()
                case .live: LiveView()
                case .stats: StatsView()
                }
            }
            .navigationTitle("ClaudeView")
        }
    }

    private var syncFooter: some View {
        HStack(spacing: 6) {
            if appState.isIndexing {
                ProgressView().controlSize(.small)
                Text("Indexation…")
            } else if let last = appState.lastSync {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Sync \(Format.relative.localizedString(for: last, relativeTo: Date()))")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
