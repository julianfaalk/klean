import Foundation

struct VolumeStats: Codable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    let importantAvailableBytes: Int64
    let opportunisticAvailableBytes: Int64

    var usedBytes: Int64 {
        max(totalBytes - availableBytes, 0)
    }
}

enum CleanupStrategy: String, Codable, Hashable, Sendable {
    case trashContents
    case deleteContents
    case moveItemToTrash
    case runCommand
}

enum CleanupRecommendationScope: String, Codable, Hashable, Sendable {
    case general
    case developer
}

enum CleanupRisk: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low:
            return "Safe"
        case .medium:
            return "Review"
        case .high:
            return "Caution"
        }
    }

    var note: String {
        switch self {
        case .low:
            return "Usually safe to remove because the data can be regenerated or restored without much friction."
        case .medium:
            return "May affect development data or working sets that you still care about."
        case .high:
            return "May permanently remove important data."
        }
    }
}

struct CleanupRecommendation: Codable, Identifiable, Hashable, Sendable {
    let title: String
    let summary: String
    let buttonLabel: String
    let targetURL: URL
    let strategy: CleanupStrategy
    let risk: CleanupRisk
    let estimatedBytes: Int64
    let systemImage: String
    let scope: CleanupRecommendationScope
    let detailText: String?
    let command: CleanupCommand?

    init(
        title: String,
        summary: String,
        buttonLabel: String,
        targetURL: URL,
        strategy: CleanupStrategy,
        risk: CleanupRisk,
        estimatedBytes: Int64,
        systemImage: String = "sparkles",
        scope: CleanupRecommendationScope = .general,
        detailText: String? = nil,
        command: CleanupCommand? = nil
    ) {
        self.title = title
        self.summary = summary
        self.buttonLabel = buttonLabel
        self.targetURL = targetURL
        self.strategy = strategy
        self.risk = risk
        self.estimatedBytes = estimatedBytes
        self.systemImage = systemImage
        self.scope = scope
        self.detailText = detailText
        self.command = command
    }

    var id: String {
        if let command {
            return "\(strategy.rawValue)|\(command.executable)|\(command.arguments.joined(separator: " "))"
        }
        return "\(strategy.rawValue)|\(targetURL.path())"
    }
}

struct CleanupCommand: Codable, Hashable, Sendable {
    let executable: String
    let arguments: [String]
}

struct StorageNode: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case file
        case folder
        case package
    }

    let url: URL
    let name: String
    let bytes: Int64
    let itemCount: Int
    let kind: Kind
    let modifiedAt: Date?

    var id: String {
        url.path()
    }

    var isDirectoryLike: Bool {
        kind != .file
    }
}

struct StorageCategory: Codable, Identifiable, Hashable, Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL
    let totalBytes: Int64
    let itemCount: Int
    let topChildren: [StorageNode]
    let cleanupRecommendation: CleanupRecommendation?

    var id: String {
        url.path()
    }
}

struct StorageSnapshot: Codable, Sendable {
    let volume: VolumeStats
    let scannedAt: Date
    let categories: [StorageCategory]
    let largestFiles: [StorageNode]
    let inaccessiblePaths: [URL]
    let developerRoutines: [CleanupRecommendation]

    var scannedBytes: Int64 {
        categories.reduce(into: 0) { partialResult, category in
            partialResult += category.totalBytes
        }
    }

    var unexplainedUsedBytes: Int64 {
        max(volume.usedBytes - scannedBytes, 0)
    }

