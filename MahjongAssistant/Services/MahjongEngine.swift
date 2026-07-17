import Foundation

struct MahjongEngine {
    func shanten(
        concealedCounts: [Int],
        openMeldCount: Int = 0,
        rules: RuleSettings = .localDefault
    ) -> Int {
        guard concealedCounts.count == 34 else { return 99 }

        var best = standardShanten(counts: concealedCounts, openMeldCount: openMeldCount)
        if openMeldCount == 0, rules.allowSevenPairs {
            best = min(best, sevenPairsShanten(counts: concealedCounts))
        }
        if openMeldCount == 0, rules.allowThirteenOrphans {
            best = min(best, thirteenOrphansShanten(counts: concealedCounts))
        }
        return best
    }

    func isComplete(
        concealedCounts: [Int],
        openMeldCount: Int = 0,
        rules: RuleSettings = .localDefault
    ) -> Bool {
        shanten(concealedCounts: concealedCounts, openMeldCount: openMeldCount, rules: rules) == -1
    }

    func effectiveTiles(
        concealedCounts: [Int],
        melds: [Meld],
        seenCounts: [Int],
        rules: RuleSettings
    ) -> [EffectiveTile] {
        let current = shanten(concealedCounts: concealedCounts, openMeldCount: melds.count, rules: rules)
        let meldCounts = melds.flatMap(\.tiles).tileCounts
        var result: [EffectiveTile] = []

        for index in 0..<34 {
            let unavailable = concealedCounts[index] + meldCounts[index] + seenCounts[safe: index, or: 0]
            guard unavailable < 4 else { continue }
            var next = concealedCounts
            next[index] += 1
            let nextShanten = shanten(concealedCounts: next, openMeldCount: melds.count, rules: rules)
            if nextShanten < current {
                result.append(
                    EffectiveTile(
                        tile: MahjongTile(index: index),
                        remaining: 4 - unavailable,
                        resultingShanten: nextShanten
                    )
                )
            }
        }
        return result.sorted {
            if $0.remaining != $1.remaining { return $0.remaining > $1.remaining }
            return $0.tile < $1.tile
        }
    }

    func discardSuggestions(
        concealedCounts: [Int],
        melds: [Meld],
        seenCounts: [Int],
        rules: RuleSettings
    ) -> [DiscardSuggestion] {
        let forecastDraws = 8
        let meldCounts = melds.flatMap(\.tiles).tileCounts
        var result: [DiscardSuggestion] = []
        for index in 0..<34 where concealedCounts[index] > 0 {
            var next = concealedCounts
            next[index] -= 1
            var projectedSeenCounts = seenCounts
            if projectedSeenCounts.count < 34 {
                projectedSeenCounts.append(
                    contentsOf: Array(repeating: 0, count: 34 - projectedSeenCounts.count)
                )
            }
            projectedSeenCounts[index] += 1
            let effective = effectiveTiles(
                concealedCounts: next,
                melds: melds,
                seenCounts: projectedSeenCounts,
                rules: rules
            )
            let nextShanten = shanten(
                concealedCounts: next,
                openMeldCount: melds.count,
                rules: rules
            )
            let totalUnknown = (0..<34).reduce(0) { partial, tileIndex in
                let known = next[tileIndex]
                    + meldCounts[tileIndex]
                    + projectedSeenCounts[safe: tileIndex, or: 0]
                return partial + max(0, 4 - known)
            }
            let effectiveCount = effective.reduce(0) { $0 + $1.remaining }
            let winProbability = estimatedWinProbability(
                shanten: nextShanten,
                effectiveCount: effectiveCount,
                totalUnknown: totalUnknown,
                forecastDraws: forecastDraws
            )
            result.append(
                DiscardSuggestion(
                    tile: MahjongTile(index: index),
                    shanten: nextShanten,
                    effectiveTiles: effective,
                    winProbability: winProbability,
                    forecastDraws: forecastDraws,
                    shouldDeclareReady: rules.winRequiresReady
                        && nextShanten == 0
                        && effectiveCount > 0
                )
            )
        }
        return result.sorted {
            if abs($0.winProbability - $1.winProbability) > 0.000_001 {
                return $0.winProbability > $1.winProbability
            }
            if $0.shanten != $1.shanten { return $0.shanten < $1.shanten }
            if $0.effectiveCount != $1.effectiveCount { return $0.effectiveCount > $1.effectiveCount }
            return $0.tile < $1.tile
        }
    }

