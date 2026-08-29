import SwiftUI
import GRDB

struct SearchHit: Identifiable, Hashable {
    var uuid: String
    var sessionId: String
    var sessionTitle: String
    var projectName: String
    var filePath: String
    var ts: Date
    var kind: String
    var snippet: String
    var id: String { uuid }
}

struct SearchView: View {
    @EnvironmentObject var appState: AppState

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var roleFilter = "all"     // all | user | assistant
    @State private var projectFilter: Int64?
    @State private var projects: [ProjectRow] = []
    @State private var opened: SearchHit?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                resultsList
            }
            .navigationTitle("Recherche")
            .navigationDestination(item: $opened) { hit in
                if let session = fetchSession(hit.sessionId) {
                    TranscriptView(session: session, projectName: hit.projectName,
                                   scrollTarget: hit.uuid)
                } else {
                    ContentUnavailableView("Session introuvable", systemImage: "questionmark.circle")
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Rechercher dans les messages")
        .onChange(of: query) { scheduleSearch() }
        .onChange(of: roleFilter) { scheduleSearch() }
        .onChange(of: projectFilter) { scheduleSearch() }
        .onAppear(perform: loadProjects)
    }

    private var filterBar: some View {
        HStack {
            Picker("Rôle", selection: $roleFilter) {
                Text("Tous").tag("all")
                Text("Vincent").tag("user")
                Text("Claude").tag("assistant")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Picker("Projet", selection: $projectFilter) {
                Text("Tous les projets").tag(Int64?.none)
                ForEach(projects) { p in
                    Text(p.name).tag(Optional(p.id ?? -1))
                }
            }
            .frame(maxWidth: 240)
            Spacer()
            if !hits.isEmpty {
                Text("\(hits.count) résultat\(hits.count > 1 ? "s" : "")")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var resultsList: some View {
        if query.isEmpty {
            ContentUnavailableView(
                "Recherche plein-texte",
                systemImage: "magnifyingglass",
                description: Text("Tape une requête — opérateurs FTS5 acceptés (AND, OR, \"phrase\", préfixe*)."))
        } else if hits.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(hits) { hit in
                Button {
                    opened = hit
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: hit.kind == "assistant" ? "sparkles" : "person.circle")
                                .foregroundStyle(hit.kind == "assistant" ? .orange : .blue)
                            Text(hit.sessionTitle).bold().lineLimit(1)
                            Spacer()
                            Text(hit.projectName).foregroundStyle(.secondary)
                            Text(Format.dateTime.string(from: hit.ts))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                        Text(highlightedSnippet(hit.snippet))
                            .font(.callout)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, appState.theme.density.rowPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// FTS snippet uses « » markers; render them bold.
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var remaining = Substring(snippet)
        while let open = remaining.range(of: "\u{2039}"), let close = remaining.range(of: "\u{203A}"),
              open.lowerBound < close.lowerBound {
            result += AttributedString(remaining[..<open.lowerBound])
            var match = AttributedString(remaining[open.upperBound..<close.lowerBound])
            match.font = .callout.bold()
            match.foregroundColor = appState.theme.accent.color
            result += match
            remaining = remaining[close.upperBound...]
        }
        result += AttributedString(remaining)
        return result
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query
        guard !q.isEmpty else { hits = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            runSearch(q)
        }
    }

    private func runSearch(_ rawQuery: String) {
        guard let db = appState.database else { return }
        struct Row: Decodable, FetchableRecord {
            var uuid: String
            var sessionId: String
            var snippet: String
            var ts: Date
            var kind: String
            var title: String?
            var filePath: String
            var projectName: String
        }
        var sql = """
            SELECT f.uuid AS uuid, f.sessionId AS sessionId,
                   snippet(message_fts, 0, '\u{2039}', '\u{203A}', '…', 18) AS snippet,
                   m.ts AS ts, m.kind AS kind,
                   s.title AS title, s.filePath AS filePath, p.name AS projectName
            FROM message_fts f
            JOIN message m ON m.uuid = f.uuid
            JOIN session s ON s.id = f.sessionId
            JOIN project p ON p.id = m.projectId
            WHERE message_fts MATCH ?
            """
        var arguments: [DatabaseValueConvertible] = [ftsQuery(rawQuery)]
        if roleFilter != "all" {
            sql += " AND m.kind = ?"
            arguments.append(roleFilter)
        }
        if let pid = projectFilter {
            sql += " AND m.projectId = ?"
            arguments.append(pid)
        }
        sql += " ORDER BY m.ts DESC LIMIT 300"
        let rows = (try? db.dbQueue.read { dbq in
            try Row.fetchAll(dbq, sql: sql, arguments: StatementArguments(arguments))
        }) ?? []
        hits = rows.map {
            SearchHit(uuid: $0.uuid, sessionId: $0.sessionId,
                      sessionTitle: $0.title ?? $0.sessionId,
                      projectName: $0.projectName, filePath: $0.filePath,
                      ts: $0.ts, kind: $0.kind, snippet: $0.snippet)
        }
    }

    /// Quotes bare tokens so user input can't crash the FTS5 query parser,
    /// while still allowing explicit operators when the query parses as-is.
    private func ftsQuery(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("\"") || trimmed.contains(" AND ") || trimmed.contains(" OR ")
            || trimmed.contains(" NOT ") || trimmed.hasSuffix("*") {
            return trimmed
        }
        return trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " ")
    }

    private func fetchSession(_ id: String) -> SessionRow? {
        guard let db = appState.database else { return nil }
        return try? db.dbQueue.read { try SessionRow.fetchOne($0, key: id) }
    }

    private func loadProjects() {
        guard let db = appState.database else { return }
        projects = (try? db.dbQueue.read { try ProjectRow.order(Column("name")).fetchAll($0) }) ?? []
    }
}
