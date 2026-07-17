import SwiftUI

struct TileView: View {
    let tile: MahjongTile
    var compact = false
    var selected = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            Text(tile.symbol)
                .font(.system(size: compact ? 30 : 39))
                .minimumScaleFactor(0.7)
            if !compact {
                Text(tile.shortName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(faceColor)
            }
        }
        .frame(width: compact ? 37 : 48, height: compact ? 48 : 61)
        .background(
            RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                .fill(Color(red: 1, green: 0.99, blue: 0.94))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: selected ? 2 : 0.7)
        )
        .accessibilityLabel(tile.fullName)
    }

    private var faceColor: Color {
        switch tile.suit {
        case .characters: return .red
        case .circles: return .blue
        case .bamboo: return .green
        case .honors:
            return tile.rank == 7 ? .red : (tile.rank == 6 ? .green : .primary)
        }
    }
}

struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
    }
}
