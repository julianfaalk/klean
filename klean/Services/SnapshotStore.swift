import Foundation

struct SnapshotStore {
    enum StoreError: LocalizedError {
        case unavailableDirectory

        var errorDescription: String? {
            switch self {
            case .unavailableDirectory:
                return "Der lokale Snapshot-Speicher konnte nicht vorbereitet werden."
            }
        }
    }

    func load() throws -> StorageSnapshot? {
        let fileManager = FileManager.default
        let url = try cacheURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StorageSnapshot.self, from: data)
    }

    func save(_ snapshot: StorageSnapshot) throws {
        let fileManager = FileManager.default
        let url = try cacheURL()
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private func cacheURL() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.unavailableDirectory
        }

        return applicationSupport
            .appending(path: "klean", directoryHint: .isDirectory)
            .appending(path: "snapshot-cache.json", directoryHint: .notDirectory)
    }
}
