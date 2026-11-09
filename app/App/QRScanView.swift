import AVFoundation
import AppKit
import CoreImage
import SwiftUI
import ThermalPrinterCore

struct CameraChoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    static func available() -> [CameraChoice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
    }
}

final class QRScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let minimumFrameInterval = Duration.milliseconds(250)

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.bash0c7.thermalprinter.qr-scanner")
    private let output = AVCaptureVideoDataOutput()
    private let imageContext = CIContext()
    private var onPayload: (@Sendable (String) -> Void)?
    private var lastProcessed = ContinuousClock.now - minimumFrameInterval

    func start(cameraID: String, onPayload: @escaping @Sendable (String) -> Void) {
        queue.async {
            self.onPayload = onPayload
            self.configure(cameraID: cameraID)
            self.session.startRunning()
        }
    }

    func switchCamera(to cameraID: String) {
        queue.async { self.configure(cameraID: cameraID) }
    }

    func stop() {
        queue.async {
            self.onPayload = nil
            self.session.stopRunning()
        }
    }

    private func configure(cameraID: String) {
        guard let device = AVCaptureDevice(uniqueID: cameraID),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if session.canAddInput(input) { session.addInput(input) }
        if session.outputs.isEmpty {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let onPayload, ContinuousClock.now - lastProcessed >= Self.minimumFrameInterval,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        lastProcessed = .now
        let frame = CIImage(cvPixelBuffer: pixels)
        guard let image = imageContext.createCGImage(frame, from: frame.extent),
              let payload = try? QRReader.payloads(in: image).first
        else { return }
        self.onPayload = nil
        session.stopRunning()
        onPayload(payload)
    }
}

private final class PreviewView: NSView {
    override func makeBackingLayer() -> CALayer { AVCaptureVideoPreviewLayer() }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = PreviewView()
        view.wantsLayer = true
        let layer = view.layer as? AVCaptureVideoPreviewLayer
        layer?.session = session
        layer?.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

struct QRScanView: View {
    enum Phase: Equatable {
        case checking
        case scanning
        case denied
        case noCamera

        var message: String? {
            switch self {
            case .checking, .scanning: nil
            case .denied: "カメラへのアクセスが許可されていません。システム設定の「プライバシーとセキュリティ」で許可してください"
            case .noCamera: "使えるカメラが見つかりません"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var scanner = QRScanner()
    @State private var phase = Phase.checking
    @State private var cameras: [CameraChoice] = []
    @State private var cameraID = ""

    var body: some View {
        VStack(spacing: 12) {
            if cameras.count > 1 {
                Picker("カメラ", selection: $cameraID) {
                    ForEach(cameras) { Text($0.name).tag($0.id) }
                }
                .accessibilityIdentifier("scanCameraPicker")
            }
            content
            Button("閉じる") { model.isScanning = false }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("closeScanButton")
        }
        .padding(16)
        .frame(width: 640, height: 520)
        .task { await begin() }
        .onChange(of: cameraID) { _, id in
            if phase == .scanning { scanner.switchCamera(to: id) }
        }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder private var content: some View {
        if let message = phase.message {
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("scanMessageLabel")
        } else {
            CameraPreview(session: scanner.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .accessibilityIdentifier("scanPreview")
        }
    }

    private func begin() async {
        guard await cameraAccessGranted() else {
            phase = .denied
            return
        }
        cameras = CameraChoice.available()
        guard let first = cameras.first, !Task.isCancelled else {
            if cameras.isEmpty { phase = .noCamera }
            return
        }
        cameraID = first.id
        phase = .scanning
        let model = model
        scanner.start(cameraID: first.id) { text in
            Task { @MainActor in model.finishScanning(with: text) }
        }
    }

    private func cameraAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }
}

struct ScannedTextSheet: View {
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("読み取った文字列").font(.headline)
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("scannedText")
            }
            .frame(minHeight: 80, maxHeight: 240)
            HStack {
                Spacer()
                Button("コピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .accessibilityIdentifier("copyScannedTextButton")
                Button("閉じる", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("closeScannedTextButton")
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
