import Foundation

struct RuleSettings: Codable, Equatable {
    var allowChi: Bool
    var allowPon: Bool
    var allowKan: Bool
    var winRequiresReady: Bool
    var allowSevenPairs: Bool
    var allowThirteenOrphans: Bool
    var onlyRecommendUsefulPon: Bool

    static let localDefault = RuleSettings(
        allowChi: false,
        allowPon: true,
        allowKan: true,
        winRequiresReady: true,
        allowSevenPairs: true,
        allowThirteenOrphans: true,
        onlyRecommendUsefulPon: true
    )

    static let common = RuleSettings(
        allowChi: true,
        allowPon: true,
        allowKan: true,
        winRequiresReady: false,
        allowSevenPairs: true,
        allowThirteenOrphans: true,
        onlyRecommendUsefulPon: true
    )

    var summary: String {
        var parts = [allowChi ? "可吃" : "禁吃", allowPon ? "可碰" : "禁碰", allowKan ? "可杠" : "禁杠"]
        parts.append(winRequiresReady ? "报听后可胡" : "成牌即可胡")
        return parts.joined(separator: " · ")
    }
}