    func opportunities(
        for incoming: MahjongTile,
        concealedCounts: [Int],
        melds: [Meld],
        seenCounts: [Int],
        isReady: Bool,
        rules: RuleSettings
    ) -> [Opportunity] {
        var result: [Opportunity] = []
        var withIncoming = concealedCounts
        guard withIncoming[incoming.index] < 4 else { return result }
        withIncoming[incoming.index] += 1

        let complete = isComplete(
            concealedCounts: withIncoming,
            openMeldCount: melds.count,
            rules: rules
        )
        if complete {
            let mayWin = !rules.winRequiresReady || isReady
            result.append(
                Opportunity(
                    kind: .win,
                    incoming: incoming,
                    usedTiles: [incoming],
                    explanation: mayWin ? "手牌已成牌，可以胡。" : "牌型已成，但当前规则要求先报听。",
                    recommended: mayWin
                )
            )
        }

        let currentShanten = shanten(
            concealedCounts: concealedCounts,
            openMeldCount: melds.count,
            rules: rules
        )

        if rules.allowKan, concealedCounts[incoming.index] >= 3 {
            result.append(
                Opportunity(
                    kind: .kan,
                    incoming: incoming,
                    usedTiles: Array(repeating: incoming, count: 3),
                    explanation: "手中有三张同牌，按“全程可杠”规则可明杠。",
                    recommended: true
                )
            )
        }

        if rules.allowPon, concealedCounts[incoming.index] >= 2 {
            var afterPon = concealedCounts
            afterPon[incoming.index] -= 2
            let afterShanten = bestShantenAfterRequiredDiscard(
                concealedCounts: afterPon,
                openMeldCount: melds.count + 1,
                rules: rules
            )
            let useful = afterShanten <= currentShanten
            result.append(
                Opportunity(
                    kind: .pon,
                    incoming: incoming,
                    usedTiles: Array(repeating: incoming, count: 2),
                    explanation: useful ? "碰后不增加向听数。" : "可以碰，但会降低当前牌效。",
                    recommended: !rules.onlyRecommendUsefulPon || useful
                )
            )
        }

        if rules.allowChi, incoming.suit != .honors {
            for pair in chiPairs(for: incoming) where pair.allSatisfy({ concealedCounts[$0.index] > 0 }) {
                var afterChi = concealedCounts
                pair.forEach { afterChi[$0.index] -= 1 }
                let afterShanten = bestShantenAfterRequiredDiscard(
                    concealedCounts: afterChi,
                    openMeldCount: melds.count + 1,
                    rules: rules
                )
                result.append(
                    Opportunity(
                        kind: .chi,
                        incoming: incoming,
                        usedTiles: pair,
                        explanation: "吃后向听数为 \(displayShanten(afterShanten))。",
                        recommended: afterShanten <= currentShanten
                    )
                )
            }
        }
        return result.sorted {
            if $0.recommended != $1.recommended { return $0.recommended && !$1.recommended }
            return actionPriority($0.kind) < actionPriority($1.kind)
        }
    }

    func concealedKanTiles(concealedCounts: [Int], rules: RuleSettings) -> [MahjongTile] {
        guard rules.allowKan else { return [] }
        return (0..<34).filter { concealedCounts[$0] == 4 }.map(MahjongTile.init(index:))
    }

    private func standardShanten(counts: [Int], openMeldCount: Int) -> Int {
        var mutableCounts = counts
        var minimum = 8
        var visited = Set<String>()

        func search(_ index: Int, _ melds: Int, _ pairs: Int, _ partials: Int) {
            var i = index
            while i < 34, mutableCounts[i] == 0 { i += 1 }

            if i >= 34 {
                let usablePartials = min(partials, max(0, 4 - melds))
                let value = 8 - melds * 2 - usablePartials - min(pairs, 1)
                minimum = min(minimum, value)
                return
            }

            let key = "\(i)|\(melds)|\(pairs)|\(partials)|\(mutableCounts.map(String.init).joined())"
            guard visited.insert(key).inserted else { return }

            if melds < 4, mutableCounts[i] >= 3 {
                mutableCounts[i] -= 3
                search(i, melds + 1, pairs, partials)
                mutableCounts[i] += 3
            }

            if melds < 4, i < 27, i % 9 <= 6,
               mutableCounts[i + 1] > 0, mutableCounts[i + 2] > 0 {
                mutableCounts[i] -= 1
                mutableCounts[i + 1] -= 1
                mutableCounts[i + 2] -= 1
                search(i, melds + 1, pairs, partials)
                mutableCounts[i] += 1
                mutableCounts[i + 1] += 1
                mutableCounts[i + 2] += 1
            }

            if mutableCounts[i] >= 2 {
                mutableCounts[i] -= 2
                if pairs == 0 {
                    search(i, melds, 1, partials)
                }
                if partials < 4 {
                    search(i, melds, pairs, partials + 1)
                }
                mutableCounts[i] += 2
            }

            if partials < 4, i < 27 {
                if i % 9 <= 7, mutableCounts[i + 1] > 0 {
                    mutableCounts[i] -= 1
                    mutableCounts[i + 1] -= 1
                    search(i, melds, pairs, partials + 1)
                    mutableCounts[i] += 1
                    mutableCounts[i + 1] += 1
                }
                if i % 9 <= 6, mutableCounts[i + 2] > 0 {
                    mutableCounts[i] -= 1
                    mutableCounts[i + 2] -= 1
                    search(i, melds, pairs, partials + 1)
                    mutableCounts[i] += 1
                    mutableCounts[i + 2] += 1
                }
            }

            mutableCounts[i] -= 1
            search(i, melds, pairs, partials)
            mutableCounts[i] += 1
        }

        search(0, openMeldCount, 0, 0)
        return minimum
    }

