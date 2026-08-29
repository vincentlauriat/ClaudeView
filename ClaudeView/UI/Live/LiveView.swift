import SwiftUI

/// Real-time "sniffer" of Claude Code session events, Wireshark-style:
/// event table on top, payload inspector below.
struct LiveView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        LiveFeedBody(feed: appState.liveFeed)
    }
}

private struct LiveFeedBody: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var feed: LiveFeedModel

    @State private var selection: LiveEvent.ID?
    @State private var kindFilter = "all"
    @State private var textFilter = ""
    @State private var followTail = true

    var body: some View {
        VSplitView {
            eventTable
                .frame(minHeight: 220)
            inspector
                .frame(minHeight: 140)
        }
        .navigationTitle("Live")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
    }

    private var subtitle: String {
        feed.paused
            ? "En pause — \(feed.events.count) événements"
            : "\(feed.events.count) événements"
    }

    private var filteredEvents: [LiveEvent] {
        feed.events.filter { e in
            (kindFilter == "all" || e.message.kind == kindFilter)
            && (textFilter.isEmpty
                || e.message.text.localizedCaseInsensitiveContains(textFilter)
                || e.projectName.localizedCaseInsensitiveContains(textFilter)
                || e.message.toolNames.joined(separator: ",")
                    .localizedCaseInsensitiveContains(textFilter))
        }
    }

    private var eventTable: some View {
        ScrollViewReader { proxy in
            Table(filteredEvents, selection: $selection) {
                TableColumn("Heure") { e in
                    Text(Format.time.string(from: e.message.timestamp)).monospacedDigit()
                }
                .width(70)
                TableColumn("Projet") { e in Text(e.projectName) }
                    .width(min: 90, ideal: 130)
                TableColumn("Rôle") { e in
                    Label(roleLabel(e), systemImage: roleIcon(e))
                        .foregroundStyle(roleColor(e))
                }
                .width(min: 90, ideal: 110)
                TableColumn("Modèle") { e in
                    Text(Format.modelShort(e.message.model)).foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 90)
                TableColumn("Outils") { e in
                    Text(e.message.toolNames.joined(separator: ", "))
                        .foregroundStyle(.teal)
                }
                .width(min: 60, ideal: 110)
                TableColumn("Tokens") { e in
                    let u = e.message.usage
                    Text(u.total > 0 ? Format.tokens(u.total) : "")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .width(55)
                TableColumn("Aperçu") { e in
                    Text(e.message.text.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1).foregroundStyle(.primary)
                }
                .width(min: 150, ideal: 400)
            }
            .onChange(of: feed.events.count) {
                if followTail, !feed.paused, let last = filteredEvents.last?.id {
                    proxy.scrollTo(last)
                    selection = selection ?? last
                }
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let id = selection, let event = feed.events.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(event.projectName, systemImage: "folder")
                        Label(String(event.message.sessionId.prefix(8)), systemImage: "number")
                        Label(Format.dateTime.string(from: event.message.timestamp),
                              systemImage: "clock")
                        Spacer()
                        let cost = appState.pricing.cost(
                            model: event.message.model, usage: event.message.usage)
                        if cost > 0 { Text(Format.cost(cost)).monospacedDigit() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let detail = MessageDetailLoader.load(
                        filePath: event.filePath,
                        byteOffset: event.byteOffset,
                        byteLength: event.byteLength) {
                        if !event.message.text.isEmpty {
                            MarkdownText(text: event.message.text,
                                         font: appState.theme.transcriptFont)
                                .textSelection(.enabled)
                        }
                        DetailBlocks(detail: detail, font: appState.theme.transcriptFont)
                    } else {
                        Text(event.message.text)
                            .font(appState.theme.transcriptFont)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Inspecteur",
                systemImage: "waveform.badge.magnifyingglass",
                description: Text(feed.events.isEmpty
                    ? "Les événements des sessions Claude Code actives apparaîtront ici en temps réel."
                    : "Sélectionne un événement pour inspecter son payload."))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Type", selection: $kindFilter) {
                Text("Tout").tag("all")
                Text("Vincent").tag("user")
                Text("Claude").tag("assistant")
                Text("Système").tag("system")
            }
            .pickerStyle(.segmented)
            TextField("Filtre", text: $textFilter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            Toggle(isOn: $followTail) {
                Label("Suivre", systemImage: "arrow.down.to.line")
            }
            .help("Défilement automatique vers le dernier événement")
            Button {
                if feed.paused { feed.resume() } else { feed.paused = true }
            } label: {
                Label(feed.paused ? "Reprendre" : "Pause",
                      systemImage: feed.paused ? "play.fill" : "pause.fill")
            }
            .help(feed.paused ? "Reprendre la capture" : "Suspendre la capture")
            Button {
                feed.clear()
                selection = nil
            } label: {
                Label("Vider", systemImage: "trash")
            }
        }
    }

    private func roleLabel(_ e: LiveEvent) -> String {
        switch e.message.kind {
        case "user": return e.message.isToolResult ? "Tool result" : "Vincent"
        case "assistant": return "Claude"
        default: return "Système"
        }
    }

    private func roleIcon(_ e: LiveEvent) -> String {
        switch e.message.kind {
        case "user": return e.message.isToolResult ? "arrow.uturn.left.circle" : "person.circle"
        case "assistant": return "sparkles"
        default: return "gearshape"
        }
    }

    private func roleColor(_ e: LiveEvent) -> Color {
        switch e.message.kind {
        case "user": return e.message.isToolResult ? .teal : .blue
        case "assistant": return .orange
        default: return .gray
        }
    }
}
