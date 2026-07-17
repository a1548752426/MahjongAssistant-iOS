import AVFoundation
import SwiftUI
import UIKit

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CameraPreviewUIView requires AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        // Keep the entire video frame visible so model coordinates map 1:1 to
        // the overlay without hidden aspect-fill cropping.
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.connection?.videoOrientation = orientation
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.connection?.videoOrientation = orientation
    }
}

final class LiveCameraCapture: NSObject {
    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "mahjong.camera.session")
    private let frameQueue = DispatchQueue(
        label: "mahjong.camera.frames",
        qos: .userInitiated
    )
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    func start(orientation: AVCaptureVideoOrientation) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(orientation: orientation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStart(orientation: orientation)
                } else {
                    self.onError?("没有相机权限，请到系统设置中允许访问相机")
                }
            }
        default:
            onError?("没有相机权限，请到系统设置中允许访问相机")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func updateOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            self?.videoOutput.connection(with: .video)?.videoOrientation = orientation
        }
    }

    private func configureAndStart(orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                do {
                    try self.configureSession(orientation: orientation)
                    self.isConfigured = true
                } catch {
                    self.onError?("相机启动失败：\(error.localizedDescription)")
                    return
                }
            } else {
                self.videoOutput.connection(with: .video)?.videoOrientation = orientation
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func configureSession(orientation: AVCaptureVideoOrientation) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraCaptureError.noBackCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraCaptureError.cannotAddInput
        }
        session.addInput(input)

        if (try? camera.lockForConfiguration()) != nil {
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(videoOutput) else {
            throw CameraCaptureError.cannotAddOutput
        }
        session.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.videoOrientation = orientation
    }
}

extension LiveCameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

private enum CameraCaptureError: LocalizedError {
    case noBackCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noBackCamera: return "找不到后置摄像头"
        case .cannotAddInput: return "无法读取后置摄像头"
        case .cannotAddOutput: return "无法取得摄像头视频帧"
        }
    }
}

extension AVCaptureVideoOrientation {
    static func current(for size: CGSize) -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .portrait:
            return .portrait
        default:
            return size.width > size.height ? .landscapeRight : .portrait
        }
    }
}
