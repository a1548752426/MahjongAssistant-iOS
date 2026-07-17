import Foundation

enum MeldKind: String, Codable, CaseIterable {
    case chi
    case pon
    case kan

    var title: String {
        switch self {
        case .chi: return "吃"
        case .pon: return "碰"
        case .kan: return "杠"
        }
    }
}

struct Meld: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: MeldKind
    let tiles: [MahjongTile]

    init(id: UUID = UUID(), kind: MeldKind, tiles: [MahjongTile]) {
        self.id = id
        self.kind = kind
        self.tiles = tiles.sorted()
    }
}

struct EffectiveTile: Identifiable, Hashable {
    let tile: MahjongTile
    let remaining: Int
    let resultingShanten: Int

    var id: Int { tile.index }
}

struct DiscardSuggestion: Identifiable, Hashable {
    let tile: MahjongTile
    let shanten: Int
    let effectiveTiles: [EffectiveTile]

    var id: Int { tile.index }
    var effectiveCount: Int { effectiveTiles.reduce(0) { $0 + $1.remaining } }
}

enum OpportunityKind: String, Hashable {
    case win
    case pon
    case kan
    case chi

    var title: String {
        switch self {
        case .win: return "胡"
        case .pon: return "碰"
        case .kan: return "杠"
        case .chi: return "吃"
        }
    }
}

struct Opportunity: Identifiable, Hashable {
    let kind: OpportunityKind
    let incoming: MahjongTile
    let usedTiles: [MahjongTile]
    let explanation: String
    let recommended: Bool

    var id: String {
        "\(kind.rawValue)-\(incoming.index)-\(usedTiles.map { String($0.index) }.joined(separator: "-"))"
    }
}

struct AnalyzeResponse: Decodable {
    let userHand: [String]
    let meldedTiles: [String]
    let suggestedPlay: String
    let annotatedImagePath: String?
    let actionDetected: String?
    let warning: String?
    let isStable: Bool?

    enum CodingKeys: String, CodingKey {
        case userHand = "user_hand"
        case meldedTiles = "melded_tiles"
        case suggestedPlay = "suggested_play"
        case annotatedImagePath = "annotated_image_path"
        case actionDetected = "action_detected"
        case warning
        case isStable = "is_stable"
    }
}

struct StatusResponse: Decodable {
    let status: String
    let sessionID: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sessionID = "session_id"
        case message
    }
}

enum GameInputMode {
    case addToHand
    case opponentDiscard
}