    var cleanupRecommendations: [CleanupRecommendation] {
        categories
            .compactMap(\.cleanupRecommendation)
            .sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    var generalCleanupRecommendations: [CleanupRecommendation] {
        cleanupRecommendations
            .filter { $0.scope == .general }
            .sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    var developerCleanupRecommendations: [CleanupRecommendation] {
        let categoryDeveloperRoutines = cleanupRecommendations.filter { $0.scope == .developer }
        return (categoryDeveloperRoutines + developerRoutines)
            .sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    var allCleanupRecommendations: [CleanupRecommendation] {
        (generalCleanupRecommendations + developerCleanupRecommendations)
            .sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    var sortedCategories: [StorageCategory] {
        categories.sorted { $0.totalBytes > $1.totalBytes }
    }
}

struct ScanProgress: Codable, Sendable {
    let currentTargetTitle: String
    let completedTargets: Int
    let totalTargets: Int

    var fractionComplete: Double {
        guard totalTargets > 0 else { return 0 }
        return Double(completedTargets) / Double(totalTargets)
    }

    var statusSummary: String {
        guard totalTargets > 0 else {
            return currentTargetTitle
        }

        return "\(min(completedTargets, totalTargets))/\(totalTargets) loaded • \(currentTargetTitle)"
    }
}

enum ScanState {
    case idle
    case scanning(ScanProgress)
    case ready(Date)
    case failed(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case let .scanning(progress):
            return progress.statusSummary
        case let .ready(date):
            return "Last updated: \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .failed(message):
            return "Scan failed: \(message)"
        }
    }
}

struct ScanTargetDefinition: Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL
    let cleanupDescriptor: CleanupDescriptor?
}

struct CleanupDescriptor: Sendable {
    let title: String
    let summary: String
    let buttonLabel: String
    let strategy: CleanupStrategy
    let risk: CleanupRisk
    let scope: CleanupRecommendationScope
}

enum DefaultScanTargets {
    static func make(home: URL) -> [ScanTargetDefinition] {
        [
            .init(
                title: "Applications",
                subtitle: "Installed apps in the main Applications folder",
                systemImage: "square.stack.3d.up.fill",
                url: URL(fileURLWithPath: "/Applications", isDirectory: true),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Downloads",
                subtitle: "The folder that quietly grows over time",
                systemImage: "arrow.down.circle.fill",
                url: home.appending(path: "Downloads", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Desktop",
                subtitle: "Easy to use, easy to overfill",
                systemImage: "macwindow.on.rectangle",
                url: home.appending(path: "Desktop", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Documents",
                subtitle: "Projects, exports, and large archives",
                systemImage: "doc.text.fill",
                url: home.appending(path: "Documents", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Pictures",
                subtitle: "Photos, libraries, and media bundles",
                systemImage: "photo.stack.fill",
                url: home.appending(path: "Pictures", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Movies",
                subtitle: "Video files and screen recordings",
                systemImage: "film.stack.fill",
                url: home.appending(path: "Movies", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Music",
                subtitle: "Audio files, samples, and media libraries",
                systemImage: "music.note.house.fill",
                url: home.appending(path: "Music", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "iCloud Drive",
                subtitle: "Synced files from your iCloud Drive home area",
                systemImage: "icloud.fill",
                url: home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Trash",
                subtitle: "Already removed, but not yet reclaimed",
                systemImage: "trash.fill",
                url: home.appending(path: ".Trash", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Empty Trash",
                    summary: "Permanently deletes the contents of your user Trash.",
                    buttonLabel: "Empty Trash",
                    strategy: .deleteContents,
                    risk: .medium,
                    scope: .general
                )
            ),
            .init(
                title: "App Support",
                subtitle: "Databases, downloads, and local app state",
                systemImage: "externaldrive.fill.badge.person.crop",
                url: home.appending(path: "Library/Application Support", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "App Containers",
                subtitle: "Sandbox data created by Mac apps",
                systemImage: "shippingbox.fill",
                url: home.appending(path: "Library/Containers", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Messages Attachments",
                subtitle: "Images, videos, and files from Messages",
                systemImage: "message.fill",
                url: home.appending(path: "Library/Messages/Attachments", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Caches",
                subtitle: "Temporary data that is often safe to clear",
                systemImage: "sparkles.rectangle.stack.fill",
                url: home.appending(path: "Library/Caches", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Clear User Caches",
                    summary: "Moves the contents of your user caches to the Trash.",
                    buttonLabel: "Move Caches to Trash",
                    strategy: .trashContents,
                    risk: .low,
                    scope: .general
                )
            ),
            .init(
                title: "Xcode DerivedData",
                subtitle: "Build artifacts, indexes, and temporary derived output",
                systemImage: "hammer.fill",
                url: home.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Clear DerivedData",
                    summary: "Moves Xcode build data to the Trash. Xcode will regenerate it when needed.",
                    buttonLabel: "Clear DerivedData",
                    strategy: .trashContents,
                    risk: .low,
                    scope: .developer
                )
            ),
            .init(
                title: "Xcode Archives",
                subtitle: "Archived builds and exported app bundles",
                systemImage: "archivebox.fill",
                url: home.appending(path: "Library/Developer/Xcode/Archives", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Review Xcode Archives",
                    summary: "Moves Xcode archives to the Trash. Only clear them if you no longer need them.",
                    buttonLabel: "Move Archives to Trash",
                    strategy: .trashContents,
                    risk: .medium,
                    scope: .developer
                )
            ),
            .init(
                title: "iOS Simulator",
                subtitle: "Simulator images, devices, and app data",
                systemImage: "iphone.gen3",
                url: home.appending(path: "Library/Developer/CoreSimulator", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            )
        ]
    }
}
