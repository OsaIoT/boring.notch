//
//  RecordingLibrary.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Where Focus recordings go and what they're called, plus the markdown
//  file with the session's markers written next to each video.
//

import Defaults
import Foundation

/// What a Focus recording captures.
enum RecordingSource: String, Sendable {
    case camera
    case screen
    case screenAndCamera

    /// From the Focus tab's Webcam and Screen toggles; nil when both are off.
    init?(camera: Bool, screen: Bool) {
        switch (camera, screen) {
        case (true, false): self = .camera
        case (false, true): self = .screen
        case (true, true): self = .screenAndCamera
        case (false, false): return nil
        }
    }

    var usesCamera: Bool { self != .screen }
    var usesScreen: Bool { self != .camera }

    /// Used in file names, so it follows the app language.
    var fileLabel: String {
        switch self {
        case .camera: String(localized: "Webcam")
        case .screen: String(localized: "Screen")
        case .screenAndCamera: String(localized: "Screen+Webcam")
        }
    }
}

enum RecordingQuality: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case hd1080
    case hd720

    var id: Self { self }
}

struct RecordingMarker: Codable, Equatable, Sendable {
    /// 1-based, in the order markers were added.
    let index: Int
    /// Seconds from the start of the video.
    let time: TimeInterval
}

/// A folder recordings are written to: security-scoped when the user picked
/// it in Settings, so access has to be released once the file is done.
struct RecordingFolder {
    let url: URL
    let isSecurityScoped: Bool

    func endAccess() {
        if isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum RecordingLibrary {
    static let defaultFolderName = "Boring Notch"

    /// `~/Movies/Boring Notch` in the real home folder. Inside the sandbox,
    /// FileManager would point at the app's container instead.
    static var defaultFolder: URL {
        realHomeDirectory
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent(defaultFolderName, isDirectory: true)
    }

    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// The folder chosen in Settings, or the default one (created if
    /// needed). Starts security-scoped access when required: call
    /// `endAccess()` once the file is written.
    static func openFolder() throws -> RecordingFolder {
        if let url = resolveCustomFolder(), url.startAccessingSecurityScopedResource() {
            return RecordingFolder(url: url, isSecurityScoped: true)
        }
        let folder = defaultFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return RecordingFolder(url: folder, isSecurityScoped: false)
    }

    /// The folder as shown in Settings, with the home folder abbreviated.
    static func displayPath(for bookmark: Data?) -> String {
        let url = bookmark.flatMap(resolve) ?? defaultFolder
        let home = realHomeDirectory.path
        guard url.path.hasPrefix(home) else { return url.path }
        return "~" + url.path.dropFirst(home.count)
    }

    /// e.g. `2026-11-23 21.30 Webcam.mov`, made unique within `folder`.
    static func movieURL(
        in folder: URL,
        source: RecordingSource,
        date: Date,
        calendar: Calendar = .current,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let base = "\(timestamp(date, calendar: calendar)) \(source.fileLabel)"
        var candidate = folder.appendingPathComponent(base).appendingPathExtension("mov")
        var counter = 2
        while fileExists(candidate) {
            candidate = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension("mov")
            counter += 1
        }
        return candidate
    }

    static func markersURL(for movie: URL) -> URL {
        movie.deletingPathExtension().appendingPathExtension("md")
    }

    /// The markdown written next to the video: title, length, and one line
    /// per marker with its position in the video.
    static func markersDocument(title: String, duration: TimeInterval, markers: [RecordingMarker]) -> String {
        var lines = [
            "# \(title)",
            "",
            String(localized: "Duration: \(StopwatchState.format(duration))"),
            ""
        ]
        lines += markers.map { "- \(clock($0.time)) — Marker \($0.index)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `yyyy-MM-dd HH.mm`: sorts by date in Finder and is valid in file names.
    static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(parts.year ?? 0)-\(pad(parts.month))-\(pad(parts.day)) \(pad(parts.hour)).\(pad(parts.minute))"
    }

    /// `hh:mm:ss`, the format video players seek to.
    static func clock(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return "\(pad(total / 3600)):\(pad(total % 3600 / 60)):\(pad(total % 60))"
    }

    private static func resolveCustomFolder() -> URL? {
        guard let bookmark = Defaults[.focusRecordingFolderBookmark] else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            Log.general.error("The Focus recording folder can't be found any more; using the default folder")
            return nil
        }
        if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
            Defaults[.focusRecordingFolderBookmark] = fresh
        }
        return url
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private static func pad(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : "\(value)"
    }
}
