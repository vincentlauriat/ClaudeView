import SwiftUI

/// Modular dashboard: a grid of user-configurable widgets. Edit mode allows
/// adding, removing, reordering and resizing; layout persists in the database.
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var editMode = false

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(appState.dashboardLayout) { widget in
                    WidgetCard(widget: widget, editMode: editMode,
                               onRemove: { remove(widget) },
                               onMoveLeft: { move(widget, by: -1) },
                               onMoveRight: { move(widget, by: +1) },
                               onToggleWide: { toggleWide(widget) })
                    .gridCellColumns(widget.wide ? gridSpan : 1)
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItemGroup {
                if editMode { addMenu }
                Toggle(isOn: $editMode.animation()) {
                    Label("Personnaliser", systemImage: "slider.horizontal.3")
                }
                .help("Ajouter, retirer, réordonner et dimensionner les widgets")
            }
        }
    }

    /// Approximate span for wide widgets with the adaptive grid.
    private var gridSpan: Int { 2 }

    private var addMenu: some View {
        Menu {
            ForEach(WidgetConfig.Kind.allCases) { kind in
                Button {
                    withAnimation { appState.dashboardLayout.append(WidgetConfig(kind: kind)) }
                } label: {
                    Label(kind.label, systemImage: kind.systemImage)
                }
            }
            Divider()
            Button("Réinitialiser le dashboard") {
                withAnimation { appState.dashboardLayout = WidgetConfig.defaultLayout }
            }
        } label: {
            Label("Ajouter un widget", systemImage: "plus")
        }
    }

    private func remove(_ widget: WidgetConfig) {
        withAnimation { appState.dashboardLayout.removeAll { $0.id == widget.id } }
    }

    private func move(_ widget: WidgetConfig, by delta: Int) {
        guard let index = appState.dashboardLayout.firstIndex(where: { $0.id == widget.id }) else { return }
        let target = index + delta
        guard target >= 0, target < appState.dashboardLayout.count else { return }
        withAnimation { appState.dashboardLayout.swapAt(index, target) }
    }

    private func toggleWide(_ widget: WidgetConfig) {
        guard let index = appState.dashboardLayout.firstIndex(where: { $0.id == widget.id }) else { return }
        withAnimation { appState.dashboardLayout[index].wide.toggle() }
    }
}

/// Chrome around a widget: title bar + edit controls.
private struct WidgetCard: View {
    @EnvironmentObject var appState: AppState
    let widget: WidgetConfig
    let editMode: Bool
    let onRemove: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onToggleWide: () -> Void

    var body: some View {
        GroupBox {
            WidgetBody(kind: widget.kind)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 90)
        } label: {
            HStack {
                Label(widget.kind.label, systemImage: widget.kind.systemImage)
                    .font(.headline)
                Spacer()
                if editMode {
                    HStack(spacing: 8) {
                        Button(action: onMoveLeft) { Image(systemName: "arrow.left") }
                        Button(action: onMoveRight) { Image(systemName: "arrow.right") }
                        Button(action: onToggleWide) {
                            Image(systemName: widget.wide
                                  ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .rotationEffect(.degrees(90))
                        }
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The actual content of each widget kind.
private struct WidgetBody: View {
    @EnvironmentObject var appState: AppState
    let kind: WidgetConfig.Kind

    @State private var value: Double = 0
    @State private var models: [AnalyticsStore.ModelSlice] = []
    @State private var projectSlices: [AnalyticsStore.ProjectSlice] = []
    @State private var sessions: [SessionRow] = []
    @State private var activity: [String: Int] = [:]
    @State private var usage = TokenUsage()

    var body: some View {
        content
            .onAppear(perform: reload)
            .onChange(of: appState.dataVersion) { reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .todayCost:
            bigNumber(Format.cost(value), caption: "aujourd'hui")
        case .monthCost:
            bigNumber(Format.cost(value), caption: "ce mois-ci")
        case .tokenTotals:
            VStack(alignment: .leading, spacing: 4) {
                tokenLine("Entrée", usage.input)
                tokenLine("Sortie", usage.output)
                tokenLine("Cache lu", usage.cacheRead)
                tokenLine("Cache écrit", usage.cacheCreation)
            }
        case .budgetGauge:
            if appState.budget.monthlyLimitUSD > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Gauge(value: min(value, appState.budget.monthlyLimitUSD),
                          in: 0...appState.budget.monthlyLimitUSD) {
                        Text("Budget")
                    } currentValueLabel: {
                        Text(Format.cost(value))
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(value > appState.budget.monthlyLimitUSD * 0.9 ? .red : .accentColor)
                    Text("sur \(Format.cost(appState.budget.monthlyLimitUSD)) / mois")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Définis un budget mensuel dans les Réglages.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .heatmap:
            ScrollView(.horizontal, showsIndicators: false) {
                HeatmapView(activity: activity, weeks: 26).padding(.vertical, 4)
            }
        case .topModels:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(models.prefix(4)) { m in
                    HStack {
                        Text(Format.modelShort(m.model))
                        Spacer()
                        Text(Format.cost(m.cost)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                if models.isEmpty { emptyNote }
            }
        case .topProjects:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(projectSlices.prefix(4)) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text(Format.cost(p.cost)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                if projectSlices.isEmpty { emptyNote }
            }
        case .recentSessions:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sessions.prefix(5)) { s in
                    HStack {
                        Text(s.title ?? s.id).lineLimit(1)
                        Spacer()
                        if let ts = s.lastTs {
                            Text(Format.relative.localizedString(for: ts, relativeTo: Date()))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                if sessions.isEmpty { emptyNote }
            }
        }
    }

    private var emptyNote: some View {
        Text("Pas encore de données").font(.callout).foregroundStyle(.secondary)
    }

    private func bigNumber(_ text: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tokenLine(_ label: String, _ n: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Format.tokens(n)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func reload() {
        guard let analytics = appState.analytics else { return }
        let month = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        let thirtyDays = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        switch kind {
        case .todayCost: value = analytics.todayCost()
        case .monthCost, .budgetGauge: value = analytics.monthCost()
        case .tokenTotals: usage = analytics.totals(since: thirtyDays)
        case .heatmap: activity = analytics.activityByDay(days: 26 * 7)
        case .topModels: models = analytics.modelBreakdown(since: month)
        case .topProjects: projectSlices = analytics.projectBreakdown(since: month)
        case .recentSessions: sessions = analytics.recentSessions(limit: 5)
        }
    }
}
