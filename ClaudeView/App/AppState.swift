import Foundation
import SwiftUI

/// Rolling buffer of live-ingested events feeding the "sniffer" view.
@MainActor
final class LiveFeedModel: ObservableObject {
    @Published private(set) var events: [LiveEvent] = []
    @Published var paused = false
    private var pendingWhilePaused: [LiveEvent] = []
    private let maxEvents = 2000

    func append(_ event: LiveEvent) {
        if paused {
            pendingWhilePaused.append(event)
            return
        }
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func resume() {
        paused = false
        for e in pendingWhilePaused { append(e) }
        pendingWhilePaused.removeAll()
    }

    func clear() {
        events.removeAll()
        pendingWhilePaused.removeAll()
    }
}

/// App-wide state: database, indexer, watcher, pricing, and every persisted
/// customization (theme, dashboard layout, budget, saved views).
@MainActor
final class AppState: ObservableObject {
    @Published var theme = Theme() { didSet { persist(SettingsKeys.theme, theme) } }
    @Published var dashboardLayout = WidgetConfig.defaultLayout {
        didSet { persist(SettingsKeys.dashboardLayout, dashboardLayout) }
    }
    @Published var budget = Budget() { didSet { persist(SettingsKeys.budget, budget) } }
    @Published var savedViews: [SavedView] = [] {
        didSet { persist(SettingsKeys.savedViews, savedViews) }
    }

    @Published private(set) var isIndexing = false
    @Published private(set) var lastSync: Date?
    /// Incremented after every ingestion pass; views observe it to refresh queries.
    @Published private(set) var dataVersion = 0
    @Published private(set) var loadError: String?

    let liveFeed = LiveFeedModel()

    private(set) var database: AppDatabase?
    private(set) var pricing = PricingEngine()
    private var indexer: Indexer?
    private var watcher: LiveWatcher?
    private let indexQueue = DispatchQueue(label: "fr.lauriat.ClaudeView.indexer", qos: .userInitiated)
    private var restoringSettings = false

    init() {
        do {
            let db = try AppDatabase.makeDefault()
            bootstrap(database: db, rootURL: Indexer.defaultRoot)
        } catch {
            loadError = "Impossible d'ouvrir la base locale : \(error.localizedDescription)"
        }
    }

    /// Test/preview entry point.
    init(database: AppDatabase, rootURL: URL) {
        bootstrap(database: database, rootURL: rootURL)
    }

    private func bootstrap(database db: AppDatabase, rootURL: URL) {
        self.database = db
        restoreSettings(from: db)
        self.pricing = PricingEngine.load(from: db)

        let indexer = Indexer(database: db, rootURL: rootURL)
        self.indexer = indexer
        indexer.onLiveEvent = { [weak self] event in
            Task { @MainActor in self?.liveFeed.append(event) }
        }

        startInitialSync()

        let watcher = LiveWatcher(rootPath: rootURL.path) { [weak self] urls in
            self?.ingestOnQueue(urls: urls)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func restoreSettings(from db: AppDatabase) {
        restoringSettings = true
        defer { restoringSettings = false }
        if let t = db.readSetting(SettingsKeys.theme, as: Theme.self) { theme = t }
        if let l = db.readSetting(SettingsKeys.dashboardLayout, as: [WidgetConfig].self) {
            dashboardLayout = l
        }
        if let b = db.readSetting(SettingsKeys.budget, as: Budget.self) { budget = b }
        if let v = db.readSetting(SettingsKeys.savedViews, as: [SavedView].self) { savedViews = v }
    }

    private func persist<T: Encodable>(_ key: String, _ value: T) {
        guard !restoringSettings else { return }
        database?.writeSetting(key, value: value)
    }

    // MARK: - Indexing

    private func startInitialSync() {
        guard let indexer else { return }
        isIndexing = true
        indexQueue.async { [weak self] in
            try? indexer.syncAll()
            Task { @MainActor in
                guard let self else { return }
                self.isIndexing = false
                self.lastSync = Date()
                self.dataVersion += 1
            }
        }
    }

    private func ingestOnQueue(urls: [URL]) {
        guard let indexer else { return }
        indexQueue.async { [weak self] in
            var newCount = 0
            for url in urls {
                newCount += (try? indexer.ingest(fileURL: url)) ?? 0
            }
            if newCount > 0 {
                Task { @MainActor in
                    guard let self else { return }
                    self.lastSync = Date()
                    self.dataVersion += 1
                }
            }
        }
    }

    func fullResync() {
        guard let database, let indexer else { return }
        isIndexing = true
        liveFeed.clear()
        indexQueue.async { [weak self] in
            try? database.clearIndex()
            try? indexer.syncAll()
            Task { @MainActor in
                guard let self else { return }
                self.isIndexing = false
                self.lastSync = Date()
                self.dataVersion += 1
            }
        }
    }

    // MARK: - Pricing

    var analytics: AnalyticsStore? {
        guard let database else { return nil }
        return AnalyticsStore(database: database, pricing: pricing)
    }

    func reloadPricing() {
        guard let database else { return }
        pricing = PricingEngine.load(from: database)
        dataVersion += 1
    }
}
