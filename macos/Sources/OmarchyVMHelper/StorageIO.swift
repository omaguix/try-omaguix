import CryptoKit
import Darwin
import Foundation

/// Small storage primitives shared by the launcher. Transaction ordering and
/// workspace locking stay in qemu-persistent-storage.sh.
enum StorageIO {
    static func sha256(path: String) throws -> String {
        let handle: FileHandle
        if path == "-" {
            handle = .standardInput
        } else {
            let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw HelperError.io("Cannot open file for SHA-256: \(path)") }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                close(fd)
                throw HelperError.io("SHA-256 requires a regular file: \(path)")
            }
            handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        }
        defer { if path != "-" { try? handle.close() } }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 8 * 1024 * 1024), !data.isEmpty {
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Deallocates every run of all-zero file system blocks, so they read back
    /// as the same zeros but take no space. APFS fills a gap shorter than
    /// about 16 MiB between two writes with allocated zeros, so writers that
    /// merely seek over zeros (`zstd --sparse`, `dd conv=sparse`) leave most
    /// of a disk image's free space allocated; punching after the write does
    /// not depend on that heuristic.
    static func punchZeroHoles(path: String) throws {
        let fd = open(path, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw HelperError.io("Cannot open file to punch holes: \(path)") }
        defer { close(fd) }
        var info = stat()
        var volume = statfs()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o600, info.st_nlink == 1,
              fstatfs(fd, &volume) == 0, volume.f_bsize > 0 else {
            throw HelperError.io("Unsafe file to punch holes: \(path)")
        }
        let block = Int(volume.f_bsize)
        let chunk = max(block, 8 * 1024 * 1024 / block * block)
        let zeros = [UInt8](repeating: 0, count: block)
        var buffer = [UInt8](repeating: 0, count: chunk)
        var offset: off_t = 0
        var runStart: off_t?

        func punch(upTo end: off_t) throws {
            guard let start = runStart, end > start else { return }
            var hole = fpunchhole(fp_flags: 0, reserved: 0, fp_offset: start, fp_length: end - start)
            guard fcntl(fd, F_PUNCHHOLE, &hole) == 0 else {
                throw HelperError.io("Cannot punch a hole in \(path) (errno \(errno))")
            }
            runStart = nil
        }

        while true {
            let count = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, chunk, offset) }
            if count < 0 {
                guard errno == EINTR else { throw HelperError.io("Cannot read \(path) (errno \(errno))") }
                continue
            }
            // A partial last block is never punched; it stays data.
            let whole = count / block * block
            guard whole > 0 else { break }
            for start in stride(from: 0, to: whole, by: block) {
                let zero = buffer.withUnsafeBytes { memcmp($0.baseAddress! + start, zeros, block) == 0 }
                if zero {
                    if runStart == nil { runStart = offset + off_t(start) }
                } else {
                    try punch(upTo: offset + off_t(start))
                }
            }
            offset += off_t(whole)
            if whole < count { break }
        }
        try punch(upTo: offset)
        guard fsync(fd) == 0 else { throw HelperError.io("Cannot flush \(path) (errno \(errno))") }
    }

    /// Callers list newly written files before their containing directory,
    /// then sync the parent again after publishing with rename. Syncing only
    /// a directory would not flush the contents of the files inside it.
    static func sync(paths: [String]) throws {
        for path in paths {
            let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw HelperError.io("Cannot open storage checkpoint: \(path)") }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == getuid(),
                  (info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o7777 == 0o700)
                    || (info.st_mode & S_IFMT == S_IFREG && info.st_mode & 0o7777 == 0o600
                        && info.st_nlink == 1) else {
                throw HelperError.io("Unsafe storage checkpoint: \(path)")
            }
            while fsync(fd) != 0 {
                guard errno == EINTR else {
                    throw HelperError.io("Cannot flush storage checkpoint: \(path) (errno \(errno))")
                }
            }
        }
    }
}
