import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published var concealed: [MahjongTile] = []
    @Published var melds: [Meld] = []
    @Published var seenCounts = Array(repeating: 0, count: 34)
    @Published var isReady = false
    @Published var lastIncoming: MahjongTile?
    @Published var opportunities: [Opportunity] = []
    @Published var notice = "先拍照识别或手动录入手牌"
    @Published var serverSuggestion: String?
    @Published var isAnalyzing = false
    @Published var isSessionActive = false
    @Published var connectionStatus = "未测试"

    @Published var rules: RuleSettings {
        didSet { save(rules, key: Keys.rules) }
    }

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Keys.serverURL) }
    }

    let engine = MahjongEngine()
    private let api = APIClient()
    private var sessionID = UUID().uuidString

    init() {
        rules = Self.load(RuleSettings.self, key: Keys.rules) ?? .localDefault
        serverURL = UserDefaults.standard.string(forKey: Keys.serverURL) ?? "http://192.168.1.100:8000"
    }

    var concealedCounts: [Int] { concealed.tileCounts }

    var currentShanten: Int {
        guard !concealed.isEmpty else { return 99 }
        return engine.shanten(
            concealedCounts: concealedCounts,
            openMeldCount: melds.count,
            rules: rules
        )
    }

    var effectiveTiles: [EffectiveTile] {
        engine.effectiveTiles(
            concealedCounts: concealedCounts,
            melds: melds,
            seenCounts: seenCounts,
            rules: rules
        )
    }

    var discardSuggestions: [DiscardSuggestion] {
        guard concealed.count % 3 == 2 else { return [] }
        return engine.discardSuggestions(
            concealedCounts: concealedCounts,
            melds: melds,
            seenCounts: seenCounts,
            rules: rules
        )
    }

    var concealedKanTiles: [MahjongTile] {
        engine.concealedKanTiles(concealedCounts: concealedCounts, rules: rules)
    }

    var addedKanTiles: [MahjongTile] {
        guard rules.allowKan else { return [] }
        let counts = concealedCounts
        return melds.compactMap { meld in
            guard meld.kind == .pon,
                  let tile = meld.tiles.first,
                  counts[tile.index] > 0 else {
                return nil
            }
            return tile
        }
    }

    func unavailableCount(for tile: MahjongTile) -> Int {
        concealedCounts[tile.index]
            + melds.flatMap(\.tiles).tileCounts[tile.index]
            + seenCounts[tile.index]
    }

    func addToHand(_ tile: MahjongTile) {
        guard unavailableCount(for: tile) < 4 else {
            notice = "\(tile.fullName)已经录入四张"
            return
        }
        concealed.append(tile)
        concealed.sort()
        clearTransientAdvice()
        notice = "已加入\(tile.fullName)"
    }

    func removeFromHand(_ tile: MahjongTile) {
        guard let index = concealed.lastIndex(of: tile) else { return }
        concealed.remove(at: index)
        clearTransientAdvice()
        if isReady, currentShanten != 0 {
            isReady = false
        }
        notice = "已移除\(tile.fullName)"
    }

    func discard(_ tile: MahjongTile) {
        guard let index = concealed.lastIndex(of: tile) else { return }
        concealed.remove(at: index)
        seenCounts[tile.index] += 1
        clearTransientAdvice()
        notice = currentShanten == 0 ? "切\(tile.shortName)后听牌，可按规则报听" : "已切\(tile.shortName)"
    }

    func toggleReady() {
        if isReady {
            isReady = false
            notice = "已取消报听"
            return
        }
        guard currentShanten == 0 else {
            notice = "当前还未听牌，不能报听"
            return
        }
        isReady = true
        notice = "已报听；按当前规则，成牌后可以胡"
    }

    func inspectOpponentDiscard(_ tile: MahjongTile) {
        lastIncoming = tile
        opportunities = engine.opportunities(
            for: tile,
            concealedCounts: concealedCounts,
            melds: melds,
            seenCounts: seenCounts,
            isReady: isReady,
            rules: rules
        )
        if opportunities.isEmpty {
            seenCounts[tile.index] += 1
            lastIncoming = nil
            notice = "对方打出\(tile.shortName)：过"
        } else {
            notice = "对方打出\(tile.shortName)，请查看可选动作"
        }
    }

    func commit(_ opportunity: Opportunity) {
        switch opportunity.kind {
        case .win:
            if opportunity.recommended {
                notice = "胡\(opportunity.incoming.shortName)"
            } else {
                notice = opportunity.explanation
            }
        case .pon:
            guard removeCopies(of: opportunity.incoming, count: 2) else { return }
            melds.append(Meld(kind: .pon, tiles: Array(repeating: opportunity.incoming, count: 3)))
            notice = "已记录碰\(opportunity.incoming.shortName)"
        case .kan:
            guard removeCopies(of: opportunity.incoming, count: 3) else { return }
            melds.append(Meld(kind: .kan, tiles: Array(repeating: opportunity.incoming, count: 4)))
            notice = "已记录杠\(opportunity.incoming.shortName)，请补牌"
        case .chi:
            guard opportunity.usedTiles.allSatisfy({ concealed.contains($0) }) else { return }
            for tile in opportunity.usedTiles {
                _ = removeCopies(of: tile, count: 1)
            }
            melds.append(Meld(kind: .chi, tiles: opportunity.usedTiles + [opportunity.incoming]))
            notice = "已记录吃牌"
        }
        lastIncoming = nil
        opportunities = []
    }

    func passIncoming() {
        if let tile = lastIncoming, seenCounts[tile.index] < 4 {
            seenCounts[tile.index] += 1
            notice = "已过\(tile.shortName)"
        }
        lastIncoming = nil
        opportunities = []
    }

    func commitConcealedKan(_ tile: MahjongTile) {
        guard rules.allowKan, removeCopies(of: tile, count: 4) else { return }
        melds.append(Meld(kind: .kan, tiles: Array(repeating: tile, count: 4)))
        clearTransientAdvice()
        notice = "已记录暗杠\(tile.shortName)，请补牌"
    }

    func commitAddedKan(_ tile: MahjongTile) {
        guard rules.allowKan,
              let meldIndex = melds.firstIndex(where: { $0.kind == .pon && $0.tiles.first == tile }),
              removeCopies(of: tile, count: 1) else {
            return
        }
        let original = melds[meldIndex]
        melds[meldIndex] = Meld(
            id: original.id,
            kind: .kan,
            tiles: Array(repeating: tile, count: 4)
        )
        clearTransientAdvice()
        notice = "已记录加杠\(tile.shortName)，请补牌"
    }

    func removeMeld(_ meld: Meld) {
        guard let index = melds.firstIndex(of: meld) else { return }
        melds.remove(at: index)
        for tile in meld.tiles where unavailableCount(for: tile) < 4 {
            concealed.append(tile)
        }
        concealed.sort()
        notice = "已撤销\(meld.kind.title)"
    }

    func clearHand() {
        concealed = []
        melds = []
        seenCounts = Array(repeating: 0, count: 34)
        isReady = false
        serverSuggestion = nil
        clearTransientAdvice()
        notice = "已清空牌局"
    }

    func setRulesPreset(_ preset: RuleSettings) {
        rules = preset
        if !rules.winRequiresReady {
            isReady = false
        }
        clearTransientAdvice()
        notice = "规则已更新"
    }

    func testServer(url: String? = nil) async {
        let target = url ?? serverURL
        connectionStatus = "测试中…"
        do {
            try await api.testConnection(baseURL: target)
            connectionStatus = "连接成功"
        } catch {
            connectionStatus = error.localizedDescription
        }
    }

    func analyzeImage(_ data: Data) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        notice = "正在识别手牌…"
        defer { isAnalyzing = false }

        do {
            if !isSessionActive {
                try await api.startSession(baseURL: serverURL, sessionID: sessionID)
                isSessionActive = true
            }
            let result = try await api.analyze(baseURL: serverURL, sessionID: sessionID, imageData: data)
            let recognizedHand = result.userHand.compactMap(MahjongTile.parse)
            guard !recognizedHand.isEmpty else { throw APIClient.ClientError.noRecognizedTiles }
            let recognizedMelds = inferMelds(from: result.meldedTiles.compactMap(MahjongTile.parse))
            guard isPhysicallyValid(hand: recognizedHand, melds: recognizedMelds) else {
                notice = "识别结果中有同牌超过四张，请手动校正"
                return
            }
            concealed = recognizedHand.sorted()
            melds = recognizedMelds
            isReady = false
            serverSuggestion = result.suggestedPlay
            clearTransientAdvice(keepServerSuggestion: true)
            notice = result.warning ?? "识别完成；请点牌校正后再看建议"
            connectionStatus = "连接成功"
        } catch {
            notice = "\(error.localizedDescription)；仍可手动录牌"
            connectionStatus = error.localizedDescription
        }
    }

    func endSession() async {
        guard isSessionActive else {
            clearHand()
            return
        }
        do {
            try await api.endSession(baseURL: serverURL, sessionID: sessionID)
        } catch {
            notice = "结束远端会话失败，但本地牌局已清空"
        }
        sessionID = UUID().uuidString
        isSessionActive = false
        clearHand()
    }

    private func removeCopies(of tile: MahjongTile, count: Int) -> Bool {
        guard concealed.filter({ $0 == tile }).count >= count else {
            notice = "\(tile.fullName)数量不足"
            return false
        }
        for _ in 0..<count {
            if let index = concealed.lastIndex(of: tile) {
                concealed.remove(at: index)
            }
        }
        return true
    }

    private func clearTransientAdvice(keepServerSuggestion: Bool = false) {
        lastIncoming = nil
        opportunities = []
        if !keepServerSuggestion {
            serverSuggestion = nil
        }
    }

    private func inferMelds(from tiles: [MahjongTile]) -> [Meld] {
        var remaining = tiles.tileCounts
        var result: [Meld] = []

        for index in 0..<34 where remaining[index] >= 3 {
            let count = min(remaining[index], 4)
            let kind: MeldKind = count == 4 ? .kan : .pon
            result.append(Meld(kind: kind, tiles: Array(repeating: MahjongTile(index: index), count: count)))
            remaining[index] -= count
        }

        if rules.allowChi {
            for index in 0..<27 where index % 9 <= 6 {
                while remaining[index] > 0, remaining[index + 1] > 0, remaining[index + 2] > 0 {
                    let sequence = [MahjongTile(index: index), MahjongTile(index: index + 1), MahjongTile(index: index + 2)]
                    result.append(Meld(kind: .chi, tiles: sequence))
                    remaining[index] -= 1
                    remaining[index + 1] -= 1
                    remaining[index + 2] -= 1
                }
            }
        }
        return result
    }

    private func isPhysicallyValid(hand: [MahjongTile], melds: [Meld]) -> Bool {
        let combined = (hand + melds.flatMap(\.tiles)).tileCounts
        return combined.allSatisfy { $0 <= 4 }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let rules = "mahjong.rules.v1"
        static let serverURL = "mahjong.serverURL"
    }
}
