import XCTest
@testable import MahjongAssistant

final class MahjongEngineTests: XCTestCase {
    private let engine = MahjongEngine()

    func testStandardCompleteHand() {
        let counts = parse("123m123p123s111z22z")
        XCTAssertEqual(engine.shanten(concealedCounts: counts), -1)
    }

    func testStandardTenpaiWaitsForPair() {
        let counts = parse("123m123p123s111z2z")
        XCTAssertEqual(engine.shanten(concealedCounts: counts), 0)
        let waits = engine.effectiveTiles(
            concealedCounts: counts,
            melds: [],
            seenCounts: Array(repeating: 0, count: 34),
            rules: .localDefault
        )
        XCTAssertEqual(waits.map(\.tile.code), ["2z"])
        XCTAssertEqual(waits.first?.remaining, 3)
    }

    func testSevenPairsTenpaiCanBeDisabled() {
        let counts = parse("1122m3344p5566s7z")
        XCTAssertEqual(engine.shanten(concealedCounts: counts), 0)
        var rules = RuleSettings.localDefault
        rules.allowSevenPairs = false
        XCTAssertGreaterThan(engine.shanten(concealedCounts: counts, rules: rules), 0)
    }

    func testThirteenOrphansTenpai() {
        let counts = parse("19m19p19s1234567z")
        XCTAssertEqual(engine.shanten(concealedCounts: counts), 0)
    }

    func testOpenMeldCountsAsOneCompletedGroup() {
        let counts = parse("123m123p123s22z")
        XCTAssertEqual(
            engine.shanten(
                concealedCounts: counts,
                openMeldCount: 1,
                rules: .localDefault
            ),
            -1
        )
    }

    func testDiscardSuggestionsPreserveFourMeldTenpai() {
        let counts = parse("123456789m123p12z")
        let suggestions = engine.discardSuggestions(
            concealedCounts: counts,
            melds: [],
            seenCounts: Array(repeating: 0, count: 34),
            rules: .localDefault
        )
        XCTAssertEqual(suggestions.first?.shanten, 0)
        XCTAssertTrue(Set(suggestions.prefix(2).map(\.tile.code)).isSubset(of: Set(["1z", "2z"])))
    }

    func testWinRequiresReady() {
        let hand = parse("123m123p123s111z2z")
        let incoming = MahjongTile.parse("2z")!
        let blocked = engine.opportunities(
            for: incoming,
            concealedCounts: hand,
            melds: [],
            seenCounts: Array(repeating: 0, count: 34),
            isReady: false,
            rules: .localDefault
        )
        XCTAssertEqual(blocked.first(where: { $0.kind == .win })?.recommended, false)

        let allowed = engine.opportunities(
            for: incoming,
            concealedCounts: hand,
            melds: [],
            seenCounts: Array(repeating: 0, count: 34),
            isReady: true,
            rules: .localDefault
        )
        XCTAssertEqual(allowed.first(where: { $0.kind == .win })?.recommended, true)
    }

    func testDefaultRulesMatchRequestedLocalRules() {
        let rules = RuleSettings.localDefault
        XCTAssertFalse(rules.allowChi)
        XCTAssertTrue(rules.allowPon)
        XCTAssertTrue(rules.allowKan)
        XCTAssertTrue(rules.winRequiresReady)
    }

    func testDefaultActionsIncludeKanButNeverChi() {
        let hand = parse("333m456789p123s1z")
        let incoming = MahjongTile.parse("3m")!
        let actions = engine.opportunities(
            for: incoming,
            concealedCounts: hand,
            melds: [],
            seenCounts: Array(repeating: 0, count: 34),
            isReady: false,
            rules: .localDefault
        )
        XCTAssertNotNil(actions.first(where: { $0.kind == .kan }))
        XCTAssertNil(actions.first(where: { $0.kind == .chi }))
    }

    func testOnDeviceModelLabelsMapToLocalTiles() {
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "1C")?.code, "1m")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "9D")?.code, "9p")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "5B")?.code, "5s")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "EW")?.code, "1z")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "SW")?.code, "2z")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "WW")?.code, "3z")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "NW")?.code, "4z")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "WD")?.code, "5z")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "GD")?.code, "6z")
        XCTAssertEqual(OnDeviceMahjongDetector.tile(for: "RD")?.code, "7z")
        XCTAssertNil(OnDeviceMahjongDetector.tile(for: "1F"))
        XCTAssertNil(OnDeviceMahjongDetector.tile(for: "1S"))
    }

    private func parse(_ notation: String) -> [Int] {
        var counts = Array(repeating: 0, count: 34)
        var digits: [Character] = []
        for character in notation {
            if character.isNumber {
                digits.append(character)
            } else {
                for digit in digits {
                    guard let tile = MahjongTile.parse("\(digit)\(character)") else {
                        XCTFail("Invalid tile notation")
                        continue
                    }
                    counts[tile.index] += 1
                }
                digits = []
            }
        }
        return counts
    }
}
