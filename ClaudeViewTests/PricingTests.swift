import XCTest
@testable import ClaudeView

final class PricingTests: XCTestCase {

    func testExactModelPrice() {
        let engine = PricingEngine()
        let usage = TokenUsage(input: 1_000_000, output: 0, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(engine.cost(model: "claude-sonnet-5", usage: usage), 3.0, accuracy: 0.001)
    }

    func testCacheAwareCost() {
        let engine = PricingEngine()
        // 1M cache read on sonnet-5 = $0.30 ; 1M cache write = $3.75
        let usage = TokenUsage(input: 0, output: 0, cacheRead: 1_000_000, cacheCreation: 1_000_000)
        XCTAssertEqual(engine.cost(model: "claude-sonnet-5", usage: usage), 4.05, accuracy: 0.001)
    }

    func testVersionedModelIdMatchesPrefix() {
        let engine = PricingEngine()
        let usage = TokenUsage(input: 0, output: 1_000_000, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(engine.cost(model: "claude-haiku-4-5-20251001", usage: usage),
                       5.0, accuracy: 0.001)
    }

    func testUnknownFamilyMemberUsesFamilyRate() {
        let engine = PricingEngine()
        let usage = TokenUsage(input: 1_000_000, output: 0, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(engine.cost(model: "claude-opus-9-experimental", usage: usage),
                       15.0, accuracy: 0.001)
    }

    func testUnknownModelCostsZero() {
        let engine = PricingEngine()
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(engine.cost(model: "gpt-12", usage: usage), 0)
        XCTAssertEqual(engine.cost(model: nil, usage: usage), 0)
    }

    func testOverrideWins() {
        var prices = PricingEngine.defaultPrices
        prices["claude-sonnet-5"] = PricingEngine.Price(
            inputPerMTok: 1, outputPerMTok: 2, cacheReadPerMTok: 0, cacheWritePerMTok: 0)
        let engine = PricingEngine(prices: prices)
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(engine.cost(model: "claude-sonnet-5", usage: usage), 3.0, accuracy: 0.001)
    }
}
