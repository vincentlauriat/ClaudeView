import SwiftUI

/// GitHub-style activity heatmap: one cell per day, columns are weeks.
struct HeatmapView: View {
    let activity: [String: Int]     // "yyyy-MM-dd" → message count
    var weeks: Int = 20

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var maxCount: Int { max(activity.values.max() ?? 1, 1) }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Align so the last column is the current (possibly partial) week.
        let daysInLastWeek = ((weekday - calendar.firstWeekday) + 7) % 7 + 1

        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { day in
                        let daysAgo = (weeks - 1 - week) * 7 + (daysInLastWeek - 1 - day)
                        if daysAgo >= 0,
                           let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) {
                            cell(for: date)
                        } else {
                            Color.clear.frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
    }

    private func cell(for date: Date) -> some View {
        let key = Self.keyFormatter.string(from: date)
        let count = activity[key] ?? 0
        let intensity = count == 0 ? 0 : 0.15 + 0.85 * min(1, Double(count) / Double(maxCount))
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(count == 0
                  ? AnyShapeStyle(Color(nsColor: .quaternarySystemFill))
                  : AnyShapeStyle(Color.accentColor.opacity(intensity)))
            .frame(width: 12, height: 12)
            .help("\(key) — \(count) messages")
    }
}
