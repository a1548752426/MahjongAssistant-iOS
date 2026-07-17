import AVFoundation
import SwiftUI

struct LiveCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LiveCameraViewModel
    @State private var showCoveredKanPicker = false

    init(store: GameStore) {
        _viewModel = StateObject(wrappedValue: LiveCameraViewModel(store: store))
    }

    var body: some View {
        GeometryReader { geometry in
            let orientation = AVCaptureVideoOrientation.current(for: geometry.size)

            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(
                    session: viewModel.camera.session,
                    orientation: orientation
                )

                DetectionOverlay(
                    detections: viewModel.detections,
                    sourceSize: viewModel.sourceSize,
                    viewSize: geometry.size,
                    tableDividerPosition: viewModel.tableDividerPosition,
                    meldAreaWidth: viewModel.meldAreaWidth,
                    meldsOnRight: viewModel.meldsOnRight,
                    suggestedTile: viewModel.suggestedTile
                )

                controls(isPortrait: geometry.size.height > geometry.size.width)
            }
            .onAppear {
                viewModel.start(viewSize: geometry.size)
            }
            .onDisappear {
                viewModel.stop()
            }
            .onChange(of: geometry.size) { newSize in
                viewModel.update(viewSize: newSize)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .sheet(isPresented: $showCoveredKanPicker) {
            TilePickerView(
                title: "选择全盖／漏识别的暗杠",
                dismissAfterSelection: true,
                unavailableCount: { viewModel.coveredKanUnavailableCount(for: $0) },
                onSelect: { viewModel.addManualCoveredKan($0) }
            )
        }
    }

    private func controls(isPortrait: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(viewModel.isModelReady ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.statusText)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    Text(
                        "手牌 \(viewModel.recognizedHand.count) · 副露明牌 \(viewModel.recognizedExposed.count) · 全局弃牌 \(viewModel.recognizedDiscarded.count)"
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))

                Spacer()

                if viewModel.inferenceMilliseconds > 0 {
                    Text("\(Int(viewModel.inferenceMilliseconds)) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if isPortrait {
                Text("横屏可让整排麻将更容易完整入镜")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.yellow, in: Capsule())
                    .padding(.top, 10)
            }

            Spacer()

            VStack(spacing: 9) {
                HStack {
                    Label(
                        "上方＝全局弃牌，下方＝手牌＋副露",
                        systemImage: "rectangle.split.2x1"
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(viewModel.meldsOnRight ? "副露改左边" : "副露改右边") {
                        viewModel.toggleMeldSide()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.small)
                }

                HStack(spacing: 10) {
                    Text("弃牌区")
                    Slider(
                        value: $viewModel.tableDividerPosition,
                        in: 0.38...0.76,
                        step: 0.01
                    )
                    .tint(.yellow)
                    .onChange(of: viewModel.tableDividerPosition) { _ in
                        viewModel.zonesDidChange()
                    }
                    Text("手牌区")
                }
                .font(.caption.bold())

                HStack(spacing: 10) {
                    Text("副露宽度")
                    Slider(
                        value: $viewModel.meldAreaWidth,
                        in: 0.16...0.46,
                        step: 0.01
                    )
                    .tint(.orange)
                    .onChange(of: viewModel.meldAreaWidth) { _ in
                        viewModel.zonesDidChange()
                    }
                    Toggle("盖牌暗杠", isOn: $viewModel.inferCoveredKans)
                        .labelsHidden()
                        .tint(.orange)
                        .onChange(of: viewModel.inferCoveredKans) { _ in
                            viewModel.coveredKanSettingDidChange()
                        }
                    Text("盖牌暗杠")
                    Button("全盖暗杠＋") {
                        showCoveredKanPicker = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.small)
                }
                .font(.caption.bold())

                if !viewModel.manualCoveredKans.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            Text("手动暗杠")
                                .font(.caption.bold())
                            ForEach(viewModel.manualCoveredKans) { tile in
                                Button {
                                    viewModel.removeManualCoveredKan(tile)
                                } label: {
                                    Label(tile.shortName, systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .controlSize(.mini)
                            }
                        }
                    }
                }

                Text("紫框统计全局弃牌；右侧橙框为副露。副露仅露出两张相同牌时，默认按四张暗杠补全。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

private struct DetectionOverlay: View {
    let detections: [MahjongDetection]
    let sourceSize: CGSize
    let viewSize: CGSize
    let tableDividerPosition: CGFloat
    let meldAreaWidth: CGFloat
    let meldsOnRight: Bool
    let suggestedTile: MahjongTile?

    var body: some View {
        let transform = AspectFitTransform(source: sourceSize, destination: viewSize)
        ZStack(alignment: .topLeading) {
            let dividerY = transform.y(forNormalized: tableDividerPosition)
            let meldDividerX = transform.x(
                forNormalized: meldsOnRight ? 1 - meldAreaWidth : meldAreaWidth
            )
            Path { path in
                path.move(to: CGPoint(x: transform.x(forNormalized: 0), y: dividerY))
                path.addLine(to: CGPoint(x: transform.x(forNormalized: 1), y: dividerY))
            }
            .stroke(
                Color.yellow.opacity(0.9),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )

            Path { path in
                path.move(to: CGPoint(x: meldDividerX, y: dividerY))
                path.addLine(
                    to: CGPoint(x: meldDividerX, y: transform.y(forNormalized: 1))
                )
            }
            .stroke(
                Color.orange.opacity(0.95),
                style: StrokeStyle(lineWidth: 2, dash: [7, 5])
            )

            Text("全局弃牌区")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.purple.opacity(0.9), in: Capsule())
                .position(
                    x: transform.x(forNormalized: 0.09),
                    y: max(15, dividerY - 15)
                )

            Text(meldsOnRight ? "右侧副露区" : "左侧副露区")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.9), in: Capsule())
                .position(
                    x: transform.x(
                        forNormalized: meldsOnRight
                            ? 1 - meldAreaWidth / 2
                            : meldAreaWidth / 2
                    ),
                    y: dividerY + 15
                )

            ForEach(detections) { detection in
                detectionBox(detection, transform: transform)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func detectionBox(
        _ detection: MahjongDetection,
        transform: AspectFitTransform
    ) -> some View {
        let box = transform.rect(forNormalized: detection.rect)
        let zone = zone(for: detection)
        let isSuggested = zone == .hand && detection.tile == suggestedTile
        let color: Color
        switch zone {
        case .discard: color = .purple
        case .meld: color = .orange
        case .hand: color = isSuggested ? .green : .cyan
        }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7)
                .stroke(color, lineWidth: isSuggested ? 6 : 3)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(isSuggested ? 0.18 : 0.06))
                )
            HStack(spacing: 4) {
                if isSuggested {
                    Image(systemName: "arrow.down.circle.fill")
                }
                Text(
                    isSuggested
                        ? "打 \(detection.tile.shortName)"
                        : "\(detection.tile.shortName) \(Int(detection.confidence * 100))%"
                )
            }
            .font((isSuggested ? Font.headline : Font.caption).bold())
            .foregroundStyle(isSuggested ? .black : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(isSuggested ? 0.95 : 0.82), in: Capsule())
            .offset(y: -27)
        }
        .frame(width: max(30, box.width), height: max(30, box.height))
        .position(x: box.midX, y: box.midY)
    }

    private enum Zone {
        case discard
        case hand
        case meld
    }

    private func zone(for detection: MahjongDetection) -> Zone {
        if detection.rect.midY < tableDividerPosition {
            return .discard
        }
        let isMeld = meldsOnRight
            ? detection.rect.midX > 1 - meldAreaWidth
            : detection.rect.midX < meldAreaWidth
        return isMeld ? .meld : .hand
    }
}

private struct AspectFitTransform {
    let source: CGSize
    let destination: CGSize
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat

    init(source: CGSize, destination: CGSize) {
        let safeSource = CGSize(
            width: max(1, source.width),
            height: max(1, source.height)
        )
        let computedScale = min(
            destination.width / safeSource.width,
            destination.height / safeSource.height
        )
        self.source = safeSource
        self.destination = destination
        scale = computedScale
        offsetX = (destination.width - safeSource.width * computedScale) / 2
        offsetY = (destination.height - safeSource.height * computedScale) / 2
    }

    func rect(forNormalized rect: CGRect) -> CGRect {
        CGRect(
            x: offsetX + rect.minX * source.width * scale,
            y: offsetY + rect.minY * source.height * scale,
            width: rect.width * source.width * scale,
            height: rect.height * source.height * scale
        )
    }

    func y(forNormalized value: CGFloat) -> CGFloat {
        offsetY + value * source.height * scale
    }

    func x(forNormalized value: CGFloat) -> CGFloat {
        offsetX + value * source.width * scale
    }
}
