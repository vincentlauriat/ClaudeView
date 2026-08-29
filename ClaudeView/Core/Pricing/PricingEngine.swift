import Foundation
import GRDB

/// Computes costs at query time: tokens × per-MTok prices.
/// Prices come from `modelPrice` (user-editable); unknown models fall back to
/// a family-based default so new model ids still get a sensible estimate.
struct PricingEngine {

    struct Price: Equatable {
        var inputPerMTok: Double
        var outputPerMTok: Double
        var cacheReadPerMTok: Double
        var cacheWritePerMTok: Double
    }

    /// Embedded defaults (USD per million tokens), editable in Settings.
    static let defaultPrices: [String: Price] = [
        "claude-fable-5":  Price(inputPerMTok: 25, outputPerMTok: 125, cacheReadPerMTok: 2.5, cacheWritePerMTok: 31.25),
        "claude-opus-5":   Price(inputPerMTok: 15, outputPerMTok: 75, cacheReadPerMTok: 1.5, cacheWritePerMTok: 18.75),
        "claude-opus-4-1": Price(inputPerMTok: 15, outputPerMTok: 75, cacheReadPerMTok: 1.5, cacheWritePerMTok: 18.75),
        "claude-sonnet-5": Price(inputPerMTok: 3, outputPerMTok: 15, cacheReadPerMTok: 0.3, cacheWritePerMTok: 3.75),
        "claude-sonnet-4-5": Price(inputPerMTok: 3, outputPerMTok: 15, cacheReadPerMTok: 0.3, cacheWritePerMTok: 3.75),
        "claude-haiku-4-5": Price(inputPerMTok: 1, outputPerMTok: 5, cacheReadPerMTok: 0.1, cacheWritePerMTok: 1.25),
    ]

    /// Family fallbacks matched by substring, in order.
    static let familyFallbacks: [(needle: String, price: Price)] = [
        ("fable",  defaultPrices["claude-fable-5"]!),
        ("mythos", defaultPrices["claude-fable-5"]!),
        ("opus",   defaultPrices["claude-opus-5"]!),
        ("sonnet", defaultPrices["claude-sonnet-5"]!),
        ("haiku",  defaultPrices["claude-haiku-4-5"]!),
    ]

    private(set) var prices: [String: Price]

    init(prices: [String: Price] = PricingEngine.defaultPrices) {
        self.prices = prices
    }

    /// Loads defaults merged with user overrides from the database.
    static func load(from db: AppDatabase) -> PricingEngine {
        var merged = defaultPrices
        if let rows = try? db.dbQueue.read({ try ModelPriceRow.fetchAll($0) }) {
            for row in rows {
                merged[row.model] = Price(
                    inputPerMTok: row.inputPerMTok,
                    outputPerMTok: row.outputPerMTok,
                    cacheReadPerMTok: row.cacheReadPerMTok,
                    cacheWritePerMTok: row.cacheWritePerMTok
                )
            }
        }
        return PricingEngine(prices: merged)
    }

    func price(forModel model: String) -> Price {
        if let p = prices[model] { return p }
        let lower = model.lowercased()
        // Exact-prefix match first (versioned ids like claude-sonnet-5-20260101)
        if let (_, p) = prices.first(where: { lower.hasPrefix($0.key) }) { return p }
        if let fallback = Self.familyFallbacks.first(where: { lower.contains($0.needle) }) {
            return fallback.price
        }
        return Price(inputPerMTok: 0, outputPerMTok: 0, cacheReadPerMTok: 0, cacheWritePerMTok: 0)
    }

    func cost(model: String?, usage: TokenUsage) -> Double {
        guard let model, !model.isEmpty else { return 0 }
        let p = price(forModel: model)
        return (Double(usage.input) * p.inputPerMTok
              + Double(usage.output) * p.outputPerMTok
              + Double(usage.cacheRead) * p.cacheReadPerMTok
              + Double(usage.cacheCreation) * p.cacheWritePerMTok) / 1_000_000
    }

    func cost(model: String?, input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Double {
        cost(model: model, usage: TokenUsage(
            input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation))
    }
}
