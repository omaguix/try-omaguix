import Foundation

/// One saved VM disk the launcher listed when the data folder held more than
/// one (`_qps_report_saved_vm_candidates` in qemu-persistent-storage.sh).
struct SavedVMCandidate: Equatable {
    /// `current`, or the factory identity naming a development disk that
    /// `make run-isolated` created beside it.
    let name: String
    /// The factory image the disk was created from.
    let factoryIdentity: String
    let schemaVersion: Int
    let capacityBytes: Int64
    let allocatedBytes: Int64
    /// When the disk was last written, which is when the VM last ran.
    let lastUsed: Date

    var isCurrent: Bool { name == SavedVMChoice.currentName }

    /// Only the storage format this app writes can be kept and launched.
    var isLaunchable: Bool { schemaVersion == SavedVMChoice.supportedSchemaVersion }
}

/// Choosing which of several saved VMs to keep. The launcher owns the disks:
/// it lists them when a launch stops, and `--keep-saved-vm NAME` keeps one as
/// `current` and renames the others into an archive in the same data folder.
enum SavedVMChoice {
    static let keepOption = "--keep-saved-vm"
    static let currentName = "current"
    static let supportedSchemaVersion = 2

    private static let candidatePrefix = "[qemu-gpu] Saved VM: "
    private static let countPrefix = "[qemu-gpu] Saved VMs: "
    private static let archivePrefix = "[qemu-gpu] Archived saved VMs: "

    /// The launcher's complete list, or nil when there is none or its closing
    /// count disagrees, as it would in a truncated stderr tail. The start menu
    /// then falls back to offering only Reset rather than a partial choice.
    static func candidates(standardError: String) -> [SavedVMCandidate]? {
        var candidates: [SavedVMCandidate] = []
        var count: Int?
        for line in standardError.split(separator: "\n") {
            if line.hasPrefix(candidatePrefix) {
                guard let candidate = candidate(line.dropFirst(candidatePrefix.count)) else { return nil }
                candidates.append(candidate)
            } else if line.hasPrefix(countPrefix) {
                count = Int(line.dropFirst(countPrefix.count))
            }
        }
        guard let count, count == candidates.count, count > 1,
              Set(candidates.map(\.name)).count == count else { return nil }
        return candidates
    }

    private static func candidate(_ fields: Substring) -> SavedVMCandidate? {
        let parts = fields.split(separator: " ")
        guard parts.count == 6,
              parts[0] == currentName || isIdentity(parts[0]),
              isIdentity(parts[1]),
              let schema = Int(parts[2]),
              let capacity = Int64(parts[3]), capacity > 0,
              let allocated = Int64(parts[4]), allocated >= 0,
              let modified = TimeInterval(parts[5]) else { return nil }
        return SavedVMCandidate(
            name: String(parts[0]),
            factoryIdentity: String(parts[1]),
            schemaVersion: schema,
            capacityBytes: capacity,
            allocatedBytes: allocated,
            lastUsed: Date(timeIntervalSince1970: modified)
        )
    }

    /// Where the launcher moved the saved VMs it did not keep, if it moved any.
    static func archivePath(standardError: String) -> String? {
        standardError.split(separator: "\n")
            .last { $0.hasPrefix(archivePrefix) }
            .map { String($0.dropFirst(archivePrefix.count)) }
    }

    /// The launchable VM used most recently, which the chooser preselects.
    static func preferredCandidate(in candidates: [SavedVMCandidate]) -> SavedVMCandidate? {
        candidates.filter(\.isLaunchable).max { $0.lastUsed < $1.lastUsed }
    }

    static func title(for candidate: SavedVMCandidate) -> String {
        candidate.isCurrent
            ? "Main VM"
            : "Development VM \(candidate.name.prefix(12))"
    }

    /// Factory image, size, last use and how the disk was created, from what
    /// the storage layer records.
    static func detail(
        for candidate: SavedVMCandidate,
        bundledIdentity: String?,
        dateFormatter: DateFormatter = lastUsedFormatter
    ) -> String {
        let origin = candidate.isCurrent
            ? "The VM a normal launch uses."
            : "Created by a development launch (make run-isolated)."
        let factory = candidate.factoryIdentity == bundledIdentity
            ? "Factory image of this app version."
            : "Factory image \(candidate.factoryIdentity.prefix(12)) from another app version."
        let size = "\(StorageLocationPolicy.format(bytes: candidate.allocatedBytes)) used of \(StorageLocationPolicy.format(bytes: candidate.capacityBytes))."
        let used = "Last used \(dateFormatter.string(from: candidate.lastUsed))."
        var detail = [origin, factory, size, used].joined(separator: " ")
        if !candidate.isLaunchable {
            detail += " Uses a storage format this version can’t open."
        }
        return detail
    }

    static func keptMessage(for candidate: SavedVMCandidate, archivePath: String?, homeDirectory: String) -> String {
        var message = "\(title(for: candidate)) is now the VM Roguix launches."
        if let archivePath {
            let display = StorageLocationPolicy.displayPath(archivePath, homeDirectory: homeDirectory)
            message += " The other saved VMs were moved, unchanged, to \(display). Roguix no longer uses or resets them; delete that folder when you no longer need them."
        }
        return message
    }

    static let lastUsedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func isIdentity(_ value: Substring) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }
}
