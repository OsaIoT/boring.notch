//
//  CameraRecorder.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Records a camera and, optionally, a microphone to a QuickTime movie. It
//  has its own capture session, independent of the mirror's, which tears
//  down whenever the notch closes. All AVFoundation work runs on one serial
//  queue.
//

import AVFoundation
import Foundation

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// Bit rate for webcam recordings. A person talking in front of a still
/// background compresses far better than the general-purpose presets
/// assume: about 4.5 Mbit/s for 1080p HEVC (≈2 GB an hour instead of ≈4)
/// still looks the same. Scaled by resolution, so 720p gets about 2 Mbit/s;
/// H.264 needs about 60% more for the same quality.
enum WebcamBitRate {
    static let hevcBitsPerPixel = 0.072
    static let h264Factor = 1.6

    static func average(width: Int, height: Int, isHEVC: Bool, framesPerSecond: Double = 30) -> Int {
        let hevc = Double(width * height) * framesPerSecond * hevcBitsPerPixel
        return Int((isHEVC ? hevc : hevc * h264Factor).rounded())
    }
}

extension RecordingQuality {
    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080: .hd1920x1080
        case .hd720: .hd1280x720
        }
    }
}

final class CameraRecorder: NSObject, @unchecked Sendable {
    struct Configuration: Sendable {
        /// Nil picks the camera automatically, built-in first.
        var cameraID: String?
        /// Nil uses the system's default input.
        var microphoneID: String?
        var includeMicrophone: Bool
        var quality: RecordingQuality
        /// Mirrors the preview only; the recorded video is never flipped.
        var mirrorPreview: Bool
    }

    enum RecorderError: LocalizedError {
        case noCamera
        case cameraUnavailable
        case notRecording

        var errorDescription: String? {
            switch self {
            case .noCamera: String(localized: "No camera found.")
            case .cameraUnavailable: String(localized: "The camera can't be used right now.")
            case .notRecording: String(localized: "Nothing is being recorded.")
            }
        }
    }

