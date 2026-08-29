import SwiftUI
import GRDB

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    let session: SessionRow
    let projectName: String
    var scrollTarget: String? = nil   // message uuid to scroll to (from search)

    @State private var messages: [MessageRow] = []
    @State private var showSidechains = false
    @State private var showSystem = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: appState.theme.density.rowPadding + 5) {
                    ForEach(visibleMessages) { message in
                        MessageBubble(message: message, filePath: session.filePath,
                                      highlighted: message.uuid == scrollTarget)
                            .id(message.uuid)
                    }
                }
                .padding()
            }
            .onAppear {
                reload()
                if let target = scrollTarget {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }
            .onChange(of: appState.dataVersion) { reload() }
        }
        .navigationTitle(session.title ?? session.id)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Menu {
                    Toggle("Afficher les sidechains", isOn: $showSidechains)
                    Toggle("Afficher les messages système", isOn: $showSystem)
                } label: {
                    Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var subtitle: String {
        let cost = appState.analytics?.sessionCost(session) ?? 0
        var parts = [projectName, "\(session.messageCount) messages", Format.cost(cost)]
        if session.malformedLines > 0 {
            parts.append("⚠︎ \(session.malformedLines) lignes ignorées")
        }
        return parts.joined(separator: " · ")
    }

    private var visibleMessages: [MessageRow] {
        messages.filter { m in
            (showSidechains || !m.isSidechain) && (showSystem || m.kind != "system")
        }
    }

    private func reload() {
        guard let db = appState.database else { return }
        messages = (try? db.dbQueue.read { dbq in
            try MessageRow.filter(Column("sessionId") == session.id)
                .order(Column("ts")).fetchAll(dbq)
        }) ?? []
    }
}

/// One transcript message: header, text, expandable detail (tool calls,
/// thinking, raw payload) lazily read from the JSONL file.
struct MessageBubble: View {
    @EnvironmentObject var appState: AppState
    let message: MessageRow
    let filePath: String
    var highlighted = false

    @State private var detail: MessageDetail?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if !message.text.isEmpty {
                MarkdownText(text: message.text, font: appState.theme.transcriptFont)
                    .textSelection(.enabled)
            }
            if expanded, let detail {
                DetailBlocks(detail: detail, font: appState.theme.transcriptFont)
            }
        }
        .padding(appState.theme.density.rowPadding + 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlighted ? message.roleColor.opacity(0.18) : Color(nsColor: .quaternarySystemFill)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(message.roleColor)
                .frame(width: 3)
                .padding(.vertical, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: message.roleIcon)
                .foregroundStyle(message.roleColor)
            Text(message.roleLabel).bold()
            if message.isSidechain {
                Text("sidechain")
                    .font(.caption2)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(.purple.opacity(0.2)))
            }
            ForEach(message.toolNameList, id: \.self) { tool in
                Text(tool)
                    .font(.caption2)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(.teal.opacity(0.2)))
            }
            if message.hasThinking {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .help("Contient un bloc thinking")
            }
            Spacer()
            if message.kind == "assistant" {
                Text(Format.modelShort(message.model))
                    .font(.caption).foregroundStyle(.secondary)
                let cost = appState.pricing.cost(model: message.model, usage: message.usage)
                if cost > 0 {
                    Text(Format.cost(cost))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text(Format.time.string(from: message.ts))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button {
                toggleDetail()
            } label: {
                Image(systemName: expanded ? "chevron.up.circle" : "chevron.down.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Détails (tool calls, thinking, payload brut)")
        }
        .font(.callout)
    }

    private func toggleDetail() {
        if expanded {
            expanded = false
            return
        }
        if detail == nil {
            detail = MessageDetailLoader.load(
                filePath: filePath,
                byteOffset: message.byteOffset,
                byteLength: message.byteLength)
        }
        expanded = detail != nil
    }
}

/// Renders the decoded blocks of a message payload.
struct DetailBlocks: View {
    let detail: MessageDetail
    let font: Font
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(detail.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
            DisclosureGroup("Payload brut (JSON)", isExpanded: $showRaw) {
                CodeBox(text: detail.rawJSON)
            }
            .font(.caption)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func blockView(_ block: MessageDetail.Block) -> some View {
        switch block {
        case .text:
            EmptyView() // already shown as the message body
        case .thinking(let t):
            VStack(alignment: .leading, spacing: 2) {
                Label("Thinking", systemImage: "brain")
                    .font(.caption).foregroundStyle(.purple)
                Text(t).font(font).italic().foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.purple.opacity(0.07)))
        case .toolUse(_, let name, let inputJSON):
            VStack(alignment: .leading, spacing: 2) {
                Label(name, systemImage: "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(.teal)
                CodeBox(text: inputJSON)
            }
        case .toolResult(_, let isError, let content):
            VStack(alignment: .leading, spacing: 2) {
                Label(isError ? "Résultat (erreur)" : "Résultat",
                      systemImage: isError ? "xmark.octagon" : "arrow.uturn.left")
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .teal)
                CodeBox(text: String(content.prefix(4000)))
            }
        }
    }
}

struct CodeBox: View {
    let text: String
    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    }
}

/// Markdown-ish text: renders inline markdown per paragraph, keeps line breaks.
struct MarkdownText: View {
    let text: String
    let font: Font

    var body: some View {
        let display = text.count > 20_000 ? String(text.prefix(20_000)) + "\n…" : text
        if let attributed = try? AttributedString(
            markdown: display,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed).font(font)
        } else {
            Text(display).font(font)
        }
    }
}
