import Foundation
import GRDB

/// Read-side queries for dashboard and stats. Costs are computed here,
/// at query time, from token sums × PricingEngine (never stored).
struct AnalyticsStore {
    let database: AppDatabase
    let pricing: PricingEngine

    struct DayCost: Identifiable, Equatable {
        var day: Date
        var cost: Double
        var messages: Int
        var id: Date { day }
    }

    struct ModelSlice: Identifiable, Equatable {
        var model: String
        var cost: Double
        var inputTokens: Int
        var outputTokens: Int
        var cacheReadTokens: Int
        var cacheCreationTokens: Int
        var id: String { model }
        var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens }
    }

    struct ProjectSlice: Identifiable, Equatable {
        var projectId: Int64
        var name: String
        var cost: Double
        var sessions: Int
        var id: Int64 { projectId }
    }

    private struct TokenGroup: Decodable, FetchableRecord {
        var day: String?
        var model: String?
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheCreation: Int
        var count: Int
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// Daily costs for the last `days` days (local time), oldest first.
    func dailyCosts(days: Int) -> [DayCost] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let rows = (try? database.dbQueue.read { db in
            try TokenGroup.fetchAll(db, sql: """
                SELECT date(ts, 'localtime') AS day, model,
                       SUM(inputTokens) AS input, SUM(outputTokens) AS output,
                       SUM(cacheReadTokens) AS cacheRead,
                       SUM(cacheCreationTokens) AS cacheCreation,
                       COUNT(*) AS count
                FROM message
                WHERE ts >= ? AND kind = 'assistant'
                GROUP BY day, model
                """, arguments: [since])
        }) ?? []
        var byDay: [String: DayCost] = [:]
        for r in rows {
            guard let dayStr = r.day, let day = Self.dayFormatter.date(from: dayStr) else { continue }
            let cost = pricing.cost(model: r.model, input: r.input, output: r.output,
                                    cacheRead: r.cacheRead, cacheCreation: r.cacheCreation)
            var d = byDay[dayStr] ?? DayCost(day: day, cost: 0, messages: 0)
            d.cost += cost
            d.messages += r.count
            byDay[dayStr] = d
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Total cost between two dates.
    func cost(from: Date, to: Date = Date()) -> Double {
        let rows = (try? database.dbQueue.read { db in
            try TokenGroup.fetchAll(db, sql: """
                SELECT NULL AS day, model,
                       SUM(inputTokens) AS input, SUM(outputTokens) AS output,
                       SUM(cacheReadTokens) AS cacheRead,
                       SUM(cacheCreationTokens) AS cacheCreation,
                       COUNT(*) AS count
                FROM message
                WHERE ts >= ? AND ts <= ? AND kind = 'assistant'
                GROUP BY model
                """, arguments: [from, to])
        }) ?? []
        return rows.reduce(0) {
            $0 + pricing.cost(model: $1.model, input: $1.input, output: $1.output,
                              cacheRead: $1.cacheRead, cacheCreation: $1.cacheCreation)
        }
    }

    func todayCost() -> Double {
        cost(from: Calendar.current.startOfDay(for: Date()))
    }

    func monthCost() -> Double {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return cost(from: Calendar.current.date(from: comps)!)
    }

    /// Per-model token/cost breakdown since a date.
    func modelBreakdown(since: Date) -> [ModelSlice] {
        let rows = (try? database.dbQueue.read { db in
            try TokenGroup.fetchAll(db, sql: """
                SELECT NULL AS day, model,
                       SUM(inputTokens) AS input, SUM(outputTokens) AS output,
                       SUM(cacheReadTokens) AS cacheRead,
                       SUM(cacheCreationTokens) AS cacheCreation,
                       COUNT(*) AS count
                FROM message
                WHERE ts >= ? AND kind = 'assistant' AND model IS NOT NULL
                GROUP BY model
                """, arguments: [since])
        }) ?? []
        return rows.compactMap { r in
            guard let model = r.model else { return nil }
            return ModelSlice(
                model: model,
                cost: pricing.cost(model: model, input: r.input, output: r.output,
                                   cacheRead: r.cacheRead, cacheCreation: r.cacheCreation),
                inputTokens: r.input, outputTokens: r.output,
                cacheReadTokens: r.cacheRead, cacheCreationTokens: r.cacheCreation)
        }.sorted { $0.cost > $1.cost }
    }

    /// Per-project cost since a date.
    func projectBreakdown(since: Date) -> [ProjectSlice] {
        struct Row: Decodable, FetchableRecord {
            var projectId: Int64
            var name: String
            var model: String?
            var input: Int
            var output: Int
            var cacheRead: Int
            var cacheCreation: Int
            var sessions: Int
        }
        let rows = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.projectId AS projectId, p.name AS name, m.model AS model,
                       SUM(m.inputTokens) AS input, SUM(m.outputTokens) AS output,
                       SUM(m.cacheReadTokens) AS cacheRead,
                       SUM(m.cacheCreationTokens) AS cacheCreation,
                       COUNT(DISTINCT m.sessionId) AS sessions
                FROM message m JOIN project p ON p.id = m.projectId
                WHERE m.ts >= ? AND m.kind = 'assistant'
                GROUP BY m.projectId, m.model
                """, arguments: [since])
        }) ?? []
        var byProject: [Int64: ProjectSlice] = [:]
        for r in rows {
            let cost = pricing.cost(model: r.model, input: r.input, output: r.output,
                                    cacheRead: r.cacheRead, cacheCreation: r.cacheCreation)
            var slice = byProject[r.projectId]
                ?? ProjectSlice(projectId: r.projectId, name: r.name, cost: 0, sessions: 0)
            slice.cost += cost
            slice.sessions = max(slice.sessions, r.sessions)
            byProject[r.projectId] = slice
        }
        return byProject.values.sorted { $0.cost > $1.cost }
    }

    /// Message counts per day (for the heatmap), keyed by "yyyy-MM-dd".
    func activityByDay(days: Int) -> [String: Int] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        struct Row: Decodable, FetchableRecord { var day: String; var count: Int }
        let rows = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT date(ts, 'localtime') AS day, COUNT(*) AS count
                FROM message WHERE ts >= ? GROUP BY day
                """, arguments: [since])
        }) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0.count) })
    }

    func recentSessions(limit: Int) -> [SessionRow] {
        (try? database.dbQueue.read { db in
            try SessionRow.order(Column("lastTs").desc).limit(limit).fetchAll(db)
        }) ?? []
    }

    func sessionCost(_ s: SessionRow) -> Double {
        pricing.cost(model: s.model, input: s.inputTokens, output: s.outputTokens,
                     cacheRead: s.cacheReadTokens, cacheCreation: s.cacheCreationTokens)
    }

    func totals(since: Date) -> TokenUsage {
        let rows = (try? database.dbQueue.read { db in
            try TokenGroup.fetchAll(db, sql: """
                SELECT NULL AS day, NULL AS model,
                       COALESCE(SUM(inputTokens), 0) AS input,
                       COALESCE(SUM(outputTokens), 0) AS output,
                       COALESCE(SUM(cacheReadTokens), 0) AS cacheRead,
                       COALESCE(SUM(cacheCreationTokens), 0) AS cacheCreation,
                       COUNT(*) AS count
                FROM message WHERE ts >= ? AND kind = 'assistant'
                """, arguments: [since])
        }) ?? []
        guard let r = rows.first else { return TokenUsage() }
        return TokenUsage(input: r.input, output: r.output,
                          cacheRead: r.cacheRead, cacheCreation: r.cacheCreation)
    }
}
