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

    /// Shared with previews. Configured and started on `queue` only.
    let session = AVCaptureSession()

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
        super.init()
    }

    /// Configures the session and starts writing to `url`; returns once the
    /// file is actually being recorded.
    func start(_ configuration: Configuration, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure(configuration)
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

    private func configure(_ configuration: Configuration) throws {
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
        let preset = configuration.quality.sessionPreset
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high

        if configuration.includeMicrophone,
           let microphone = Self.microphone(matching: configuration.microphoneID),
           let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(microphoneInput) {
            session.addInput(microphoneInput)
        }

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecorderError.cameraUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
        applyVideoSettings(for: camera)
    }

    /// HEVC when the Mac can encode it (about half the size of H.264 for an
    /// hour of webcam), at the camera's actual resolution. The settings come
    /// from AVOutputSettingsAssistant, which returns nil instead of a
    /// dictionary the encoder would reject.
    private func applyVideoSettings(for camera: AVCaptureDevice) {
        guard let connection = output.connection(with: .video) else { return }
        let assistant = AVOutputSettingsAssistant(preset: .hevc1920x1080)
            ?? AVOutputSettingsAssistant(preset: .preset1920x1080)
        guard var settings = assistant?.videoSettings else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        if dimensions.width > 0, dimensions.height > 0 {
            settings[AVVideoWidthKey] = Int(dimensions.width)
            settings[AVVideoHeightKey] = Int(dimensions.height)
        }
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