    /// Configured and started on `queue` only.
    let session: AVCaptureSession
    /// The live preview, created up front: attaching a new preview layer to
    /// a session that is already recording reconfigures it, and AVFoundation
    /// then ends the movie file after a fraction of a second. Views only
    /// host this layer.
    let previewLayer: AVCaptureVideoPreviewLayer
    /// Same, for the floating bubble. Created up front for the same reason.
    let bubblePreviewLayer: AVCaptureVideoPreviewLayer

    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "BoringNotch.Focus.CameraRecorder", qos: .userInitiated)
    /// Called when a recording ends without `stop()`, e.g. the camera was
    /// unplugged. Receives the file when it was still saved.
    private let onUnexpectedFinish: @Sendable (URL?, Error?) -> Void

    // Only touched on `queue`.
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    init(onUnexpectedFinish: @escaping @Sendable (URL?, Error?) -> Void) {
        self.onUnexpectedFinish = onUnexpectedFinish
        let session = AVCaptureSession()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        let bubblePreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        bubblePreviewLayer.videoGravity = .resizeAspectFill
        self.session = session
        self.previewLayer = previewLayer
        self.bubblePreviewLayer = bubblePreviewLayer
        super.init()
    }

    /// Configures the session and starts writing to `url`; returns once the
    /// file is actually being recorded.
    func start(_ configuration: Configuration, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure(configuration, recordsToFile: true)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    self.startContinuation = continuation
                    self.output.startRecording(to: url, recordingDelegate: self)
                } catch {
                    self.teardown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs the camera for the previews only, with no file and no
    /// microphone: in screen recordings the bubble is captured with the rest
    /// of the screen.
    func startPreview(_ configuration: Configuration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure(configuration, recordsToFile: false)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    self.teardown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopPreview() {
        queue.async {
            self.teardown()
        }
    }

    func pause() {
        queue.async {
            if self.output.isRecording, !self.output.isRecordingPaused {
                self.output.pauseRecording()
            }
        }
    }

    func resume() {
        queue.async {
            if self.output.isRecordingPaused {
                self.output.resumeRecording()
            }
        }
    }

    /// Finishes the file and returns where it was saved.
    func stop() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            queue.async {
                guard self.output.isRecording else {
                    continuation.resume(throwing: RecorderError.notRecording)
                    return
                }
                self.stopContinuation = continuation
                self.output.stopRecording()
            }
        }
    }

    private func configure(_ configuration: Configuration, recordsToFile: Bool) throws {
        guard let camera = Self.camera(matching: configuration.cameraID) else {
            throw RecorderError.noCamera
        }
        let cameraInput = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard session.canAddInput(cameraInput) else {
            session.commitConfiguration()
            throw RecorderError.cameraUnavailable
        }
        session.addInput(cameraInput)
        // A bubble doesn't need 1080p.
        let preset = recordsToFile ? configuration.quality.sessionPreset : .hd1280x720
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high

        if recordsToFile,
           configuration.includeMicrophone,
           let microphone = Self.microphone(matching: configuration.microphoneID),
           let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(microphoneInput) {
            session.addInput(microphoneInput)
        }

        if recordsToFile {
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw RecorderError.cameraUnavailable
            }
            session.addOutput(output)
        }
        session.commitConfiguration()
        if recordsToFile {
            applyVideoSettings(for: camera)
        }
        // Before recording starts, like everything else that touches the
        // session's connections.
        for layer in [previewLayer, bubblePreviewLayer] {
            if let connection = layer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = configuration.mirrorPreview
            }
        }
    }

    /// HEVC when the Mac can encode it, at the camera's actual resolution and
    /// a bit rate sized for a webcam (see WebcamBitRate). The settings start
    /// from AVOutputSettingsAssistant, which returns nil instead of a
    /// dictionary the encoder would reject.
    private func applyVideoSettings(for camera: AVCaptureDevice) {
        guard let connection = output.connection(with: .video) else { return }
        let hevcAssistant = AVOutputSettingsAssistant(preset: .hevc1920x1080)
        let assistant = hevcAssistant ?? AVOutputSettingsAssistant(preset: .preset1920x1080)
        guard var settings = assistant?.videoSettings else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let width = dimensions.width > 0 ? Int(dimensions.width) : 1920
        let height = dimensions.height > 0 ? Int(dimensions.height) : 1080
        settings[AVVideoWidthKey] = width
        settings[AVVideoHeightKey] = height
        var compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any] ?? [:]
        compression[AVVideoAverageBitRateKey] = WebcamBitRate.average(
            width: width,
            height: height,
            isHEVC: hevcAssistant != nil
        )
        settings[AVVideoCompressionPropertiesKey] = compression
        output.setOutputSettings(settings, for: connection)
    }

    private func teardown() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
    }

    /// The chosen camera, or the automatic pick (built-in first) when it's
    /// missing: recording with another camera beats not recording at all.
    static func camera(matching id: String?) -> AVCaptureDevice? {
        let devices = AVCaptureSessionEngine.discoveredDevices()
        let chosen = id.flatMap { id in devices.first { $0.id == id } }
            ?? preferredCamera(from: devices, selection: .automatic)
        return chosen.flatMap { AVCaptureDevice(uniqueID: $0.id) }
    }

    static func microphone(matching id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }

    static func availableMicrophones() -> [AudioInputDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        queue.async {
            self.startContinuation?.resume()
            self.startContinuation = nil
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // AVFoundation reports some clean stops as errors; this key says
        // whether the file is complete anyway.
        let finishedCleanly = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        queue.async {
            self.teardown()
            let saved = finishedCleanly && FileManager.default.fileExists(atPath: outputFileURL.path)

            if let start = self.startContinuation {
                self.startContinuation = nil
                start.resume(throwing: error ?? RecorderError.cameraUnavailable)
                return
            }
            if let stop = self.stopContinuation {
                self.stopContinuation = nil
                if saved {
                    stop.resume(returning: outputFileURL)
                } else {
                    stop.resume(throwing: error ?? RecorderError.notRecording)
                }
                return
            }
            self.onUnexpectedFinish(saved ? outputFileURL : nil, error)
        }
    }
}
