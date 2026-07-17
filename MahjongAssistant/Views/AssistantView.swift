import PhotosUI
import SwiftUI
import UIKit

struct AssistantView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showTilePicker = false
    @State private var inputMode: GameInputMode = .addToHand
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    captureCard
                    handCard
                    adviceCard
                    if !store.opportunities.isEmpty {
                        opportunityCard
                    }
                    if let serverSuggestion = store.serverSuggestion, !serverSuggestion.isEmpty {
                        serverAdviceCard(serverSuggestion)
                    }
                }
                .padding(16)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.97, blue: 0.94),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("听牌助手")
            .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            store.clearHand()
                        } label: {
                            Label("清空牌局", systemImage: "trash")
                        }
                        Button {
                            Task { await store.endSession() }
                        } label: {
                            Label("结束会话", systemImage: "stop.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showTilePicker) {
                TilePickerView(
                    title: inputMode == .addToHand ? "手动录牌" : "对方打出的牌",
                    dismissAfterSelection: inputMode == .opponentDiscard,
                    unavailableCount: { store.unavailableCount(for: $0) },
                    onSelect: { tile in
                        switch inputMode {
                        case .addToHand:
                            store.addToHand(tile)
                        case .opponentDiscard:
                            store.inspectOpponentDiscard(tile)
                        }
                    }
                )
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { data in
                    Task { await store.analyzeImage(data) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { item in
                guard let selectedItem = item else { return }
                Task {
                    do {
                        let loadedData = try await selectedItem.loadTransferable(type: Data.self)
                        if let data = loadedData {
                            await store.analyzeImage(data)
                        } else {
                            store.notice = "无法读取这张照片"
                        }
                    } catch {
                        store.notice = "无法读取这张照片"
                    }
                    photoItem = nil
                }
            }
        }
    }

    private var statusCard: some View {
        let shanten = store.currentShanten
        return SurfaceCard {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 74, height: 74)
                    VStack(spacing: 0) {
                        Text(statusPrimary(shanten))
                            .font(.title2.bold())
                            .foregroundStyle(statusColor)
                        Text(statusSecondary(shanten))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.rules.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)
                    Text(store.notice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if store.rules.winRequiresReady {
                            Button(store.isReady ? "已报听" : "报听") {
                                store.toggleReady()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!store.isReady && shanten != 0)
                        } else {
                            Label("无需报听", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("手牌 \(store.concealed.count) · 副露 \(store.melds.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var captureCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("识别与录入", systemImage: "camera.viewfinder")
                    .font(.headline)
                HStack(spacing: 10) {
                    Button {
                        showCamera = true
                    } label: {
                        actionLabel("拍照识牌", icon: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isAnalyzing || !UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        actionLabel("相册", icon: "photo")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isAnalyzing)

                    Button {
                        inputMode = .addToHand
                        showTilePicker = true
                    } label: {
                        actionLabel("手动", icon: "plus.square.on.square")
                    }
                    .buttonStyle(.bordered)
                }
                if store.isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("识别服务处理中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("照片识别需在设置页填写局域网后端；手动录牌和本地牌效不依赖网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var handCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("当前手牌", systemImage: "rectangle.grid.3x2")
                        .font(.headline)
                    Spacer()
                    if !store.concealed.isEmpty {
                        Text("点牌可删除")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.concealed.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "square.grid.3x3")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("还没有手牌")
                            .font(.headline)
                        Text("拍照识别，或点击“手动”逐张录入")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.adaptive(minimum: 44), spacing: 7), count: 1),
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(Array(store.concealed.enumerated()), id: \.offset) { _, tile in
                            Button {
                                store.removeFromHand(tile)
                            } label: {
                                TileView(tile: tile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !store.melds.isEmpty {
                    Divider()
                    Text("副露（点按撤销）")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.melds) { meld in
                                Button {
                                    store.removeMeld(meld)
                                } label: {
                                    HStack(spacing: 2) {
                                        Text(meld.kind.title)
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.accentColor)
                                        ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                                            TileView(tile: tile, compact: true)
                                        }
                                    }
                                    .padding(6)
                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !store.concealedKanTiles.isEmpty || !store.addedKanTiles.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        Text("可杠")
                            .font(.subheadline.weight(.semibold))
                        ForEach(store.concealedKanTiles) { tile in
                            Button("暗杠 \(tile.shortName)") {
                                store.commitConcealedKan(tile)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        ForEach(store.addedKanTiles) { tile in
                            Button("加杠 \(tile.shortName)") {
                                store.commitAddedKan(tile)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var adviceCard: some View {
        let shanten = store.currentShanten
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("本地牌效建议", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    if shanten < 99 {
                        Text(shantenLabel(shanten))
                            .font(.caption.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(statusColor.opacity(0.13), in: Capsule())
                            .foregroundStyle(statusColor)
                    }
                }

                if store.concealed.isEmpty {
                    Text("录入手牌后自动计算。")
                        .foregroundStyle(.secondary)
                } else if shanten == -1 {
                    HStack(spacing: 10) {
                        Image(systemName: store.rules.winRequiresReady && !store.isReady ? "exclamationmark.triangle.fill" : "hands.sparkles.fill")
                            .foregroundStyle(store.rules.winRequiresReady && !store.isReady ? .orange : .red)
                        Text(store.rules.winRequiresReady && !store.isReady ? "牌型已经完成，但当前规则要求先报听才可胡。" : "手牌已经成牌。")
                            .font(.subheadline.weight(.semibold))
                    }
                } else if store.concealed.count % 3 == 2 {
                    let suggestions = Array(store.discardSuggestions.prefix(5))
                    if suggestions.isEmpty {
                        Text("牌数暂不适合计算切牌，请检查录入结果。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { rank, suggestion in
                            HStack(spacing: 10) {
                                Text("\(rank + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(rank == 0 ? Color.red : Color.secondary, in: Circle())
                                TileView(tile: suggestion.tile, compact: true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("切 \(suggestion.tile.fullName)")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(shantenLabel(suggestion.shanten)) · \(suggestion.effectiveCount) 张进张")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("切牌") {
                                    store.discard(suggestion.tile)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if rank < suggestions.count - 1 { Divider() }
                        }
                    }
                } else {
                    effectiveTilesView
                    Button {
                        inputMode = .opponentDiscard
                        showTilePicker = true
                    } label: {
                        Label("查看别人打出的牌能否碰 / 杠 / 胡", systemImage: "arrow.down.to.line.compact")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var effectiveTilesView: some View {
        let tiles = store.effectiveTiles
        return VStack(alignment: .leading, spacing: 9) {
            Text(store.currentShanten == 0 ? "等待这些牌" : "有效进张")
                .font(.subheadline.weight(.semibold))
            if tiles.isEmpty {
                Text("当前没有检测到能降低向听数的牌，请检查牌数和副露。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(tiles) { item in
                            VStack(spacing: 4) {
                                TileView(tile: item.tile, compact: true)
                                Text("余 \(item.remaining)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("共 \(tiles.reduce(0) { $0 + $1.remaining }) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var opportunityCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("对方出牌动作", systemImage: "bolt.fill")
                    .font(.headline)
                ForEach(store.opportunities) { opportunity in
                    HStack(alignment: .top, spacing: 10) {
                        Text(opportunity.kind.title)
                            .font(.title3.bold())
                            .foregroundStyle(opportunity.recommended ? .white : .secondary)
                            .frame(width: 44, height: 44)
                            .background(opportunity.recommended ? Color.red : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(opportunity.recommended ? "建议执行" : "可选，但不建议")
                                .font(.subheadline.weight(.semibold))
                            Text(opportunity.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("记录") {
                            store.commit(opportunity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(opportunity.kind == .win && !opportunity.recommended)
                    }
                    if opportunity.id != store.opportunities.last?.id { Divider() }
                }
                Button {
                    store.passIncoming()
                } label: {
                    Label("过", systemImage: "forward.end")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func serverAdviceCard(_ text: String) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("识别服务原始建议", systemImage: "server.rack")
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("本地建议会按应用内规则重新计算；服务器文字仅作对照。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        switch store.currentShanten {
        case -1: return .red
        case 0: return .orange
        case 1...2: return Color.accentColor
        default: return .secondary
        }
    }

    private func statusPrimary(_ shanten: Int) -> String {
        if store.concealed.isEmpty { return "--" }
        if shanten == -1 { return "胡" }
        if shanten == 0 { return "听" }
        if shanten < 99 { return "\(shanten)" }
        return "?"
    }

    private func statusSecondary(_ shanten: Int) -> String {
        if store.concealed.isEmpty { return "待录牌" }
        if shanten == -1 { return "已成牌" }
        if shanten == 0 { return "听牌" }
        if shanten < 99 { return "向听" }
        return "牌数异常"
    }

    private func shantenLabel(_ shanten: Int) -> String {
        if shanten == -1 { return "已成牌" }
        if shanten == 0 { return "听牌" }
        return "\(shanten) 向听"
    }
}
