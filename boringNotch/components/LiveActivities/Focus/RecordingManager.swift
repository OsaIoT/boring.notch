//
//  RecordingManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Owns Focus recordings: permissions, where the file goes, start / pause /
//  stop for the webcam, the screen or both (with the webcam bubble),
//  markers, and what happens once the video is saved.
//

import AVFoundation
import AppKit
import Defaults
import Foundation

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    /// Screen recording uses ScreenCaptureKit's SCRecordingOutput.
    static var canRecordScreen: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    enum Failure: Equatable {
        case permission(FocusPermission)
        case noSource
        case message(String)
    }

    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case paused
        case finishing
        case saved(URL)
        case failed(Failure)
    }

    private struct ScreenRecordingUnavailable: LocalizedError {
        var errorDescription: String? { String(localized: "Screen recording needs macOS 15 or later.") }
    }

    @Published private(set) var phase: Phase = .idle
    /// What the current (or last) recording captures.
    @Published private(set) var activeSource: RecordingSource?
    /// Recording time, pauses excluded: the same model as the stopwatch.
    @Published private(set) var clock = StopwatchState()
    @Published private(set) var markers: [RecordingMarker] = []
    @Published private(set) var lastRecording: URL?

    /// The mirror's camera. Stopped while a recording uses the camera, so a
    /// second session can't change the camera's format mid-video.
    weak var mirrorCamera: CameraModel?

    private lazy var cameraRecorder = CameraRecorder { [weak self] url, error in
        Task { @MainActor in
            self?.recordingEndedUnexpectedly(url: url, error: error)
        }
    }
    /// A ScreenRecorder on macOS 15+, typed loosely so this class still
    /// loads on macOS 14.
    private var screenRecorderStorage: AnyObject?
    private let bubble = CameraBubbleController()
    private var folder: RecordingFolder?
    private var phaseResetTask: Task<Void, Never>?

    private init() {}

    var isRecording: Bool { phase == .recording || phase == .paused }
    /// From the moment a recording is requested until its file is saved.
    var isBusy: Bool { phase == .starting || phase == .finishing || isRecording }
    var usesCamera: Bool { isBusy && activeSource?.usesCamera == true }
    /// Only webcam recordings can pause: SCRecordingOutput has no pause.
    var canPause: Bool { activeSource == .camera }
    /// Whether the closed notch shows the recording pill (including the
    /// short "saved" / "failed" confirmations).
    var showsInNotch: Bool { phase != .idle }
    /// The recorder's own preview layer, to host as-is (see CameraRecorder).
    var previewLayer: AVCaptureVideoPreviewLayer? {
        isRecording && activeSource?.usesCamera == true ? cameraRecorder.previewLayer : nil
    }

    /// What the next recording will capture, from the Focus tab's toggles.
    var selectedSource: RecordingSource? {
        RecordingSource(
            camera: Defaults[.focusRecordCamera],
            screen: Defaults[.focusRecordScreen] && Self.canRecordScreen
        )
    }

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isBusy else { return }
        phaseResetTask?.cancel()
        phase = .starting
        Task { await beginRecording() }
    }

    func stop() {
        guard isRecording else { return }
        Task { await endRecording() }
    }

    func togglePause() {
        guard canPause else { return }
        switch phase {
        case .recording:
            cameraRecorder.pause()
            clock.pause(at: Date())
            phase = .paused
        case .paused:
            cameraRecorder.resume()
            clock.start(at: Date())
            phase = .recording
        default:
            break
        }
    }

    func addMarker() {
        guard isRecording else { return }
        markers.append(RecordingMarker(index: markers.count + 1, time: clock.elapsed(at: Date())))
    }

    /// Lets a quitting app finish the file first; an interrupted movie file
    /// can't be played.
    func finishBeforeQuitting() async {
        if isRecording {
            await endRecording()
        }
    }

    func openLastRecording() {
        guard let url = lastRecording else { return }
        withFolderAccess { NSWorkspace.shared.open(url) }
    }

    func revealLastRecording() {
        guard let url = lastRecording else { return }
        withFolderAccess { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// The screen picked in Settings, or the one with the pointer.
    static func targetScreen() -> NSScreen? {
        if let id = Defaults[.focusDisplayID],
           let screen = NSScreen.screens.first(where: { $0.cgDisplayID == CGDirectDisplayID(truncatingIfNeeded: id) }) {
            return screen
        }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: - Recording lifecycle

    private func beginRecording() async {
        guard let source = selectedSource else {
            fail(.noSource)
            return
        }
        activeSource = source
        let includeMicrophone = Defaults[.focusRecordMicrophone]

        var needed: [FocusPermission] = []
        if source.usesCamera { needed.append(.camera) }
        if includeMicrophone { needed.append(.microphone) }
        if source.usesScreen { needed.append(.screen) }
        for permission in needed {
            guard await permission.ensureAccess() else {
                fail(.permission(permission))
                return
            }
        }

        do {
            let folder = try RecordingLibrary.openFolder()
            self.folder = folder
            let url = RecordingLibrary.movieURL(in: folder.url, source: source, date: Date())
            let screen = Self.targetScreen()
            if source.usesCamera {
                mirrorCamera?.stopSession()
            }

            switch source {
            case .camera:
                try await cameraRecorder.start(cameraConfiguration(includeMicrophone: includeMicrophone), to: url)
                if Defaults[.focusBubbleInCameraMode] {
                    bubble.show(previewLayer: cameraRecorder.bubblePreviewLayer, on: screen)
                }
            case .screen:
                try await startScreenRecording(to: url, on: screen, includeMicrophone: includeMicrophone)
            case .screenAndCamera:
                // The camera only feeds the bubble; the microphone goes
                // through the screen recording.
                try await cameraRecorder.startPreview(cameraConfiguration(includeMicrophone: false))
                bubble.show(previewLayer: cameraRecorder.bubblePreviewLayer, on: screen)
                do {
                    try await startScreenRecording(to: url, on: screen, includeMicrophone: includeMicrophone)
                } catch {
                    stopCameraExtras()
                    throw error
                }
            }
            markers = []
            clock = StopwatchState()
            clock.start(at: Date())
            phase = .recording
            Log.general.info("Focus recording started: \(source.rawValue, privacy: .public)")
        } catch {
            releaseFolder()
            fail(.message(error.localizedDescription))
        }
    }

    private func endRecording() async {
        let duration = clock.elapsed(at: Date())
        clock.pause(at: Date())
        phase = .finishing
        do {
            let url: URL
            if activeSource?.usesScreen == true {
                url = try await stopScreenRecording()
            } else {
                url = try await cameraRecorder.stop()
            }
            stopCameraExtras()
            didSave(url, duration: duration)
        } catch {
            stopCameraExtras()
            releaseFolder()
            fail(.message(error.localizedDescription))
        }
    }

    private func recordingEndedUnexpectedly(url: URL?, error: Error?) {
        guard isRecording else { return }
        let nsError = error as NSError?
        Log.general.error(
            "Focus recording ended on its own after \(self.clock.elapsed(at: Date()), privacy: .public)s: \(nsError?.domain ?? "no error", privacy: .public) \(nsError?.code ?? 0, privacy: .public) \(nsError?.localizedDescription ?? "", privacy: .public)"
        )
        let duration = clock.elapsed(at: Date())
        clock.pause(at: Date())
        stopCameraExtras()
        if let url {
            didSave(url, duration: duration)
        } else {
            releaseFolder()
            fail(.message(error?.localizedDescription ?? String(localized: "The recording stopped unexpectedly.")))
        }
    }

    private func didSave(_ url: URL, duration: TimeInterval) {
        writeMarkers(for: url, duration: duration)
        if Defaults[.focusAddRecordingsToShelf] {
            addToShelf(url)
        }
        releaseFolder()
        lastRecording = url
        phase = .saved(url)
        Log.general.info("Focus recording saved")
        if Defaults[.focusOpenRecordingWhenDone] {
            openLastRecording()
        }
        resetPhase(after: .seconds(4))
    }

    private func fail(_ failure: Failure) {
        phase = .failed(failure)
        Log.general.error("Focus recording failed: \(String(describing: failure), privacy: .public)")
        resetPhase(after: .seconds(8))
    }

    private func resetPhase(after delay: Duration) {
        phaseResetTask?.cancel()
        phaseResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.phase = .idle
        }
    }

    // MARK: - Camera and screen

    private func cameraConfiguration(includeMicrophone: Bool) -> CameraRecorder.Configuration {
        CameraRecorder.Configuration(
            cameraID: Defaults[.focusCameraID],
            microphoneID: Defaults[.focusMicrophoneID],
            includeMicrophone: includeMicrophone,
            quality: Defaults[.focusRecordingQuality],
            mirrorPreview: Defaults[.isMirrored]
        )
    }

    /// Hides the bubble and, for screen + webcam, stops the preview-only
    /// camera session.
    private func stopCameraExtras() {
        bubble.hide()
        if activeSource == .screenAndCamera {
            cameraRecorder.stopPreview()
        }
    }

    private func startScreenRecording(to url: URL, on screen: NSScreen?, includeMicrophone: Bool) async throws {
        guard #available(macOS 15.0, *) else { throw ScreenRecordingUnavailable() }
        let configuration = ScreenRecorder.Configuration(
            displayID: screen?.cgDisplayID ?? CGMainDisplayID(),
            includeMicrophone: includeMicrophone,
            microphoneID: Defaults[.focusMicrophoneID],
            showsClicks: Defaults[.focusShowClicks],
            quality: Defaults[.focusRecordingQuality]
        )
        try await screenRecorder().start(configuration, to: url)
    }

    private func stopScreenRecording() async throws -> URL {
        guard #available(macOS 15.0, *) else { throw ScreenRecordingUnavailable() }
        return try await screenRecorder().stop()
    }

    @available(macOS 15.0, *)
    private func screenRecorder() -> ScreenRecorder {
        if let recorder = screenRecorderStorage as? ScreenRecorder {
            return recorder
        }
        let recorder = ScreenRecorder { [weak self] url, error in
            Task { @MainActor in
                self?.recordingEndedUnexpectedly(url: url, error: error)
            }
        }
        screenRecorderStorage = recorder
        return recorder
    }

    // MARK: - Files

    private func writeMarkers(for url: URL, duration: TimeInterval) {
        guard !markers.isEmpty else { return }
        let title = url.deletingPathExtension().lastPathComponent
        let document = RecordingLibrary.markersDocument(title: title, duration: duration, markers: markers)
        do {
            try document.write(to: RecordingLibrary.markersURL(for: url), atomically: true, encoding: .utf8)
        } catch {
            Log.general.error("Could not write the Focus markers: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func addToShelf(_ url: URL) {
        do {
            let bookmark = try Bookmark(url: url)
            ShelfStateViewModel.shared.add([ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: false)])
        } catch {
            Log.shelf.error("Could not add the Focus recording to the shelf: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func releaseFolder() {
        folder?.endAccess()
        folder = nil
    }

    /// Opening or revealing a video in a folder picked in Settings needs
    /// that folder's security scope for the duration of the call.
    private func withFolderAccess(_ action: () -> Void) {
        let access = try? RecordingLibrary.openFolder()
        action()
        access?.endAccess()
    }
}
