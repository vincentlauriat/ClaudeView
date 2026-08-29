import Foundation

/// A dashboard widget instance (kind + size), part of the persisted layout.
struct WidgetConfig: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case todayCost, monthCost, tokenTotals, budgetGauge
        case heatmap, topModels, topProjects, recentSessions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .todayCost: "Coût du jour"
            case .monthCost: "Coût du mois"
            case .tokenTotals: "Tokens (30 j)"
            case .budgetGauge: "Budget mensuel"
            case .heatmap: "Heatmap d'activité"
            case .topModels: "Top modèles"
            case .topProjects: "Top projets"
            case .recentSessions: "Sessions récentes"
            }
        }
        var systemImage: String {
            switch self {
            case .todayCost: "dollarsign.circle"
            case .monthCost: "calendar.badge.clock"
            case .tokenTotals: "number.circle"
            case .budgetGauge: "gauge.with.needle"
            case .heatmap: "square.grid.4x3.fill"
            case .topModels: "cpu"
            case .topProjects: "folder"
            case .recentSessions: "clock.arrow.circlepath"
            }
        }
        /// Wide widgets span the full dashboard width.
        var defaultWide: Bool {
            switch self {
            case .heatmap, .recentSessions: true
            default: false
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var wide: Bool

    init(kind: Kind, wide: Bool? = nil) {
        self.kind = kind
        self.wide = wide ?? kind.defaultWide
    }

    static let defaultLayout: [WidgetConfig] = [
        WidgetConfig(kind: .todayCost),
        WidgetConfig(kind: .monthCost),
        WidgetConfig(kind: .tokenTotals),
        WidgetConfig(kind: .budgetGauge),
        WidgetConfig(kind: .heatmap),
        WidgetConfig(kind: .topModels),
        WidgetConfig(kind: .topProjects),
        WidgetConfig(kind: .recentSessions),
    ]
}

/// Monthly/daily budget thresholds (USD). 0 = disabled.
struct Budget: Codable, Equatable {
    var monthlyLimitUSD: Double = 0
    var dailyLimitUSD: Double = 0
}

/// A saved sessions-list view: name + filter state.
struct SavedView: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var projectId: Int64?      // nil = all projects
    var searchText: String = ""
    var onlyWithCost: Bool = false
    var since: Date?
}

enum SettingsKeys {
    static let theme = "theme"
    static let dashboardLayout = "dashboardLayout"
    static let budget = "budget"
    static let savedViews = "savedViews"
    static let sessionColumns = "sessionColumns"
}
