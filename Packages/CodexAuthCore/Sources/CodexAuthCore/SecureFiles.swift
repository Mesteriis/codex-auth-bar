import CryptoKit
import Darwin
import Foundation

public enum StorageError: Error, Equatable, Sendable {
    case concurrentModification
    case unsafePath
    case cannotOpen(String)
    case cannotWrite(String)
    case recoveryRequired
}

public struct FileFingerprint: Equatable, Sendable {
    public var exists: Bool
    public var inode: UInt64
    public var size: UInt64
    public var modifiedAt: TimeInterval
    public var sha256: String

    public static let missing = FileFingerprint(exists: false, inode: 0, size: 0, modifiedAt: 0, sha256: "")
}

enum SecureFiles {
    static func ensurePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(url.path, 0o700) == 0 else { throw StorageError.cannotWrite(url.path) }
    }

    static func fingerprint(_ url: URL) throws -> FileFingerprint {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            exists: true,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? UInt64(data.count),
            modifiedAt: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    static func atomicWrite(_ data: Data, to destination: URL, mode: mode_t = 0o600) throws {
        try ensurePrivateDirectory(destination.deletingLastPathComponent())
        let name = ".\(destination.lastPathComponent).tmp.\(UUID().uuidString)"
        let temporary = destination.deletingLastPathComponent().appending(path: name)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else { throw StorageError.cannotOpen(temporary.path) }
        var succeeded = false
        defer {
            close(descriptor)
            if !succeeded { unlink(temporary.path) }
        }
        try data.withUnsafeBytes { bytes in
            var remaining = bytes.count
            var pointer = bytes.baseAddress
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                guard count > 0 else { throw StorageError.cannotWrite(temporary.path) }
                remaining -= count
                pointer = pointer?.advanced(by: count)
            }
        }
        guard fsync(descriptor) == 0 else { throw StorageError.cannotWrite(temporary.path) }
        guard rename(temporary.path, destination.path) == 0 else { throw StorageError.cannotWrite(destination.path) }
        guard chmod(destination.path, mode) == 0 else { throw StorageError.cannotWrite(destination.path) }
        let directoryDescriptor = open(destination.deletingLastPathComponent().path, O_RDONLY)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            close(directoryDescriptor)
        }
        succeeded = true
    }

    static func copyPreservingDestinationMode(_ data: Data, to destination: URL) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let existingMode = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value
        try atomicWrite(data, to: destination, mode: mode_t(existingMode ?? 0o600))
    }

    static func uniqueBackupURL(in directory: URL, baseName: String, date: Date = .now) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "\(baseName).bak.\(formatter.string(from: date))"
        var candidate = directory.appending(path: stem)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(stem).\(suffix)")
            suffix += 1
        }
        return candidate
    }

    static func backupIfChanged(current: URL, replacement: Data, directory: URL, baseName: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: current.path) else { return nil }
        let existing = try Data(contentsOf: current)
        guard existing != replacement else { return nil }
        let backup = uniqueBackupURL(in: directory, baseName: baseName)
        try atomicWrite(existing, to: backup)
        try pruneBackups(in: directory, baseName: baseName, keeping: 5)
        return backup
    }

    static func pruneBackups(in directory: URL, baseName: String, keeping count: Int) throws {
        let prefix = "\(baseName).bak."
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }
        let sorted = try urls.sorted {
            let left = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let right = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return left > right
        }
        for url in sorted.dropFirst(count) { try FileManager.default.removeItem(at: url) }
    }
}
