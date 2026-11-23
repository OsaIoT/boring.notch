//
//  ScreenRecorder.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Records a display (and optionally the microphone) straight to a movie
//  file with ScreenCaptureKit's SCRecordingOutput (macOS 15+). A webcam
//  bubble, when shown, is just another window on screen, so it ends up in
//  the video without any compositing.
//

import AVFoundation
import ScreenCaptureKit

/// Frame size for screen recordings: the display's pixels, scaled down so
/// the height stays within the quality's limit. Code stays sharp without
/// 5K files. Even numbers, as video encoders expect.
enum ScreenCaptureSize {
    static func outputSize(pixelWidth: Int, pixelHeight: Int, quality: RecordingQuality) -> (width: Int, height: Int) {
        let maxHeight = quality == .hd1080 ? 1440 : 900
        let scale = min(1, Double(maxHeight) / Double(max(pixelHeight, 1)))
        let width = Int((Double(pixelWidth) * scale).rounded(.down)) & ~1
        let height = Int((Double(pixelHeight) * scale).rounded(.down)) & ~1
        return (max(width, 2), max(height, 2))
    }
}

@available(macOS 15.0, *)
final class ScreenRecorder: NSObject, @unchecked Sendable {
    struct Configuration: Sendable {
        var displayID: CGDirectDisplayID
        var includeMicrophone: Bool
        /// Nil uses the system's default input.
        var microphoneID: String?
        var showsClicks: Bool
        var quality: RecordingQuality
    }

    enum RecorderError: LocalizedError {
        case displayNotFound
        case notRecording

        var errorDescription: String? {
            switch self {
            case .displayNotFound: String(localized: "The screen to record can't be found.")
            case .notRecording: String(localized: "Nothing is being recorded.")
            }
        }
    }

    /// Called when a recording ends without `stop()`, e.g. the display was
    /// unplugged or screen recording access was revoked.
    private let onUnexpectedFinish: @Sendable (URL?, Error?) -> Void
    private let sampleQueue = DispatchQueue(label: "BoringNotch.Focus.ScreenRecorder.samples", qos: .utility)

    private let lock = NSLock()
    // Guarded by `lock`.
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?
    private var isFinished = true

    init(onUnexpectedFinish: @escaping @Sendable (URL?, Error?) -> Void) {
        self.onUnexpectedFinish = onUnexpectedFinish
        super.init()
    }

    func start(_ configuration: Configuration, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == configuration.displayID })
            ?? content.displays.first else {
            throw RecorderError.displayNotFound
        }

        let streamConfiguration = SCStreamConfiguration()
        let pixels = Self.pixelSize(of: display)
        let size = ScreenCaptureSize.outputSize(
            pixelWidth: pixels.width,
            pixelHeight: pixels.height,
            quality: configuration.quality
        )
        streamConfiguration.width = size.width
        streamConfiguration.height = size.height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfiguration.showsCursor = true
        streamConfiguration.showMouseClicks = configuration.showsClicks
        streamConfiguration.capturesAudio = false
        streamConfiguration.captureMicrophone = configuration.includeMicrophone
        if configuration.includeMicrophone {
            streamConfiguration.microphoneCaptureDeviceID = configuration.microphoneID
                ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        }

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.outputFileType = .mov
        if recordingConfiguration.availableVideoCodecTypes.contains(.hevc) {
            recordingConfiguration.videoCodecType = .hevc
        }

        // Windows whose sharing type is .none (the notch, when "hide from
        // screen recordings" is on) are left out by the system already.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        // Frames go to the recording output; these no-op outputs only keep
        // ScreenCaptureKit from logging every frame as dropped.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if configuration.includeMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
        }
        try stream.addRecordingOutput(recordingOutput)

        lock.withLock {
            self.stream = stream
            self.recordingOutput = recordingOutput
            self.outputURL = url
            self.isFinished = false
        }
        do {
            try await stream.startCapture()
        } catch {
            lock.withLock {
                self.stream = nil
                self.recordingOutput = nil
                self.isFinished = true
            }
            throw error
        }
    }

    /// Stops capturing and returns the finished file.
    func stop() async throws -> URL {
        guard let stream = lock.withLock({ self.stream }) else {
            throw RecorderError.notRecording
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            lock.withLock { self.stopContinuation = continuation }
            stream.stopCapture { [weak self] error in
                guard let self else { return }
                if let error {
                    self.finish(.failure(error))
                } else {
                    // The recording output normally reports the finished file
                    // first; this only covers it never doing so.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        self.finishWithFileIfPending(error: nil)
                    }
                }
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let pending: (continuation: CheckedContinuation<URL, Error>?, url: URL?)? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            let continuation = stopContinuation
            stopContinuation = nil
            stream = nil
            recordingOutput = nil
            return (continuation, outputURL)
        }
        guard let pending else { return }
        if let continuation = pending.continuation {
            continuation.resume(with: result)
            return
        }
        switch result {
        case .success(let url):
            onUnexpectedFinish(url, nil)
        case .failure(let error):
            onUnexpectedFinish(nil, error)
        }
    }

    /// Ends a recording whose file may still be fine even though no "did
    /// finish" callback arrived.
    private func finishWithFileIfPending(error: Error?) {
        guard let url = lock.withLock({ isFinished ? nil : outputURL }) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            finish(.success(url))
        } else {
            finish(.failure(error ?? RecorderError.notRecording))
        }
    }

    private static func pixelSize(of display: SCDisplay) -> (width: Int, height: Int) {
        if let mode = CGDisplayCopyDisplayMode(display.displayID), mode.pixelWidth > 0, mode.pixelHeight > 0 {
            return (mode.pixelWidth, mode.pixelHeight)
        }
        return (display.width, display.height)
    }
}

@available(macOS 15.0, *)
extension ScreenRecorder: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        guard let url = lock.withLock({ outputURL }) else { return }
        finish(.success(url))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(error))
    }
}

@available(macOS 15.0, *)
extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The recording output usually still closes the file properly;
        // give it a moment before deciding what was saved.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finishWithFileIfPending(error: error)
        }
    }
}

@available(macOS 15.0, *)
extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}
