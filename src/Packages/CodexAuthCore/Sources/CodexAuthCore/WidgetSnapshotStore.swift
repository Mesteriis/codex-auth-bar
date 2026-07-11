import Foundation

public enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case missing
    case unsupportedSchema(Int)
    case invalidJSON
}

public struct WidgetSnapshotStore: Sendable {
    public let containerURL: URL

    public var snapshotURL: URL {
        containerURL.appending(path: "widget/snapshot.json")
    }

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public func load() throws -> WidgetSnapshot {
        guard try SecureFiles.regularFileExists(snapshotURL) else {
            throw WidgetSnapshotStoreError.missing
        }
        let data = try SecureFiles.readRegularFile(snapshotURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (object["schema_version"] as? NSNumber)?.intValue
        else { throw WidgetSnapshotStoreError.invalidJSON }
        guard version <= WidgetSnapshot.currentSchemaVersion else {
            throw WidgetSnapshotStoreError.unsupportedSchema(version)
        }
        return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try SecureFiles.atomicWrite(encoder.encode(snapshot), to: snapshotURL)
    }
}
