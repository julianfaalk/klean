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
}

enum CleanupRisk: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low:
            return "Sicher"
        case .medium:
            return "Pruefen"
        case .high:
            return "Vorsicht"
        }
    }

    var note: String {
        switch self {
        case .low:
            return "In der Regel unkompliziert rueckgaengig oder neu erzeugbar."
        case .medium:
            return "Kann Entwicklungsdaten oder persoenliche Arbeitsflaechen betreffen."
        case .high:
            return "Kann dauerhaft wichtige Daten entfernen."
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

    var id: String {
        "\(strategy.rawValue)|\(targetURL.path())"
    }
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

        return "\(min(completedTargets, totalTargets))/\(totalTargets) geladen • \(currentTargetTitle)"
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
            return "Bereit"
        case let .scanning(progress):
            return progress.statusSummary
        case let .ready(date):
            return "Zuletzt aktualisiert: \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .failed(message):
            return "Scan fehlgeschlagen: \(message)"
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
}

enum DefaultScanTargets {
    static func make(home: URL) -> [ScanTargetDefinition] {
        [
            .init(
                title: "Programme",
                subtitle: "Installierte Apps im Systemordner",
                systemImage: "square.stack.3d.up.fill",
                url: URL(fileURLWithPath: "/Applications", isDirectory: true),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Downloads",
                subtitle: "Was oft unbemerkt viel Speicher zieht",
                systemImage: "arrow.down.circle.fill",
                url: home.appending(path: "Downloads", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Desktop",
                subtitle: "Schnell erreichbar, schnell ueberfuellt",
                systemImage: "macwindow.on.rectangle",
                url: home.appending(path: "Desktop", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Dokumente",
                subtitle: "Projekte, Exporte und grosse Archive",
                systemImage: "doc.text.fill",
                url: home.appending(path: "Documents", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Bilder",
                subtitle: "Fotos, Libraries und Medienpakete",
                systemImage: "photo.stack.fill",
                url: home.appending(path: "Pictures", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Filme",
                subtitle: "Video- und Screenrecording-Daten",
                systemImage: "film.stack.fill",
                url: home.appending(path: "Movies", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Musik",
                subtitle: "Audio, Samples und Mediatheken",
                systemImage: "music.note.house.fill",
                url: home.appending(path: "Music", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "iCloud Drive",
                subtitle: "Synchronisierte Inhalte im Home-Bereich",
                systemImage: "icloud.fill",
                url: home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Papierkorb",
                subtitle: "Bereits entfernt, aber noch nicht freigegeben",
                systemImage: "trash.fill",
                url: home.appending(path: ".Trash", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Papierkorb leeren",
                    summary: "Entfernt den Inhalt deines Benutzer-Papierkorbs dauerhaft.",
                    buttonLabel: "Papierkorb leeren",
                    strategy: .deleteContents,
                    risk: .medium
                )
            ),
            .init(
                title: "App Support",
                subtitle: "Datenbanken, Downloads und lokale App-Daten",
                systemImage: "externaldrive.fill.badge.person.crop",
                url: home.appending(path: "Library/Application Support", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "App Container",
                subtitle: "Sandbox-Daten von Mac-Apps",
                systemImage: "shippingbox.fill",
                url: home.appending(path: "Library/Containers", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Messages Anhaenge",
                subtitle: "Bilder, Videos und Dateien aus Nachrichten",
                systemImage: "message.fill",
                url: home.appending(path: "Library/Messages/Attachments", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            ),
            .init(
                title: "Caches",
                subtitle: "Temporäre Daten, oft gut entsorgbar",
                systemImage: "sparkles.rectangle.stack.fill",
                url: home.appending(path: "Library/Caches", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Caches aufraeumen",
                    summary: "Verschiebt den Inhalt deiner Benutzer-Caches in den Papierkorb.",
                    buttonLabel: "Caches in Papierkorb",
                    strategy: .trashContents,
                    risk: .low
                )
            ),
            .init(
                title: "Xcode DerivedData",
                subtitle: "Build-Artefakte und Indexdaten",
                systemImage: "hammer.fill",
                url: home.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "DerivedData bereinigen",
                    summary: "Verschiebt Xcode-Builddaten in den Papierkorb. Xcode erzeugt sie bei Bedarf neu.",
                    buttonLabel: "DerivedData cleanen",
                    strategy: .trashContents,
                    risk: .low
                )
            ),
            .init(
                title: "Xcode Archives",
                subtitle: "Archivierte Builds und Exporte",
                systemImage: "archivebox.fill",
                url: home.appending(path: "Library/Developer/Xcode/Archives", directoryHint: .isDirectory),
                cleanupDescriptor: .init(
                    title: "Xcode Archives pruefen",
                    summary: "Verschiebt Xcode-Archive in den Papierkorb. Nur cleanen, wenn du sie wirklich nicht mehr brauchst.",
                    buttonLabel: "Archives in Papierkorb",
                    strategy: .trashContents,
                    risk: .medium
                )
            ),
            .init(
                title: "iOS Simulator",
                subtitle: "Simulator-Images, Geräte und App-Daten",
                systemImage: "iphone.gen3",
                url: home.appending(path: "Library/Developer/CoreSimulator", directoryHint: .isDirectory),
                cleanupDescriptor: nil
            )
        ]
    }
}
