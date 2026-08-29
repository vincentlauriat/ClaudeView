import SwiftUI
import GRDB

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Apparence", systemImage: "paintpalette") }
            PricingSettings()
                .tabItem { Label("Tarifs", systemImage: "dollarsign.circle") }
            BudgetSettings()
                .tabItem { Label("Budget", systemImage: "gauge.with.needle") }
            DataSettings()
                .tabItem { Label("Données", systemImage: "externaldrive") }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Picker("Couleur d'accent", selection: $appState.theme.accent) {
                ForEach(Theme.Accent.allCases) { accent in
                    HStack {
                        Circle().fill(accent.color).frame(width: 12, height: 12)
                        Text(accent.label)
                    }
                    .tag(accent)
                }
            }
            Picker("Apparence", selection: $appState.theme.scheme) {
                ForEach(Theme.Scheme.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
            Picker("Densité d'affichage", selection: $appState.theme.density) {
                ForEach(Theme.Density.allCases) { d in Text(d.label).tag(d) }
            }
            .pickerStyle(.segmented)
            Section("Transcriptions") {
                Slider(value: $appState.theme.transcriptFontSize, in: 10...18, step: 1) {
                    Text("Taille du texte : \(Int(appState.theme.transcriptFontSize)) pt")
                }
                Toggle("Police à chasse fixe", isOn: $appState.theme.transcriptUsesMonospace)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Editable per-model prices (USD per million tokens). Rows cover every model
/// seen in the index plus the embedded defaults; edits persist as overrides.
private struct PricingSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var rows: [ModelPriceRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tarifs en USD par million de tokens. Les modifications s'appliquent immédiatement à tous les coûts affichés (rien n'est réindexé).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Table($rows) {
                TableColumn("Modèle") { $row in
                    Text(row.model) + (row.isCustom ? Text(" •").foregroundStyle(.orange) : Text(""))
                }
                .width(min: 150, ideal: 190)
                TableColumn("Entrée") { $row in
                    priceField($row.inputPerMTok, row: row)
                }
                TableColumn("Sortie") { $row in
                    priceField($row.outputPerMTok, row: row)
                }
                TableColumn("Cache lu") { $row in
                    priceField($row.cacheReadPerMTok, row: row)
                }
                TableColumn("Cache écrit") { $row in
                    priceField($row.cacheWritePerMTok, row: row)
                }
            }
            HStack {
                Button("Rétablir les tarifs par défaut", role: .destructive) {
                    resetAll()
                }
                Spacer()
                Text("• = tarif personnalisé").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear(perform: reload)
    }

    private func priceField(_ value: Binding<Double>, row: ModelPriceRow) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0...4)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .onSubmit { save(row.model) }
    }

    private func reload() {
        guard let db = appState.database else { return }
        let overrides = (try? db.dbQueue.read { try ModelPriceRow.fetchAll($0) }) ?? []
        let overrideMap = Dictionary(uniqueKeysWithValues: overrides.map { ($0.model, $0) })

        // Models actually seen in the index
        let seen: [String] = (try? db.dbQueue.read { dbq in
            try String.fetchAll(dbq, sql:
                "SELECT DISTINCT model FROM message WHERE model IS NOT NULL ORDER BY model")
        }) ?? []

        var all = Set(seen)
        all.formUnion(PricingEngine.defaultPrices.keys)
        all.formUnion(overrideMap.keys)

        rows = all.sorted().map { model in
            if let o = overrideMap[model] { return o }
            let p = appState.pricing.price(forModel: model)
            return ModelPriceRow(model: model,
                                 inputPerMTok: p.inputPerMTok,
                                 outputPerMTok: p.outputPerMTok,
                                 cacheReadPerMTok: p.cacheReadPerMTok,
                                 cacheWritePerMTok: p.cacheWritePerMTok,
                                 isCustom: false)
        }
    }

    private func save(_ model: String) {
        guard let db = appState.database,
              var row = rows.first(where: { $0.model == model }) else { return }
        row.isCustom = true
        try? db.dbQueue.write { try row.save($0) }
        appState.reloadPricing()
        reload()
    }

    private func resetAll() {
        guard let db = appState.database else { return }
        try? db.dbQueue.write { _ = try ModelPriceRow.deleteAll($0) }
        appState.reloadPricing()
        reload()
    }
}

private struct BudgetSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Seuils (USD, 0 = désactivé)") {
                TextField("Budget mensuel",
                          value: $appState.budget.monthlyLimitUSD,
                          format: .number.precision(.fractionLength(0...2)))
                TextField("Budget quotidien",
                          value: $appState.budget.dailyLimitUSD,
                          format: .number.precision(.fractionLength(0...2)))
            }
            Section {
                Text("Le widget « Budget mensuel » du dashboard passe en rouge au-delà de 90 % du seuil.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct DataSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmResync = false

    var body: some View {
        Form {
            LabeledContent("Source", value: Indexer.defaultRoot.path)
            if let last = appState.lastSync {
                LabeledContent("Dernière synchronisation",
                               value: Format.dateTime.string(from: last))
            }
            LabeledContent("Base locale") {
                Text("~/Library/Application Support/ClaudeView/")
            }
            Section {
                Button("Resynchroniser tout l'index…") { confirmResync = true }
                    .disabled(appState.isIndexing)
                if appState.isIndexing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Indexation en cours…").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Reconstruire l'index complet ?",
            isPresented: $confirmResync) {
            Button("Resynchroniser", role: .destructive) { appState.fullResync() }
        } message: {
            Text("L'index SQLite est vidé puis reconstruit depuis les fichiers JSONL. Les réglages et tarifs sont conservés.")
        }
    }
}
