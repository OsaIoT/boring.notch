//
//  RecordingManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Owns Focus recordings: permissions, where the file goes, start / pause /
//  stop, markers, and what happens once the video is saved.
//

import AVFoundation
import AppKit
import Defaults
import Foundation

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    enum Failure: Equatable {
        case permission(FocusPermission)
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

    @Published private(set) var phase: Phase = .idle
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
    private var folder: RecordingFolder?
    private var phaseResetTask: Task<Void, Never>?

    private init() {}

    var isRecording: Bool { phase == .recording || phase == .paused }
    /// From the moment a recording is requested until its file is saved.
    var isBusy: Bool { phase == .starting || phase == .finishing || isRecording }
    var usesCamera: Bool { isBusy }
    /// Whether the closed notch shows the recording pill (including the
    /// short "saved" / "failed" confirmations).
    var showsInNotch: Bool { phase != .idle }
    /// The recorder's own preview layer, to host as-is (see CameraRecorder).
    var previewLayer: AVCaptureVideoPreviewLayer? { isRecording ? cameraRecorder.previewLayer : nil }

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

    // MARK: - Recording lifecycle

    private func beginRecording() async {
        guard await FocusPermission.camera.ensureAccess() else {
            fail(.permission(.camera))
            return
        }
        let includeMicrophone = Defaults[.focusRecordMicrophone]
        if includeMicrophone {
            guard await FocusPermission.microphone.ensureAccess() else {
                fail(.permission(.microphone))
                return
            }
        }

        do {
            let folder = try RecordingLibrary.openFolder()
            self.folder = folder
            let url = RecordingLibrary.movieURL(in: folder.url, source: .camera, date: Date())
            mirrorCamera?.stopSession()
            let configuration = CameraRecorder.Configuration(
                cameraID: Defaults[.focusCameraID],
                microphoneID: Defaults[.focusMicrophoneID],
                includeMicrophone: includeMicrophone,
                quality: Defaults[.focusRecordingQuality],
                mirrorPreview: Defaults[.isMirrored]
            )
            try await cameraRecorder.start(configuration, to: url)
            markers = []
            clock = StopwatchState()
            clock.start(at: Date())
            phase = .recording
            Log.general.info("Focus recording started")
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
            let url = try await cameraRecorder.stop()
            didSave(url, duration: duration)
        } catch {
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
