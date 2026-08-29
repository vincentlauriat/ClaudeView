import SwiftUI

/// User-customizable appearance, persisted in `appSetting`.
struct Theme: Codable, Equatable {
    enum Accent: String, Codable, CaseIterable, Identifiable {
        case orange, blue, purple, pink, red, green, teal, indigo, graphite
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .orange: .orange
            case .blue: .blue
            case .purple: .purple
            case .pink: .pink
            case .red: .red
            case .green: .green
            case .teal: .teal
            case .indigo: .indigo
            case .graphite: Color(nsColor: .systemGray)
            }
        }
        var label: String {
            switch self {
            case .orange: "Orange"
            case .blue: "Bleu"
            case .purple: "Violet"
            case .pink: "Rose"
            case .red: "Rouge"
            case .green: "Vert"
            case .teal: "Turquoise"
            case .indigo: "Indigo"
            case .graphite: "Graphite"
            }
        }
    }

    enum Scheme: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "Système"
            case .light: "Clair"
            case .dark: "Sombre"
            }
        }
    }

    enum Density: String, Codable, CaseIterable, Identifiable {
        case compact, regular, comfortable
        var id: String { rawValue }
        var label: String {
            switch self {
            case .compact: "Compacte"
            case .regular: "Normale"
            case .comfortable: "Confortable"
            }
        }
        var rowPadding: CGFloat {
            switch self {
            case .compact: 2
            case .regular: 5
            case .comfortable: 9
            }
        }
    }

    var accent: Accent = .orange
    var scheme: Scheme = .system
    var density: Density = .regular
    var transcriptFontSize: Double = 13
    var transcriptUsesMonospace: Bool = false

    var colorScheme: ColorScheme? {
        switch scheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var transcriptFont: Font {
        transcriptUsesMonospace
            ? .system(size: transcriptFontSize, design: .monospaced)
            : .system(size: transcriptFontSize)
    }
}
