import AVFoundation
import CoreVideo

/// Keeps an AVCaptureSession running and exposes the most-recent frame on demand.
/// The session is started once; PostureAnalyzer samples `latestFrame` every 5 s
/// so we avoid the overhead of starting/stopping per cycle.
final class CameraCapture: NSObject {

    /// The most recent pixel buffer captured by the session. Thread-safe.
    private(set) var latestFrame: CVPixelBuffer? {
        get { lock.withLock { _latestFrame } }
        set { lock.withLock { _latestFrame = newValue } }
    }

    private var _latestFrame: CVPixelBuffer?
    private let lock = NSLock()

    private let session    = AVCaptureSession()
    private let output     = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.posture.camera.session", qos: .utility)
    private let sampleQueue  = DispatchQueue(label: "com.posture.camera.sample",  qos: .utility)

    override init() {
        super.init()
        setupSession()
    }

    // MARK: - Setup

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        // Prefer the front camera (typical laptop webcam)
        let device =
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
    }

    // MARK: - Lifecycle

    var isRunning: Bool { session.isRunning }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestFrame = pixelBuffer
    }
}

// MARK: - NSLock helper

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
