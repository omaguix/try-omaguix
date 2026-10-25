import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Saved VM choice", .identity(.tryOmaguix))
struct SavedVMChoiceTests {
    private let identityA = String(repeating: "a", count: 64)
    private let identityB = String(repeating: "b", count: 64)

    private func report(_ lines: [String], count: Int?) -> String {
        var text = "qemu-persistent-storage: initialized persistent workspace aaaaaaaaaaaa\n"
        text += lines.map { "[qemu-gpu] Saved VM: \($0)\n" }.joined()
        if let count { text += "[qemu-gpu] Saved VMs: \(count)\n" }
        return text + "qemu-persistent-storage: multiple saved VMs were found; choose the one to keep, or use Reset Omaguix\n"
    }

    @Test("the launcher's complete list becomes the choice")
    func parsesCompleteList() throws {
        let candidates = try #require(SavedVMChoice.candidates(standardError: report([
            "current \(identityA) 2 68719476736 1200000000 1759800000",
            "\(identityB) \(identityB) 2 68719476736 300000000 1759900000",
        ], count: 2)))
        #expect(candidates.map(\.name) == ["current", identityB])
        #expect(candidates[0].isCurrent)
        #expect(candidates[0].factoryIdentity == identityA)
        #expect(candidates[1].capacityBytes == 68_719_476_736)
        #expect(candidates[1].allocatedBytes == 300_000_000)
        #expect(candidates[1].lastUsed == Date(timeIntervalSince1970: 1_759_900_000))
        #expect(SavedVMChoice.preferredCandidate(in: candidates)?.name == identityB)
    }

    @Test("a truncated, malformed, or single-entry list offers no choice")
    func rejectsIncompleteLists() {
        let current = "current \(identityA) 2 100 50 1"
        let other = "\(identityB) \(identityB) 2 100 50 2"
        #expect(SavedVMChoice.candidates(standardError: report([current, other], count: nil)) == nil)
        #expect(SavedVMChoice.candidates(standardError: report([other], count: 2)) == nil)
        #expect(SavedVMChoice.candidates(standardError: report([current], count: 1)) == nil)
        #expect(SavedVMChoice.candidates(standardError: report([current, current], count: 2)) == nil)
        #expect(SavedVMChoice.candidates(standardError: report(
            [current, "../current \(identityB) 2 100 50 2"], count: 2)) == nil)
        #expect(SavedVMChoice.candidates(standardError: report(
            [current, "\(identityB) \(identityB) 2 100 50"], count: 2)) == nil)
        #expect(SavedVMChoice.candidates(standardError: "the saved VM uses an unsupported storage format") == nil)
    }

    @Test("an unsupported disk is listed but cannot be kept")
    func unsupportedDiskIsNotLaunchable() throws {
        let candidates = try #require(SavedVMChoice.candidates(standardError: report([
            "current \(identityA) 1 100 50 9",
            "\(identityB) \(identityB) 2 100 50 1",
        ], count: 2)))
        #expect(!candidates[0].isLaunchable)
        #expect(SavedVMChoice.preferredCandidate(in: candidates)?.name == identityB)
        #expect(SavedVMChoice.detail(for: candidates[0], bundledIdentity: nil).contains("can’t open"))
    }

    @Test("each disk says how it was created, its factory image, size, and last use")
    func describesCandidates() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let current = SavedVMCandidate(
            name: "current", factoryIdentity: identityA, schemaVersion: 2,
            capacityBytes: 64_000_000_000, allocatedBytes: 12_300_000_000,
            lastUsed: Date(timeIntervalSince1970: 0)
        )
        let development = SavedVMCandidate(
            name: identityB, factoryIdentity: identityB, schemaVersion: 2,
            capacityBytes: 64_000_000_000, allocatedBytes: 1_000_000_000,
            lastUsed: Date(timeIntervalSince1970: 0)
        )
        #expect(SavedVMChoice.title(for: current) == "Main VM")
        #expect(SavedVMChoice.title(for: development) == "Development VM bbbbbbbbbbbb")
        let currentDetail = SavedVMChoice.detail(for: current, bundledIdentity: identityA, dateFormatter: formatter)
        #expect(currentDetail.contains("normal launch"))
        #expect(currentDetail.contains("this app version"))
        #expect(currentDetail.contains("12.3 GB used of 64.0 GB"))
        #expect(currentDetail.contains("Last used 1970-01-01 00:00"))
        let developmentDetail = SavedVMChoice.detail(for: development, bundledIdentity: identityA, dateFormatter: formatter)
        #expect(developmentDetail.contains("make run-isolated"))
        #expect(developmentDetail.contains("bbbbbbbbbbbb from another app version"))
    }

    @Test("keeping a VM reports where the others went")
    func reportsArchive() {
        let standardError = "[qemu-gpu] Archived saved VMs: /Users/me/Library/Application Support/Try Omaguix/VM/v1/guix/archive/saved-vms-20261007-120000\n"
        let path = SavedVMChoice.archivePath(standardError: standardError)
        #expect(path == "/Users/me/Library/Application Support/Try Omaguix/VM/v1/guix/archive/saved-vms-20261007-120000")
        #expect(SavedVMChoice.archivePath(standardError: "nothing moved\n") == nil)
        let candidate = SavedVMCandidate(
            name: "current", factoryIdentity: identityA, schemaVersion: 2,
            capacityBytes: 1, allocatedBytes: 1, lastUsed: Date()
        )
        let message = SavedVMChoice.keptMessage(for: candidate, archivePath: path, homeDirectory: "/Users/me")
        #expect(message.contains("~/Library/Application Support/Try Omaguix/VM/v1/guix/archive/saved-vms-20261007-120000"))
        #expect(message.contains("unchanged"))
    }

    @Test("the chooser keeps Reset as one option and says what it erases")
    func chooserText() {
        #expect(StartMenuPresentation.savedVMChoiceDetail.contains("archive"))
        #expect(StartMenuPresentation.savedVMChoiceDetail.contains("reset Omaguix to erase all of them"))
        #expect(StartMenuPresentation.resetErasesSavedVMs(count: 3).contains("3 saved VMs, and Reset erases all of them"))
    }

    @Test("the parser and the launcher agree on the flag and the report lines")
    func launcherContract() throws {
        let launcher = try source(named: "run-qemu-gpu.sh")
        let library = try source(named: "qemu-persistent-storage.sh")
        #expect(launcher.contains("  \(SavedVMChoice.keepOption))\n"))
        #expect(library.contains("printf '[qemu-gpu] Saved VM: %s %s %s %s %s %s\\n'"))
        #expect(library.contains("printf '[qemu-gpu] Saved VMs: %s\\n'"))
        #expect(library.contains("printf '[qemu-gpu] Archived saved VMs: %s\\n'"))
        #expect(library.contains("QEMU_PERSISTENT_STORAGE_SCHEMA=\(SavedVMChoice.supportedSchemaVersion)\n"))
    }

    private func source(named relativePath: String) throws -> String {
        let macosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: macosDirectory.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
