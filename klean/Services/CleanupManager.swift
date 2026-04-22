import Foundation

struct CleanupManager: Sendable {
    enum CleanupError: LocalizedError {
        case nothingToClean
        case partialFailure([String])
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .nothingToClean:
                return "Es gab nichts zu bereinigen."
            case let .partialFailure(failures):
                let preview = failures.prefix(3).joined(separator: ", ")
                if preview.isEmpty {
                    return "\(failures.count) Elemente konnten nicht verarbeitet werden."
                }
                return "\(failures.count) Elemente konnten nicht verarbeitet werden: \(preview)"
            case let .commandFailed(message):
                return message
            }
        }
    }

    func execute(_ recommendation: CleanupRecommendation) throws {
        switch recommendation.strategy {
        case .trashContents:
            try trashContents(of: recommendation.targetURL)
        case .deleteContents:
            try deleteContents(of: recommendation.targetURL)
        case .moveItemToTrash:
            try moveItemToTrash(recommendation.targetURL)
        case .runCommand:
            guard let command = recommendation.command else {
                throw CleanupError.commandFailed("Der Cleanup-Command fehlt.")
            }
            try runCommand(
                executable: command.executable,
                arguments: command.arguments
            )
        }
    }

    func moveItemToTrash(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CleanupError.nothingToClean
        }

        _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private func trashContents(of directoryURL: URL) throws {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        guard !items.isEmpty else {
            throw CleanupError.nothingToClean
        }

        var failures: [String] = []
        for item in items {
            do {
                _ = try fileManager.trashItem(at: item, resultingItemURL: nil)
            } catch {
                failures.append(item.lastPathComponent)
            }
        }

        if !failures.isEmpty {
            throw CleanupError.partialFailure(failures)
        }
    }

    private func deleteContents(of directoryURL: URL) throws {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        guard !items.isEmpty else {
            throw CleanupError.nothingToClean
        }

        var failures: [String] = []
        for item in items {
            do {
                try forceRemoveItem(at: item)
            } catch {
                failures.append(item.lastPathComponent)
            }
        }

        if !failures.isEmpty {
            throw CleanupError.partialFailure(failures)
        }
    }

    private func forceRemoveItem(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            try? runCommand(
                executable: "/usr/bin/chflags",
                arguments: ["-R", "nouchg", url.path]
            )
            try runCommand(
                executable: "/bin/rm",
                arguments: ["-rf", url.path]
            )
        }

        if fileManager.fileExists(atPath: url.path) {
            throw CleanupError.partialFailure([url.lastPathComponent])
        }
    }

    private func runCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CleanupError.commandFailed(message?.isEmpty == false ? message! : "Die Bereinigung konnte nicht abgeschlossen werden.")
        }
    }
}
