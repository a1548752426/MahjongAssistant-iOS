import Accelerate
import CoreVideo
import Foundation

struct MahjongDetection: Identifiable {
    let id = UUID()
    let label: String
    let tile: MahjongTile
    let confidence: Float
    /// Normalized coordinates in the camera frame.
    let rect: CGRect
}

struct MahjongInferenceResult {
    let detections: [MahjongDetection]
    let sourceSize: CGSize
    let inferenceMilliseconds: Double
}

enum OnDeviceDetectorError: LocalizedError {
    case missingModel
    case missingLabels
    case unsupportedPixelFormat
    case preprocessingFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "离线麻将识别模型没有打包进应用"
        case .missingLabels:
            return "离线模型的牌名文件缺失"
        case .unsupportedPixelFormat:
            return "摄像头输出了不支持的像素格式"
        case .preprocessingFailed:
            return "无法处理摄像头画面"
        case .invalidOutput:
            return "离线模型返回了无法解析的结果"
        }
    }
}

final class OnDeviceMahjongDetector {
    private struct Letterbox {
        let tensor: NSMutableData
        let scale: CGFloat
        let paddingX: CGFloat
        let paddingY: CGFloat
        let sourceSize: CGSize
    }

    private struct Candidate {
        let label: String
        let tile: MahjongTile
        let score: Float
        let rect: CGRect
    }

    private let inputSize = 640
    private let anchorCount = 8_400
    private let confidenceThreshold: Float = 0.54
    private let iouThreshold: CGFloat = 0.46
    private let labels: [String]
    private let environment: ORTEnv
    private let session: ORTSession

    init(bundle: Bundle = .main) throws {
        guard let modelURL = bundle.url(forResource: "weights", withExtension: "onnx") else {
            throw OnDeviceDetectorError.missingModel
        }
        guard let labelsURL = bundle.url(forResource: "MahjongLabels", withExtension: "txt"),
              let labelsText = try? String(contentsOf: labelsURL, encoding: .utf8) else {
            throw OnDeviceDetectorError.missingLabels
        }
        labels = labelsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let ortEnvironment = try ORTEnv(loggingLevel: .warning)
        environment = ortEnvironment
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(2)

        if ORTIsCoreMLExecutionProviderAvailable() {
            let coreML = ORTCoreMLExecutionProviderOptions()
            coreML.onlyAllowStaticInputShapes = true
            coreML.createMLProgram = true
            coreML.enableOnSubgraphs = true
            try? options.appendCoreMLExecutionProvider(with: coreML)
        }

        session = try ORTSession(
            env: ortEnvironment,
            modelPath: modelURL.path,
            sessionOptions: options
        )
    }

