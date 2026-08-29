import SwiftUI
import GRDB

/// A session with its display metadata (project name, computed cost).
struct SessionItem: Identifiable, Hashable {
    var row: SessionRow
    var projectName: String
    var cost: Double
    var id: String { row.id }

    var title: String { row.title ?? row.id }
    var lastTs: Date { row.lastTs ?? .distantPast }
    var messageCount: Int { row.messageCount }
    var totalTokens: Int {
        row.inputTokens + row.outputTokens + row.cacheReadTokens + row.cacheCreationTokens
    }
    var model: String { Format.modelShort(row.model) }
    var branch: String { row.gitBranch ?? "" }
}

struct SessionsView: View {
    @EnvironmentObject var appState: AppState

    @State private var items: [SessionItem] = []
    @State private var projects: [ProjectRow] = []
    @State private var selection: SessionItem.ID?
    @State private var sortOrder = [KeyPathComparator(\SessionItem.lastTs, order: .reverse)]
    @State private var columnCustomization = TableColumnCustomization<SessionItem>()
    @State private var filterProject: Int64?
    @State private var filterText = ""
    @State private var openedSession: SessionItem?
    @State private var savingViewName = ""
    @State private var showSaveViewAlert = false

    var body: some View {
        NavigationStack {
            table
                .navigationDestination(item: $openedSession) { item in
                    TranscriptView(session: item.row, projectName: item.projectName)
                }
                .navigationTitle("Sessions")
                .toolbar { toolbarContent }
                .searchable(text: $filterText, placement: .toolbar, prompt: "Filtrer titre, projet, branche")
        }
        .onAppear(perform: reload)
        .onChange(of: appState.dataVersion) { reload() }
        .onChange(of: columnCustomization) {
            appState.database?.writeSetting(SettingsKeys.sessionColumns, value: columnCustomization)
        }
        .alert("Enregistrer la vue", isPresented: $showSaveViewAlert) {
            TextField("Nom de la vue", text: $savingViewName)
            Button("Enregistrer") { saveCurrentView() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Sauvegarde le projet et le filtre actuels comme vue nommée.")
        }
    }

    private var filtered: [SessionItem] {
        var result = items
        if let pid = filterProject {
            result = result.filter { $0.row.projectId == pid }
        }
        if !filterText.isEmpty {
            let needle = filterText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(needle)
                || $0.projectName.lowercased().contains(needle)
                || $0.branch.lowercased().contains(needle)
            }
        }
        return result.sorted(using: sortOrder)
    }

    private var table: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumn("Titre", value: \.title) { item in
                Text(item.title).lineLimit(1)
            }
            .width(min: 150, ideal: 320)
            .customizationID("title")

            TableColumn("Projet", value: \.projectName) { item in
                Text(item.projectName).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 140)
            .customizationID("project")

            TableColumn("Dernière activité", value: \.lastTs) { item in
                Text(Format.dateTime.string(from: item.lastTs))
            }
            .width(min: 110, ideal: 150)
            .customizationID("lastTs")

            TableColumn("Messages", value: \.messageCount) { item in
                Text("\(item.messageCount)").monospacedDigit()
            }
            .width(min: 55, ideal: 70)
            .customizationID("messages")

            TableColumn("Tokens", value: \.totalTokens) { item in
                Text(Format.tokens(item.totalTokens)).monospacedDigit()
            }
            .width(min: 55, ideal: 75)
            .customizationID("tokens")

            TableColumn("Coût", value: \.cost) { item in
                Text(Format.cost(item.cost)).monospacedDigit()
            }
            .width(min: 55, ideal: 75)
            .customizationID("cost")

            TableColumn("Modèle", value: \.model) { item in
                Text(item.model).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 100)
            .customizationID("model")

            TableColumn("Branche", value: \.branch) { item in
                Text(item.branch).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 110)
            .customizationID("branch")
        }
        .contextMenu(forSelectionType: SessionItem.ID.self) { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                Button("Ouvrir la transcription") { openedSession = item }
                Button("Afficher le fichier dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: item.row.filePath)])
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                openedSession = item
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Projet", selection: $filterProject) {
                Text("Tous les projets").tag(Int64?.none)
                ForEach(projects) { p in
                    Text(p.name).tag(Optional(p.id ?? -1))
                }
            }
            .frame(minWidth: 150)
        }
        ToolbarItem {
            Menu {
                ForEach(appState.savedViews) { view in
                    Button(view.name) { apply(view) }
                }
                if !appState.savedViews.isEmpty { Divider() }
                Button("Enregistrer la vue actuelle…") {
                    savingViewName = ""
                    showSaveViewAlert = true
                }
                if !appState.savedViews.isEmpty {
                    Menu("Supprimer une vue") {
                        ForEach(appState.savedViews) { view in
                            Button(view.name) {
                                appState.savedViews.removeAll { $0.id == view.id }
                            }
                        }
                    }
                }
            } label: {
                Label("Vues", systemImage: "square.stack.3d.up")
            }
        }
    }

    private func apply(_ view: SavedView) {
        filterProject = view.projectId
        filterText = view.searchText
    }

    private func saveCurrentView() {
        guard !savingViewName.isEmpty else { return }
        appState.savedViews.append(SavedView(
            name: savingViewName, projectId: filterProject, searchText: filterText))
    }

    private func reload() {
        guard let db = appState.database, let analytics = appState.analytics else { return }
        let fetched = (try? db.dbQueue.read { dbq -> ([ProjectRow], [SessionRow]) in
            let p = try ProjectRow.order(Column("name")).fetchAll(dbq)
            let s = try SessionRow.order(Column("lastTs").desc).fetchAll(dbq)
            return (p, s)
        }) ?? ([], [])
        projects = fetched.0
        let names = Dictionary(uniqueKeysWithValues: fetched.0.compactMap { p in
            p.id.map { ($0, p.name) }
        })
        items = fetched.1.map {
            SessionItem(row: $0, projectName: names[$0.projectId] ?? "?",
                        cost: analytics.sessionCost($0))
        }
        if let stored = db.readSetting(
            SettingsKeys.sessionColumns, as: TableColumnCustomization<SessionItem>.self),
           columnCustomization == TableColumnCustomization<SessionItem>() {
            columnCustomization = stored
        }
    }
}
