import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var appState: AppState

    @State private var periodDays = 30
    @State private var dailyCosts: [AnalyticsStore.DayCost] = []
    @State private var models: [AnalyticsStore.ModelSlice] = []
    @State private var projectSlices: [AnalyticsStore.ProjectSlice] = []
    @State private var activity: [String: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Période", selection: $periodDays) {
                    Text("30 jours").tag(30)
                    Text("90 jours").tag(90)
                    Text("1 an").tag(365)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                GroupBox("Coût par jour") {
                    if dailyCosts.isEmpty {
                        emptyChart
                    } else {
                        Chart(dailyCosts) { day in
                            BarMark(
                                x: .value("Jour", day.day, unit: .day),
                                y: .value("Coût", day.cost))
                            .foregroundStyle(Color.accentColor.gradient)
                        }
                        .frame(height: 180)
                        .padding(.top, 6)
                    }
                }

                GroupBox("Activité (messages par jour)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HeatmapView(activity: activity, weeks: min(52, max(periodDays / 7 + 1, 20)))
                            .padding(6)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Par modèle") {
                        if models.isEmpty {
                            emptyChart
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(models) { m in
                                    HStack {
                                        Text(Format.modelShort(m.model)).bold()
                                        Spacer()
                                        Text(Format.tokens(m.totalTokens))
                                            .foregroundStyle(.secondary).monospacedDigit()
                                        Text(Format.cost(m.cost)).monospacedDigit()
                                            .frame(width: 70, alignment: .trailing)
                                    }
                                    .font(.callout)
                                    ProgressView(value: m.cost,
                                                 total: max(models.first?.cost ?? 1, 0.001))
                                        .tint(.accentColor)
                                }
                            }
                            .padding(6)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("Par projet") {
                        if projectSlices.isEmpty {
                            emptyChart
                        } else {
                            Chart(projectSlices.prefix(10)) { p in
                                BarMark(
                                    x: .value("Coût", p.cost),
                                    y: .value("Projet", p.name))
                                .foregroundStyle(Color.accentColor.gradient)
                            }
                            .chartXAxisLabel("USD")
                            .frame(height: max(180, CGFloat(min(projectSlices.count, 10)) * 26))
                            .padding(6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("Stats")
        .onAppear(perform: reload)
        .onChange(of: appState.dataVersion) { reload() }
        .onChange(of: periodDays) { reload() }
    }

    private var emptyChart: some View {
        Text("Pas encore de données")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func reload() {
        guard let analytics = appState.analytics else { return }
        let since = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date())!
        dailyCosts = analytics.dailyCosts(days: periodDays)
        models = analytics.modelBreakdown(since: since)
        projectSlices = analytics.projectBreakdown(since: since)
        activity = analytics.activityByDay(days: periodDays)
    }
}
