import Foundation

enum TileSuit: String, CaseIterable, Codable {
    case characters
    case circles
    case bamboo
    case honors

    var title: String {
        switch self {
        case .characters: return "万"
        case .circles: return "筒"
        case .bamboo: return "条"
        case .honors: return "字"
        }
    }
}

struct MahjongTile: Identifiable, Hashable, Codable, Comparable {
    let index: Int

    var id: Int { index }

    var suit: TileSuit {
        switch index {
        case 0..<9: return .characters
        case 9..<18: return .circles
        case 18..<27: return .bamboo
        default: return .honors
        }
    }

    var rank: Int {
        switch suit {
        case .characters: return index + 1
        case .circles: return index - 8
        case .bamboo: return index - 17
        case .honors: return index - 26
        }
    }

    var code: String {
        switch suit {
        case .characters: return "\(rank)m"
        case .circles: return "\(rank)p"
        case .bamboo: return "\(rank)s"
        case .honors: return "\(rank)z"
        }
    }

    var shortName: String {
        if suit == .honors {
            return ["东", "南", "西", "北", "白", "发", "中"][rank - 1]
        }
        return "\(rank)\(suit.title)"
    }

    var fullName: String {
        let numberNames = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if suit == .honors {
            return ["东风", "南风", "西风", "北风", "白板", "发财", "红中"][rank - 1]
        }
        return "\(numberNames[rank - 1])\(suit.title)"
    }

    var symbol: String {
        let scalar: Int
        switch suit {
        case .characters:
            scalar = 0x1F007 + rank - 1
        case .bamboo:
            scalar = 0x1F010 + rank - 1
        case .circles:
            scalar = 0x1F019 + rank - 1
        case .honors:
            let honorScalars = [0x1F000, 0x1F001, 0x1F002, 0x1F003, 0x1F006, 0x1F005, 0x1F004]
            scalar = honorScalars[rank - 1]
        }
        guard let value = UnicodeScalar(scalar) else { return shortName }
        return String(value)
    }

    var isTerminalOrHonor: Bool {
        suit == .honors || rank == 1 || rank == 9
    }

    static let all: [MahjongTile] = (0..<34).map(MahjongTile.init(index:))

    static func tiles(in suit: TileSuit) -> [MahjongTile] {
        all.filter { $0.suit == suit }
    }

    static func parse(_ rawCode: String) -> MahjongTile? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count >= 2, let number = Int(String(code.dropLast())) else { return nil }
        let suffix = code.last
        switch suffix {
        case "m" where (1...9).contains(number):
            return MahjongTile(index: number - 1)
        case "p" where (1...9).contains(number):
            return MahjongTile(index: 9 + number - 1)
        case "s" where (1...9).contains(number):
            return MahjongTile(index: 18 + number - 1)
        case "z" where (1...7).contains(number):
            return MahjongTile(index: 27 + number - 1)
        default:
            return nil
        }
    }

    static func < (lhs: MahjongTile, rhs: MahjongTile) -> Bool {
        lhs.index < rhs.index
    }
}

extension Array where Element == MahjongTile {
    var tileCounts: [Int] {
        reduce(into: Array(repeating: 0, count: 34)) { result, tile in
            guard result.indices.contains(tile.index) else { return }
            result[tile.index] += 1
        }
    }
}