    private func bestShantenAfterRequiredDiscard(
        concealedCounts: [Int],
        openMeldCount: Int,
        rules: RuleSettings
    ) -> Int {
        var best = 99
        for index in 0..<34 where concealedCounts[index] > 0 {
            var afterDiscard = concealedCounts
            afterDiscard[index] -= 1
            best = min(
                best,
                shanten(
                    concealedCounts: afterDiscard,
                    openMeldCount: openMeldCount,
                    rules: rules
                )
            )
        }
        return best
    }

    private func sevenPairsShanten(counts: [Int]) -> Int {
        let pairCount = counts.filter { $0 >= 2 }.count
        let uniqueCount = counts.filter { $0 > 0 }.count
        return 6 - pairCount + max(0, 7 - uniqueCount)
    }

    private func thirteenOrphansShanten(counts: [Int]) -> Int {
        let required = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
        let uniqueCount = required.filter { counts[$0] > 0 }.count
        let hasPair = required.contains { counts[$0] > 1 }
        return 13 - uniqueCount - (hasPair ? 1 : 0)
    }

    private func chiPairs(for incoming: MahjongTile) -> [[MahjongTile]] {
        let index = incoming.index
        let rankIndex = index % 9
        var result: [[MahjongTile]] = []
        if rankIndex >= 2 {
            result.append([MahjongTile(index: index - 2), MahjongTile(index: index - 1)])
        }
        if rankIndex >= 1, rankIndex <= 7 {
            result.append([MahjongTile(index: index - 1), MahjongTile(index: index + 1)])
        }
        if rankIndex <= 6 {
            result.append([MahjongTile(index: index + 1), MahjongTile(index: index + 2)])
        }
        return result
    }

    private func actionPriority(_ action: OpportunityKind) -> Int {
        switch action {
        case .win: return 0
        case .kan: return 1
        case .pon: return 2
        case .chi: return 3
        }
    }

    private func displayShanten(_ value: Int) -> String {
        value == 0 ? "听牌" : "\(value) 向听"
    }

    /// Uses only the player's known tiles. Tenpai is an exact no-replacement
    /// hit estimate for the forecast window; earlier stages are discounted
    /// because one or more future improvements are still required.
    private func estimatedWinProbability(
        shanten: Int,
        effectiveCount: Int,
        totalUnknown: Int,
        forecastDraws: Int
    ) -> Double {
        guard shanten >= 0, effectiveCount > 0, totalUnknown > 0 else {
            return shanten < 0 ? 1 : 0
        }
        let improvementProbability = hitProbability(
            successCount: effectiveCount,
            totalCount: totalUnknown,
            draws: forecastDraws
        )
        if shanten == 0 {
            return improvementProbability
        }

        let continuationFactor: Double
        switch shanten {
        case 1:
            continuationFactor = 0.42
        case 2:
            continuationFactor = 0.20
        case 3:
            continuationFactor = 0.09
        default:
            continuationFactor = 0.04 * pow(0.55, Double(max(0, shanten - 4)))
        }
        return min(1, improvementProbability * continuationFactor)
    }

    private func hitProbability(
        successCount: Int,
        totalCount: Int,
        draws: Int
    ) -> Double {
        let successes = min(max(0, successCount), totalCount)
        let sampleCount = min(max(0, draws), totalCount)
        guard successes > 0, sampleCount > 0 else { return 0 }

        var missProbability = 1.0
        for drawIndex in 0..<sampleCount {
            let remainingTotal = totalCount - drawIndex
            let remainingMisses = max(0, totalCount - successes - drawIndex)
            guard remainingMisses > 0 else { return 1 }
            missProbability *= Double(remainingMisses) / Double(remainingTotal)
        }
        return max(0, min(1, 1 - missProbability))
    }
}

private extension Array where Element == Int {
    subscript(safe index: Int, or fallback: Int) -> Int {
        indices.contains(index) ? self[index] : fallback
    }
}
