import AVFoundation
import Combine
import Foundation

final class LiveCameraViewModel: ObservableObject {
    @Published var detections: [MahjongDetection] = []
    @Published var sourceSize = CGSize(width: 1_280, height: 720)
    @Published var tableDividerPosition: CGFloat = 0.58
    @Published var meldAreaWidth: CGFloat = 0.28
    @Published var meldsOnRight = true
    @Published var inferCoveredKans = true
    @Published var suggestedTile: MahjongTile?
    @Published var recognizedHand: [MahjongTile] = []
    @Published var recognizedExposed: [MahjongTile] = []
    @Published var recognizedDiscarded: [MahjongTile] = []
    @Published var inferredCoveredKanCount = 0
    @Published var manualCoveredKans: [MahjongTile] = []
    @Published var statusText = "正在载入离线模型…"
    @Published var inferenceMilliseconds: Double = 0
    @Published var isModelReady = false

    let camera = LiveCameraCapture()

    private let store: GameStore
    private let inferenceQueue = DispatchQueue(
        label: "mahjong.ondevice.inference",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var detector: OnDeviceMahjongDetector?
    private var isLoadingDetector = false
    private var isProcessingFrame = false
    private var lastInferenceDate = Date.distantPast
    private var stableSignature = ""
    private var stableFrameCount = 0
    private var lastAppliedSignature = ""
    private var recognitionSplitY: CGFloat = 0.58
    private var currentOrientation: AVCaptureVideoOrientation = .landscapeRight
    private let minimumFrameInterval: TimeInterval = 0.36

    init(store: GameStore) {
        self.store = store
        camera.onFrame = { [weak self] pixelBuffer in
            self?.enqueue(pixelBuffer)
        }
        camera.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.statusText = message
            }
        }
    }

    func start(viewSize: CGSize) {
        currentOrientation = .current(for: viewSize)
        loadDetectorIfNeeded()
        camera.start(orientation: currentOrientation)
    }

    func update(viewSize: CGSize) {
        let newOrientation = AVCaptureVideoOrientation.current(for: viewSize)
        guard newOrientation != currentOrientation else { return }
        currentOrientation = newOrientation
        camera.updateOrientation(newOrientation)
        resetStability()
    }

    func stop() {
        camera.stop()
    }

    func zonesDidChange() {
        stateLock.lock()
        recognitionSplitY = tableDividerPosition
        stateLock.unlock()
        resetStability()
        statusText = "上方识别全局弃牌；\(meldsOnRight ? "右" : "左")下识别副露"
    }

    func toggleMeldSide() {
        meldsOnRight.toggle()
        zonesDidChange()
    }

    func coveredKanSettingDidChange() {
        resetStability()
        statusText = inferCoveredKans
            ? "两张相同明牌将补全为四张盖牌暗杠"
            : "已关闭盖牌暗杠自动推断"
    }

    @MainActor
    func addManualCoveredKan(_ tile: MahjongTile) {
        guard !manualCoveredKans.contains(tile) else { return }
        manualCoveredKans.append(tile)
        manualCoveredKans.sort()
        resetStability()
        statusText = "已手动指定 \(tile.shortName) 为盖牌暗杠"
    }

    @MainActor
    func removeManualCoveredKan(_ tile: MahjongTile) {
        manualCoveredKans.removeAll { $0 == tile }
        resetStability()
        statusText = "已移除 \(tile.shortName) 的手动盖牌暗杠"
    }

    @MainActor
    func coveredKanUnavailableCount(for tile: MahjongTile) -> Int {
        if manualCoveredKans.contains(tile) { return 4 }
        let outsideMeldCounts = (recognizedHand + recognizedDiscarded).tileCounts
        return outsideMeldCounts[tile.index] > 0 ? 4 : 0
    }

    private func loadDetectorIfNeeded() {
        stateLock.lock()
        let shouldLoad = detector == nil && !isLoadingDetector
        if shouldLoad { isLoadingDetector = true }
        stateLock.unlock()
        guard shouldLoad else { return }

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                let loaded = try OnDeviceMahjongDetector()
                self.stateLock.lock()
                self.detector = loaded
                self.isLoadingDetector = false
                self.stateLock.unlock()
                DispatchQueue.main.async {
                    self.isModelReady = true
                    self.statusText = "模型已就绪，请横屏让全部牌进入画面"
                }
            } catch {
                self.stateLock.lock()
                self.isLoadingDetector = false
                self.stateLock.unlock()
                DispatchQueue.main.async {
                    self.isModelReady = false
                    self.statusText = error.localizedDescription
                }
            }
        }
    }

    private func enqueue(_ pixelBuffer: CVPixelBuffer) {
        let now = Date()
        stateLock.lock()
        guard let detector,
              !isProcessingFrame,
              now.timeIntervalSince(lastInferenceDate) >= minimumFrameInterval else {
            stateLock.unlock()
            return
        }
        isProcessingFrame = true
        lastInferenceDate = now
        let splitY = recognitionSplitY
        stateLock.unlock()

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<MahjongInferenceResult, Error>
            do {
                let overlap: CGFloat = 0.02
                let upperHeight = min(1, splitY + overlap)
                let lowerY = max(0, splitY - overlap)
                result = .success(
                    try detector.detect(
                        pixelBuffer: pixelBuffer,
                        regions: [
                            CGRect(x: 0, y: 0, width: 1, height: upperHeight),
                            CGRect(x: 0, y: lowerY, width: 1, height: 1 - lowerY)
                        ]
                    )
                )
            } catch {
                result = .failure(error)
            }

            self.stateLock.lock()
            self.isProcessingFrame = false
            self.stateLock.unlock()

            DispatchQueue.main.async {
                switch result {
                case let .success(inference):
                    self.consume(inference)
                case let .failure(error):
                    self.statusText = "离线识别失败：\(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func consume(_ result: MahjongInferenceResult) {
        detections = result.detections
        sourceSize = result.sourceSize
        inferenceMilliseconds = result.inferenceMilliseconds

        let hand = result.detections
            .filter { zone(for: $0) == .hand }
            .sorted { $0.rect.midX < $1.rect.midX }
            .map(\.tile)
        let exposed = result.detections
            .filter { zone(for: $0) == .meld }
            .sorted { $0.rect.midX < $1.rect.midX }
            .map(\.tile)
        let discarded = result.detections
            .filter { zone(for: $0) == .discard }
            .sorted {
                abs($0.rect.midY - $1.rect.midY) < 0.04
                    ? $0.rect.midX < $1.rect.midX
                    : $0.rect.midY < $1.rect.midY
            }
            .map(\.tile)
        var effectiveExposed = exposed
        for tile in manualCoveredKans {
            let visibleCount = effectiveExposed.filter { $0 == tile }.count
            if visibleCount < 4 {
                effectiveExposed.append(
                    contentsOf: Array(repeating: tile, count: 4 - visibleCount)
                )
            }
        }
        recognizedHand = hand
        recognizedExposed = exposed
        recognizedDiscarded = discarded
        inferredCoveredKanCount = inferCoveredKans
            ? exposed.tileCounts.enumerated().filter {
                $0.element == 2
                    && !manualCoveredKans.contains(MahjongTile(index: $0.offset))
            }.count
            : 0
        inferredCoveredKanCount += manualCoveredKans.count

        guard !hand.isEmpty else {
            suggestedTile = nil
            statusText = result.detections.isEmpty
                ? "未识别到麻将牌，请靠近并减少反光"
                : "请调整区域线，让立牌位于左／中下方手牌区"
            resetStability()
            return
        }

        let signature = detectionSignature(
            hand: hand,
            exposed: effectiveExposed,
            discarded: discarded
        )
        if signature == stableSignature {
            stableFrameCount += 1
        } else {
            stableSignature = signature
            stableFrameCount = 1
        }

        if stableFrameCount >= 2 {
            if signature != lastAppliedSignature {
                if store.applyLiveRecognition(
                    hand: hand,
                    exposedTiles: effectiveExposed,
                    discardedTiles: discarded,
                    inferCoveredKans: inferCoveredKans
                ) {
                    lastAppliedSignature = signature
                }
            }
            updateAdvice()
        } else {
            suggestedTile = nil
            statusText = "正在确认 \(hand.count) 张手牌…"
        }
    }

    @MainActor
    private func updateAdvice() {
        if let best = store.discardSuggestions.first {
            suggestedTile = best.tile
            statusText = "建议打 \(best.tile.shortName) · \(best.effectiveCount) 张进张 · 已见 \(recognizedDiscarded.count) 张弃牌"
        } else {
            suggestedTile = nil
            let shanten = store.currentShanten
            if shanten == -1 {
                statusText = (!store.rules.winRequiresReady || store.isReady)
                    ? "已经和牌"
                    : "已经成牌，按当前规则需先报听才可胡"
            } else if shanten == 0 {
                statusText = "当前听牌，等待进张"
            } else if shanten < 99 {
                statusText = "\(shanten) 向听；摸牌后显示建议切牌"
            } else {
                statusText = "请保持完整手牌入镜"
            }
        }
        if inferredCoveredKanCount > 0 {
            statusText += " · 推断盖牌杠×\(inferredCoveredKanCount)"
        }
    }

    private enum RecognitionZone {
        case discard
        case hand
        case meld
    }

    private func zone(for detection: MahjongDetection) -> RecognitionZone {
        if detection.rect.midY < tableDividerPosition {
            return .discard
        }
        let isInMeldArea = meldsOnRight
            ? detection.rect.midX > 1 - meldAreaWidth
            : detection.rect.midX < meldAreaWidth
        return isInMeldArea ? .meld : .hand
    }

    private func detectionSignature(
        hand: [MahjongTile],
        exposed: [MahjongTile],
        discarded: [MahjongTile]
    ) -> String {
        let handCounts = hand.tileCounts.map { String($0) }.joined()
        let exposedCounts = exposed.tileCounts.map { String($0) }.joined()
        let discardedCounts = discarded.tileCounts.map { String($0) }.joined()
        return [
            handCounts,
            exposedCounts,
            discardedCounts,
            String(meldsOnRight),
            String(inferCoveredKans),
            manualCoveredKans.map(\.code).joined(separator: ","),
            String(describing: tableDividerPosition.rounded(toPlaces: 2)),
            String(describing: meldAreaWidth.rounded(toPlaces: 2))
        ].joined(separator: "|")
    }

    private func resetStability() {
        stableSignature = ""
        stableFrameCount = 0
        lastAppliedSignature = ""
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let power = CGFloat(pow(10.0, Double(places)))
        return (self * power).rounded() / power
    }
}
