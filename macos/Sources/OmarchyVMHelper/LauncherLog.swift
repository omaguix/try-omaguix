import Foundation
import os

/// Keeps the launcher's stderr (run-qemu-gpu.sh and QEMU) after the app is
/// gone. A Finder launch sends the helper's own stderr to /dev/null, so this
/// file and the unified log are the only record of why a launch failed.
///
/// Each launcher run starts a new file and moves the previous one to `.1`; a
/// run that writes more than `maximumBytes` rotates the same way, so the two
/// files never hold more than twice that.
final class LauncherLog: @unchecked Sendable {
    static let maximumBytes = 1_024 * 1_024

    let url: URL
    private let maximumBytes: Int
    private let logger: Logger
    private let lock = NSLock()
    private var handle: FileHandle?
    private var writtenBytes = 0

    /// `subsystem` is the unified log's: the app's bundle identifier.
    init(url: URL, maximumBytes: Int = LauncherLog.maximumBytes, subsystem: String) {
        self.url = url
        self.maximumBytes = maximumBytes
        logger = Logger(subsystem: subsystem, category: "launcher")
    }

    /// `~/Library/Logs/<the identity's logs directory>/launcher.log`, where
    /// Console lists it under Log Reports.
    static func defaultURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        identity: AppIdentity = .main
    ) -> URL {
        home.appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(identity.logsDirectory, isDirectory: true)
            .appendingPathComponent("launcher.log")
    }

    var rotatedURL: URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".1")
    }

    func beginRun() {
        lock.lock()
        defer { lock.unlock() }
        rotate()
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        logger.notice("\(String(decoding: data, as: UTF8.self), privacy: .public)")
        lock.lock()
        defer { lock.unlock() }
        if handle == nil || writtenBytes >= maximumBytes {
            rotate()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            writtenBytes += data.count
        } catch {
            logger.error("cannot write \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            self.handle = nil
        }
    }

    /// Diagnostics must never stop a launch, so failures here only reach the
    /// unified log and leave the file closed.
    private func rotate() {
        try? handle?.close()
        handle = nil
        writtenBytes = 0
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: rotatedURL)
                try fileManager.moveItem(at: url, to: rotatedURL)
            }
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: url)
        } catch {
            logger.error("cannot open \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The alert text for a launcher run that failed without a more specific
/// explanation: its last messages and where the whole log is, instead of
/// advice to reinstall that rarely matches the cause.
enum LauncherFailureReport {
    static let tailLineCount = 8

    static func detail(summary: String, standardError: String, logURL: URL?) -> String {
        var parts = [summary]
        let tail = lastLines(of: standardError, count: tailLineCount)
        if tail.isEmpty {
            parts.append("It printed no messages.")
        } else {
            parts.append("Its last messages:\n\n" + tail)
        }
        if let logURL {
            parts.append("The full log is \(displayPath(logURL)).")
        }
        return parts.joined(separator: "\n\n")
    }

    static func lastLines(of text: String, count: Int) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(count)
            .joined(separator: "\n")
    }

    static func displayPath(
        _ url: URL,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        let path = url.path
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
