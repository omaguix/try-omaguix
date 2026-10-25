import Darwin
import Foundation
import Testing
@testable import OmarchyVMHelper

/// Lets the real launcher library lay out a workspace and requires every Swift
/// reader of that layout to find it. The app's disk-space estimates, saved-VM
/// detection, integration cache and size floor only read what the shell writes,
/// so a renamed disk, kind or subdirectory on either side silently turns them
/// into "nothing there" rather than failing.
@Suite("Guest state layout cross-language agreement", .identity(.tryOmaguix))
struct GuestStateLayoutAgreementTests {
    private static let identity = String(repeating: "a", count: 64)
    private static let sourceSHA = String(repeating: "d", count: 64)

    @Test("Swift finds the disk and metadata the launcher writes")
    func swiftReadsLauncherLayout() throws {
        let stateRoot = try temporaryStateRoot()
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        // Foundation drops `/private` when resolving, so resolve both sides alike.
        let launcherDirectory = URL(fileURLWithPath: try layOutWorkspace(in: stateRoot))
            .resolvingSymlinksInPath().path

        let environment = [StorageLocationPolicy.environmentKey: stateRoot.path]
        let storageRoot = try #require(QEMUGPUStorageSpaceEstimate.storageRootURL(environment: environment))
        #expect(storageRoot.resolvingSymlinksInPath().path == launcherDirectory)

        #expect(QEMUGPUStorageSpaceEstimate.hasRecordedPersistentDisk(stateRoot: stateRoot.path))
        #expect(QEMUGPUStorageSpaceEstimate.reclaimableBytes(
            environment: environment,
            bundleIdentity: Self.identity
        ) != nil)

        // run-qemu-gpu.sh keys the cache by the disk's inode, next to `disks/`.
        let cache = try #require(GuestIntegrationCache.url(storageRoot: storageRoot))
        #expect(cache.deletingLastPathComponent().resolvingSymlinksInPath().path == launcherDirectory)
    }

    /// Confirmed in the app on 2026-10-08: the picker looked for the marker in
    /// the chosen folder itself, so a folder the launcher had laid out was
    /// refused as "already has files in it".
    @Test("the picker accepts a folder the launcher laid out, and only by its marker")
    func pickerAcceptsLauncherLayout() throws {
        let stateRoot = try temporaryStateRoot()
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        _ = try layOutWorkspace(in: stateRoot)
        let container = stateRoot.resolvingSymlinksInPath().path
        // Far more than the probe reports free, so acceptance also proves the
        // picker found the saved VM and skipped the new-VM space floor.
        let metrics = BundledGuestMetrics(
            identity: Self.identity,
            sourceDiskBytes: 1 << 40,
            workingDiskBytes: 1 << 40
        )
        let probe = LayoutVolumeProbe()

        let resolution = try StorageLocationPolicy.validate(container, metrics: metrics, probe: probe)
        #expect(resolution.stateRoot == container)
        #expect(resolution.spaceWarning == nil)

        // Without the marker the same files are just a folder with content in it.
        try FileManager.default.removeItem(at: GuestStateLayout.rootMarker(inStateRoot: stateRoot))
        #expect(throws: StorageLocationPolicyError.notEmpty(container)) {
            try StorageLocationPolicy.validate(container, metrics: metrics, probe: probe)
        }
    }

    @Test("the layout names match the launcher's constants")
    func layoutConstants() throws {
        let library = try String(contentsOf: Self.library, encoding: .utf8)
        #expect(library.contains("\nQPS_STATE_SUBDIRECTORY=\(GuestStateLayout.subdirectory)\n"))
        #expect(library.contains("\nQPS_DISK_NAME=\(GuestStateLayout.diskName)\n"))
        #expect(library.contains("\nQEMU_PERSISTENT_STORAGE_KIND='\(GuestStateLayout.persistentDiskKind)'\n"))
    }

    private static let library = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("qemu-persistent-storage.sh")

    /// Prepares the state root and records a `current` disk with the library's
    /// own functions, checks the disk with the launcher's
    /// own validation, and returns the directory the launcher resolved.
    private func layOutWorkspace(in stateRoot: URL) throws -> String {
        let script = #"""
        set -e
        source "$1" >/dev/null
        export OMARCHY_QEMU_GPU_STATE_ROOT=$2
        _qps_prepare_state_root
        workspace="$QEMU_PERSISTENT_STORAGE_DISKS_ROOT/current"
        mkdir -m 700 "$workspace"
        _qps_write_metadata "$workspace/metadata.json" "$3" "$4" 1
        (umask 077; printf 'disk' >"$workspace/$QPS_DISK_NAME")
        _qps_validate_recorded_workspace "$workspace"
        printf '%s' "$QEMU_PERSISTENT_STORAGE_ROOT"
        """#
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "bash", Self.library.path, stateRoot.path, Self.identity, Self.sourceSHA]
        process.standardOutput = output
        try process.run()
        let directory = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return directory
    }

    private struct LayoutVolumeProbe: VolumeProbing {
        func capabilities(at url: URL) throws -> VolumeCapabilities {
            VolumeCapabilities(
                typeName: VolumeCapabilities.apfsTypeName,
                volumeName: "Test Drive",
                supportsCloning: true,
                supportsSparseFiles: true,
                isLocal: true,
                isInternal: true,
                availableBytes: 0
            )
        }
    }

    private func temporaryStateRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omarchy-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(Darwin.chmod(url.path, 0o700) == 0)
        return url
    }
}