    func detect(pixelBuffer: CVPixelBuffer) throws -> MahjongInferenceResult {
        let letterbox = try makeInput(from: pixelBuffer)
        let input = try ORTValue(
            tensorData: letterbox.tensor,
            elementType: .float,
            shape: [1, 3, inputSize, inputSize].map { NSNumber(value: $0) }
        )

        let started = CFAbsoluteTimeGetCurrent()
        let outputs = try session.run(
            withInputs: ["images": input],
            outputNames: ["output0"],
            runOptions: nil
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1_000

        guard let output = outputs["output0"] else {
            throw OnDeviceDetectorError.invalidOutput
        }
        let rawData = try output.tensorData() as Data
        let values = rawData.withUnsafeBytes { rawBuffer -> [Float] in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
        guard values.count >= (labels.count + 4) * anchorCount else {
            throw OnDeviceDetectorError.invalidOutput
        }

        let candidates = decode(values, letterbox: letterbox)
        let detections = nonMaximumSuppression(candidates)
            .prefix(24)
            .map {
                MahjongDetection(
                    label: $0.label,
                    tile: $0.tile,
                    confidence: $0.score,
                    rect: $0.rect
                )
            }

        return MahjongInferenceResult(
            detections: detections,
            sourceSize: letterbox.sourceSize,
            inferenceMilliseconds: elapsed
        )
    }

    private func makeInput(from pixelBuffer: CVPixelBuffer) throws -> Letterbox {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw OnDeviceDetectorError.unsupportedPixelFormat
        }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw OnDeviceDetectorError.preprocessingFailed
        }

        let scale = min(
            CGFloat(inputSize) / CGFloat(sourceWidth),
            CGFloat(inputSize) / CGFloat(sourceHeight)
        )
        let scaledWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let scaledHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))
        let paddingX = CGFloat(inputSize - scaledWidth) / 2
        let paddingY = CGFloat(inputSize - scaledHeight) / 2
        let left = Int(paddingX.rounded(.down))
        let top = Int(paddingY.rounded(.down))

        var bgra = [UInt8](repeating: 114, count: inputSize * inputSize * 4)
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let sourceAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OnDeviceDetectorError.preprocessingFailed
        }

        let status = bgra.withUnsafeMutableBytes { destinationBytes -> vImage_Error in
            guard let destinationAddress = destinationBytes.baseAddress else {
                return kvImageNullPointerArgument
            }
            var source = vImage_Buffer(
                data: sourceAddress,
                height: vImagePixelCount(sourceHeight),
                width: vImagePixelCount(sourceWidth),
                rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
            )
            var destination = vImage_Buffer(
                data: destinationAddress.advanced(by: (top * inputSize + left) * 4),
                height: vImagePixelCount(scaledHeight),
                width: vImagePixelCount(scaledWidth),
                rowBytes: inputSize * 4
            )
            return vImageScale_ARGB8888(
                &source,
                &destination,
                nil,
                vImage_Flags(kvImageHighQualityResampling)
            )
        }
        guard status == kvImageNoError else {
            throw OnDeviceDetectorError.preprocessingFailed
        }

        let planeSize = inputSize * inputSize
        var floats = [Float](repeating: 0, count: planeSize * 3)
        let divisor: Float = 1 / 255
        for pixel in 0..<planeSize {
            let byteOffset = pixel * 4
            floats[pixel] = Float(bgra[byteOffset + 2]) * divisor
            floats[planeSize + pixel] = Float(bgra[byteOffset + 1]) * divisor
            floats[(planeSize * 2) + pixel] = Float(bgra[byteOffset]) * divisor
        }
        let tensor = floats.withUnsafeBufferPointer { buffer in
            NSMutableData(
                bytes: buffer.baseAddress,
                length: buffer.count * MemoryLayout<Float>.stride
            )
        }

        return Letterbox(
            tensor: tensor,
            scale: scale,
            paddingX: paddingX,
            paddingY: paddingY,
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight)
        )
    }

    private func decode(_ output: [Float], letterbox: Letterbox) -> [Candidate] {
        var result: [Candidate] = []
        let sourceWidth = letterbox.sourceSize.width
        let sourceHeight = letterbox.sourceSize.height

        for anchor in 0..<anchorCount {
            var bestClass = 0
            var bestScore: Float = 0
            for classIndex in labels.indices {
                let score = output[(classIndex + 4) * anchorCount + anchor]
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }
            guard bestScore >= confidenceThreshold,
                  let tile = Self.tile(for: labels[bestClass]) else {
                continue
            }

            let centerX = CGFloat(output[anchor])
            let centerY = CGFloat(output[anchorCount + anchor])
            let width = CGFloat(output[(anchorCount * 2) + anchor])
            let height = CGFloat(output[(anchorCount * 3) + anchor])

            let minX = ((centerX - width / 2) - letterbox.paddingX) / letterbox.scale
            let minY = ((centerY - height / 2) - letterbox.paddingY) / letterbox.scale
            let maxX = ((centerX + width / 2) - letterbox.paddingX) / letterbox.scale
            let maxY = ((centerY + height / 2) - letterbox.paddingY) / letterbox.scale

            let normalized = CGRect(
                x: max(0, min(1, minX / sourceWidth)),
                y: max(0, min(1, minY / sourceHeight)),
                width: max(0, min(1, maxX / sourceWidth) - max(0, min(1, minX / sourceWidth))),
                height: max(0, min(1, maxY / sourceHeight) - max(0, min(1, minY / sourceHeight)))
            )
            guard normalized.width > 0.005, normalized.height > 0.005 else { continue }
            result.append(
                Candidate(
                    label: labels[bestClass],
                    tile: tile,
                    score: bestScore,
                    rect: normalized
                )
            )
        }
        return result
    }

    private func nonMaximumSuppression(_ candidates: [Candidate]) -> [Candidate] {
        var kept: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard kept.allSatisfy({ intersectionOverUnion(candidate.rect, $0.rect) < iouThreshold }) else {
                continue
            }
            kept.append(candidate)
        }
        return kept
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    static func tile(for modelLabel: String) -> MahjongTile? {
        let label = modelLabel.uppercased()
        if label.count == 2,
           let rank = Int(String(label.first ?? " ")),
           (1...9).contains(rank) {
            switch label.last {
            case "B": return MahjongTile(index: 18 + rank - 1)
            case "C": return MahjongTile(index: rank - 1)
            case "D": return MahjongTile(index: 9 + rank - 1)
            default: break
            }
        }

        let honors: [String: Int] = [
            "EW": 27,
            "SW": 28,
            "WW": 29,
            "NW": 30,
            "WD": 31,
            "GD": 32,
            "RD": 33
        ]
        return honors[label].map(MahjongTile.init(index:))
    }
}
