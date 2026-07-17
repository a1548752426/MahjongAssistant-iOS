import SwiftUI

struct TilePickerView: View {
    let title: String
    let dismissAfterSelection: Bool
    let unavailableCount: (MahjongTile) -> Int
    let onSelect: (MahjongTile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(TileSuit.allCases, id: \.self) { suit in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(suit.title)
                                .font(.headline)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: suit == .honors ? 7 : 9),
                                spacing: 10
                            ) {
                                ForEach(MahjongTile.tiles(in: suit)) { tile in
                                    Button {
                                        onSelect(tile)
                                        if dismissAfterSelection { dismiss() }
                                    } label: {
                                        ZStack(alignment: .topTrailing) {
                                            TileView(tile: tile, compact: true)
                                            Text("\(unavailableCount(tile))")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.white)
                                                .frame(width: 17, height: 17)
                                                .background(unavailableCount(tile) >= 4 ? Color.red : Color.accentColor)
                                                .clipShape(Circle())
                                                .offset(x: 5, y: -5)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(unavailableCount(tile) >= 4)
                                    .opacity(unavailableCount(tile) >= 4 ? 0.35 : 1)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

