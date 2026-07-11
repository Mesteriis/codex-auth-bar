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

public struct FileFingerprint: Codable, Equatable, Sendable {
    public var exists: Bool
    public var inode: UInt64
    public var size: UInt64
    public var modifiedAt: TimeInterval
    public var sha256: String

    public static let missing = FileFingerprint(exists: false, inode: 0, size: 0, modifiedAt: 0, sha256: "")

    enum CodingKeys: String, CodingKey {
        case exists, inode, size, sha256
        case modifiedAt = "modified_at"
    }
}

enum SecureFiles {
    static func ensurePrivateDirectory(_ url: URL) throws {
        var status = stat()
        if lstat(url.path, &status) == 0 {
            guard (status.st_mode & S_IFMT) == S_IFDIR else { throw StorageError.unsafePath }
        } else {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard lstat(url.path, &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else {
                throw StorageError.unsafePath
            }
        }
        guard chmod(url.path, 0o700) == 0 else { throw StorageError.cannotWrite(url.path) }
    }

    static func readRegularFile(_ url: URL, maximumBytes: Int = AuthParser.maximumBytes) throws -> Data {
        let directory = try openParentDirectory(of: url)
        defer { close(directory) }
        let descriptor = openat(directory, url.lastPathComponent, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw StorageError.unsafePath }
            throw StorageError.cannotOpen(url.path)
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size >= 0,
              status.st_size <= maximumBytes
        else { throw StorageError.unsafePath }
        return try read(descriptor, status: status, maximumBytes: maximumBytes, path: url.path)
    }

    static func fingerprint(_ url: URL) throws -> FileFingerprint {
        let directory = try openParentDirectory(of: url)
        defer { close(directory) }
        let descriptor = openat(directory, url.lastPathComponent, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0, errno == ENOENT { return .missing }
        guard descriptor >= 0 else {
            if errno == ELOOP { throw StorageError.unsafePath }
            throw StorageError.cannotOpen(url.path)
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { throw StorageError.unsafePath }
        let data = try read(descriptor, status: status, maximumBytes: AuthParser.maximumBytes, path: url.path)
        return FileFingerprint(
            exists: true,
            inode: UInt64(status.st_ino),
            size: UInt64(status.st_size),
            modifiedAt: TimeInterval(status.st_mtimespec.tv_sec) + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    static func atomicWrite(_ data: Data, to destination: URL, mode: mode_t = 0o600) throws {
        try ensurePrivateDirectory(destination.deletingLastPathComponent())
        let name = ".\(destination.lastPathComponent).tmp.\(UUID().uuidString)"
        let directory = try openParentDirectory(of: destination)
        defer { close(directory) }
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else { throw StorageError.cannotOpen(destination.path) }
        var succeeded = false
        defer {
            close(descriptor)
            if !succeeded { unlinkat(directory, name, 0) }
        }
        try data.withUnsafeBytes { bytes in
            var remaining = bytes.count
            var pointer = bytes.baseAddress
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                guard count > 0 else { throw StorageError.cannotWrite(destination.path) }
                remaining -= count
                pointer = pointer?.advanced(by: count)
            }
        }
        guard fchmod(descriptor, mode) == 0 else { throw StorageError.cannotWrite(destination.path) }
        guard fsync(descriptor) == 0 else { throw StorageError.cannotWrite(destination.path) }
        guard renameat(directory, name, directory, destination.lastPathComponent) == 0 else {
            throw StorageError.cannotWrite(destination.path)
        }
        guard fsync(directory) == 0 else { throw StorageError.cannotWrite(destination.deletingLastPathComponent().path) }
        succeeded = true
    }

    static func copyPreservingDestinationMode(_ data: Data, to destination: URL) throws {
        let directory = try openParentDirectory(of: destination)
        defer { close(directory) }
        var status = stat()
        let found = fstatat(directory, destination.lastPathComponent, &status, AT_SYMLINK_NOFOLLOW) == 0
        let existingMode = found && (status.st_mode & S_IFMT) == S_IFREG ? status.st_mode & 0o777 : 0o600
        try atomicWrite(data, to: destination, mode: existingMode)
    }

    static func removeRegularFile(_ url: URL) throws {
        let directory = try openParentDirectory(of: url)
        defer { close(directory) }
        var status = stat()
        if fstatat(directory, url.lastPathComponent, &status, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw StorageError.cannotOpen(url.path)
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else { throw StorageError.unsafePath }
        guard unlinkat(directory, url.lastPathComponent, 0) == 0,
              fsync(directory) == 0
        else { throw StorageError.cannotWrite(url.path) }
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
        let existing = try readRegularFile(current)
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
        for url in sorted.dropFirst(count) { try removeRegularFile(url) }
    }

    private static func openParentDirectory(of url: URL) throws -> Int32 {
        let parent = url.deletingLastPathComponent()
        let descriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StorageError.unsafePath }
        return descriptor
    }

    private static func read(
        _ descriptor: Int32,
        status: stat,
        maximumBytes: Int,
        path: String
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(Int(status.st_size))
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, max(1, maximumBytes)))
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            guard count >= 0 else { throw StorageError.cannotOpen(path) }
            if count == 0 { break }
            guard result.count + count <= maximumBytes else { throw StorageError.unsafePath }
            result.append(buffer, count: count)
        }
        return result
    }
}
