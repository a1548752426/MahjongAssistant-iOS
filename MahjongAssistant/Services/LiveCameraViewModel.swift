import AVFoundation
import Combine
import Foundation

final class LiveCameraViewModel: ObservableObject {
    @Published var detections: [MahjongDetection] = []
    @Published var sourceSize = CGSize(width: 1_280, height: 720)
    @Published var dividerPosition: CGFloat = 0.46
    @Published var meldsAreAbove = true
    @Published var suggestedTile: MahjongTile?
    @Published var recognizedHand: [MahjongTile] = []
    @Published var recognizedExposed: [MahjongTile] = []
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
    private var currentOrientation: AVCaptureVideoOrientation = .landscapeRight
    private let minimumFrameInterval: TimeInterval = 0.24

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

    func dividerDidChange() {
        resetStability()
        statusText = meldsAreAbove
            ? "分界线上方识别为碰／杠副露"
            : "分界线下方识别为碰／杠副露"
    }

    func toggleMeldSide() {
        meldsAreAbove.toggle()
        dividerDidChange()
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
        stateLock.unlock()

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<MahjongInferenceResult, Error>
            do {
                result = .success(try detector.detect(pixelBuffer: pixelBuffer))
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

        let ordered = result.detections.sorted { $0.rect.midX < $1.rect.midX }
        let exposed = ordered.filter(isExposed(_:)).map(\.tile)
        let hand = ordered.filter { !isExposed($0) }.map(\.tile)
        recognizedHand = hand
        recognizedExposed = exposed

        guard !hand.isEmpty else {
            suggestedTile = nil
            statusText = result.detections.isEmpty
                ? "未识别到麻将牌，请靠近并减少反光"
                : "请移动分界线，让立牌位于手牌区域"
            resetStability()
            return
        }

        let signature = detectionSignature(hand: hand, exposed: exposed)
        if signature == stableSignature {
            stableFrameCount += 1
        } else {
            stableSignature = signature
            stableFrameCount = 1
        }

        if stableFrameCount >= 2 {
            if signature != lastAppliedSignature {
                if store.applyLiveRecognition(hand: hand, exposedTiles: exposed) {
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
            statusText = "建议打 \(best.tile.shortName) · \(best.effectiveCount) 张进张"
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
    }

    private func isExposed(_ detection: MahjongDetection) -> Bool {
        meldsAreAbove
            ? detection.rect.midY < dividerPosition
            : detection.rect.midY > dividerPosition
    }

    private func detectionSignature(
        hand: [MahjongTile],
        exposed: [MahjongTile]
    ) -> String {
        let handCounts = hand.tileCounts.map { String($0) }.joined()
        let exposedCounts = exposed.tileCounts.map { String($0) }.joined()
        return "\(handCounts)|\(exposedCounts)|\(meldsAreAbove)|\(dividerPosition.rounded(toPlaces: 2))"
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
