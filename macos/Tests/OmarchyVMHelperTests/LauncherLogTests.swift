import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Launcher log")
struct LauncherLogTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func contents(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test("The log lives with the user's other app logs")
    func defaultLocation() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(LauncherLog.defaultURL(home: home).path == "/Users/example/Library/Logs/Try Roguix/launcher.log")
    }

    @Test("Each run starts a new file and keeps the previous run")
    func runRotation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LauncherLog(url: directory.appendingPathComponent("Logs/launcher.log"))

        log.beginRun()
        log.append(Data("first run\n".utf8))
        log.beginRun()
        log.append(Data("second run\n".utf8))

        #expect(try contents(log.url) == "second run\n")
        #expect(try contents(log.rotatedURL) == "first run\n")
    }

    @Test("A run cannot grow the log past twice its limit")
    func sizeBound() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LauncherLog(url: directory.appendingPathComponent("launcher.log"), maximumBytes: 64)

        log.beginRun()
        for index in 0..<100 {
            log.append(Data("line \(index) of a noisy launcher\n".utf8))
        }

        let current = try Data(contentsOf: log.url).count
        let previous = try Data(contentsOf: log.rotatedURL).count
        #expect(current + previous <= 2 * (64 + 64))
        #expect(try contents(log.url).hasSuffix("line 99 of a noisy launcher\n"))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.sorted() == ["launcher.log", "launcher.log.1"])
    }

    @Test("The supervisor's stderr reaches the log")
    func supervisorWritesLog() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LauncherLog(url: directory.appendingPathComponent("launcher.log"))
        let supervisor = QEMUGPUProcessSupervisor(log: log)

        let status: Int32 = await withCheckedContinuation { continuation in
            do {
                try supervisor.start(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo 'run-qemu-gpu: missing firmware' >&2; exit 3"],
                    environment: [:]
                ) { status in
                    continuation.resume(returning: status)
                }
            } catch {
                Issue.record(error)
                continuation.resume(returning: -1)
            }
        }

        #expect(status == 3)
        #expect(try contents(log.url).contains("run-qemu-gpu: missing firmware"))
    }
}

@Suite("Launcher failure report")
struct LauncherFailureReportTests {
    @Test("The alert quotes the last lines and names the log, without reinstall advice")
    func detail() {
        let standardError = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n\n"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let text = LauncherFailureReport.detail(
            summary: "The app’s virtual machine stopped during startup.",
            standardError: standardError,
            logURL: LauncherLog.defaultURL(home: home)
        )

        #expect(text.hasPrefix("The app’s virtual machine stopped during startup."))
        #expect(text.contains("line 13\nline 14"))
        #expect(text.contains("line 20"))
        #expect(!text.contains("line 12\n"))
        #expect(text.hasSuffix("The full log is ~/Library/Logs/Try Roguix/launcher.log."))
        #expect(!text.localizedCaseInsensitiveContains("reinstall"))
    }

    @Test("A launcher that printed nothing says so")
    func silent() {
        let text = LauncherFailureReport.detail(summary: "Failed.", standardError: " \n", logURL: nil)
        #expect(text == "Failed.\n\nIt printed no messages.")
    }

    @Test("Paths outside home stay absolute")
    func displayPath() {
        let url = URL(fileURLWithPath: "/Users/other/launcher.log")
        #expect(LauncherFailureReport.displayPath(url, home: "/Users/example") == "/Users/other/launcher.log")
        #expect(LauncherFailureReport.displayPath(url, home: "/Users/other") == "~/launcher.log")
    }
}
