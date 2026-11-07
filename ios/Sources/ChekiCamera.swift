import AVFoundation
import Photos
import SwiftUI
import UIKit

final class ChekiCamera: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.bash0c7.thermalprinter.camera")
    private var device: AVCaptureDevice?
    private var pending: CheckedContinuation<Data?, Never>?
    @MainActor private var coordinator: AVCaptureDevice.RotationCoordinator?
    @MainActor private var previewLayer: AVCaptureVideoPreviewLayer?
    @MainActor private var frontCamera: AVCaptureDevice?

    func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                NSLog("[ThermalPrinterPhone] camera access denied")
                return
            }
            queue.async {
                if self.device == nil { self.configure() }
                self.session.startRunning()
                let camera = self.device
                Task { @MainActor in
                    self.frontCamera = camera
                    self.linkRotation()
                }
            }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    @MainActor func attach(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        coordinator = nil
        linkRotation()
    }

    @MainActor private func linkRotation() {
        guard coordinator == nil, let previewLayer, let frontCamera else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: frontCamera, previewLayer: previewLayer)
        self.coordinator = coordinator
        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
    }

    @MainActor func capture() async -> Data? {
        let angle = coordinator?.videoRotationAngleForHorizonLevelCapture
        return await withCheckedContinuation { continuation in
            queue.async {
                guard self.device != nil, self.session.isRunning, self.pending == nil,
                    let connection = self.output.connection(with: .video)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                if let angle, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                self.pending = continuation
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { NSLog("[ThermalPrinterPhone] capture failed: %@", error.localizedDescription) }
        let data = photo.fileDataRepresentation()
        queue.async {
            let continuation = self.pending
            self.pending = nil
            continuation?.resume(returning: data)
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            NSLog("[ThermalPrinterPhone] no front camera")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input), session.canAddOutput(output) else { return }
            session.addInput(input)
            session.addOutput(output)
        } catch {
            NSLog("[ThermalPrinterPhone] camera input failed: %@", error.localizedDescription)
            return
        }
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        device = camera
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: ChekiCamera

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

enum PhotoSaver {
    static func save(_ data: Data) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            NSLog("[ThermalPrinterPhone] photo library access denied")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            NSLog("[ThermalPrinterPhone] photo save failed: %@", error.localizedDescription)
        }
    }
}
