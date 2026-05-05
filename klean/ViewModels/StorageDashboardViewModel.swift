import AppKit
import Foundation

enum SidebarSelection: Hashable {
    case overview
    case category(String)
}

enum ConfirmedAction {
    case cleanup(CleanupRecommendation)
    case trash(StorageNode)
}

struct AppAlert: Identifiable {
    enum Kind {
        case info(title: String, message: String)
        case confirmation(title: String, message: String, action: ConfirmedAction)
    }

    let id = UUID()
    let kind: Kind
}

@MainActor
final class StorageDashboardViewModel: ObservableObject {
    @Published var snapshot: StorageSnapshot?
    @Published var scanState: ScanState = .idle
    @Published var selection: SidebarSelection = .overview
    @Published var activeAlert: AppAlert?
    @Published var isShowingCachedData = false

    private let scanner = StorageScanner()
    private let cleanupManager = CleanupManager()
    private let snapshotStore = SnapshotStore()
    private let automaticRefreshInterval: TimeInterval = 15 * 60
    private var scanTask: Task<Void, Never>?

    init() {
        restoreCachedSnapshot()
        if shouldRefreshOnLaunch {
            startScan(force: true)
        }
    }

    var selectedCategory: StorageCategory? {
        guard case let .category(id) = selection else {
            return nil
        }

        return snapshot?.categories.first(where: { $0.id == id })
    }

    func startScan(force: Bool = true) {
        if force == false,
           let snapshot,
           Date().timeIntervalSince(snapshot.scannedAt) < automaticRefreshInterval {
            scanState = .ready(snapshot.scannedAt)
            return
        }

        scanTask?.cancel()
        scanState = .scanning(.init(currentTargetTitle: "Preparing", completedTargets: 0, totalTargets: 1))

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await scanner.scan { progress in
                    self.scanState = .scanning(progress)
                } partialUpdate: { update in
                    let mergedSnapshot = self.mergeDisplayedSnapshot(with: update.snapshot)
                    self.snapshot = mergedSnapshot
                    self.isShowingCachedData = false
                    self.scanState = .scanning(update.progress)
                    self.persist(snapshot: mergedSnapshot)
                }

                self.snapshot = snapshot
                self.isShowingCachedData = false
                self.persist(snapshot: snapshot)
                if case let .category(id) = self.selection,
                   snapshot.categories.contains(where: { $0.id == id }) == false {
                    self.selection = .overview
                }
                self.scanState = .ready(snapshot.scannedAt)
            } catch is CancellationError {
                self.scanState = .idle
            } catch {
                self.scanState = .failed(error.localizedDescription)
                self.activeAlert = AppAlert(
                    kind: .info(
                        title: "Scan Failed",
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    func select(category: StorageCategory) {
        selection = .category(category.id)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func requestCleanup(_ recommendation: CleanupRecommendation) {
        let targetLine: String
        switch recommendation.strategy {
        case .runCommand:
            targetLine = recommendation.detailText.map { "Routine: \($0)" } ?? "Routine: Command"
        default:
            targetLine = "Target: \(recommendation.detailText ?? recommendation.targetURL.prettyPath)"
        }

        activeAlert = AppAlert(
            kind: .confirmation(
                title: recommendation.title,
                message: "\(recommendation.summary)\n\n\(targetLine)\nEstimated impact: \(ByteCountFormatter.storageString(recommendation.estimatedBytes))\nRisk: \(recommendation.risk.note)",
                action: .cleanup(recommendation)
            )
        )
    }

    func requestTrash(_ item: StorageNode) {
        activeAlert = AppAlert(
            kind: .confirmation(
                title: "Move To Trash?",
                message: "\(item.name) will be moved to your Trash.",
                action: .trash(item)
            )
        )
    }

    func perform(_ action: ConfirmedAction) {
        Task { [weak self] in
            guard let self else { return }

            do {
                applyOptimisticUpdate(for: action)

                switch action {
                case let .cleanup(recommendation):
                    try cleanupManager.execute(recommendation)
                    persistCurrentSnapshot()
                    activeAlert = AppAlert(
                        kind: .info(
                            title: "Cleanup Complete",
                            message: "\(recommendation.title) finished successfully."
                        )
                    )
                case let .trash(item):
                    try cleanupManager.moveItemToTrash(item.url)
                    persistCurrentSnapshot()
                    activeAlert = AppAlert(
                        kind: .info(
                            title: "Moved To Trash",
                            message: "\(item.name) is now in the Trash."
                        )
                    )
                }

                startScan(force: true)
            } catch {
                startScan(force: true)
                activeAlert = AppAlert(
                    kind: .info(
                        title: "Action Failed",
                        message: error.localizedDescription
                    )
                )
            }
        }
    }
}

private extension StorageDashboardViewModel {
    var shouldRefreshOnLaunch: Bool {
        guard let snapshot else {
            return true
        }

        return Date().timeIntervalSince(snapshot.scannedAt) >= automaticRefreshInterval
    }

    func restoreCachedSnapshot() {
        guard let cachedSnapshot = try? snapshotStore.load() else {
            return
        }

        snapshot = cachedSnapshot
        isShowingCachedData = true
        scanState = .ready(cachedSnapshot.scannedAt)
    }

    func mergeDisplayedSnapshot(with refreshedSnapshot: StorageSnapshot) -> StorageSnapshot {
        guard let snapshot else {
            return refreshedSnapshot
        }

        return snapshot.merging(refreshedSnapshot: refreshedSnapshot)
    }

    func persist(snapshot: StorageSnapshot) {
        try? snapshotStore.save(snapshot)
    }

    func persistCurrentSnapshot() {
        guard let snapshot else { return }
        persist(snapshot: snapshot)
    }

    func applyOptimisticUpdate(for action: ConfirmedAction) {
        guard let snapshot else { return }

        switch action {
        case let .cleanup(recommendation):
            self.snapshot = snapshot.applyingCleanup(recommendation)
        case let .trash(item):
            self.snapshot = snapshot.applyingTrash(of: item)
        }
        isShowingCachedData = false
    }
}

private extension StorageSnapshot {
    func merging(refreshedSnapshot: StorageSnapshot) -> StorageSnapshot {
        let refreshedCategoryPaths = Set(refreshedSnapshot.categories.map(\.id))
        let refreshedPrefixes = refreshedSnapshot.categories.map { $0.url.standardizedFileURL.path }

        let preservedCategories = categories.filter { refreshedCategoryPaths.contains($0.id) == false }
        let mergedCategories = (preservedCategories + refreshedSnapshot.categories)
            .sorted { $0.totalBytes > $1.totalBytes }

        let preservedLargestFiles = largestFiles.filter { file in
            refreshedPrefixes.contains(where: { file.url.standardizedFileURL.path.hasPrefix($0) }) == false
        }
        let mergedLargestFiles = Array((preservedLargestFiles + refreshedSnapshot.largestFiles)
            .sorted { $0.bytes > $1.bytes }
            .prefix(18))

        let mergedInaccessiblePaths = Array(
            Set(inaccessiblePaths.map(\.path) + refreshedSnapshot.inaccessiblePaths.map(\.path))
        )
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        .sorted { $0.path < $1.path }

        return StorageSnapshot(
            volume: refreshedSnapshot.volume,
            scannedAt: refreshedSnapshot.scannedAt,
            categories: mergedCategories,
            largestFiles: mergedLargestFiles,
            inaccessiblePaths: mergedInaccessiblePaths,
            developerRoutines: refreshedSnapshot.developerRoutines,
            reviewRecommendations: refreshedSnapshot.reviewRecommendations
        )
    }

    func applyingCleanup(_ recommendation: CleanupRecommendation) -> StorageSnapshot {
        let targetPath = recommendation.targetURL.standardizedFileURL.path
        let updatedDeveloperRoutines = developerRoutines.filter {
            shouldKeepRecommendation($0, afterApplying: recommendation)
        }
        let updatedReviewRecommendations = reviewRecommendations.filter {
            shouldKeepRecommendation($0, afterApplying: recommendation)
        }
        let shouldMoveToTrash = recommendation.strategy == .trashContents || recommendation.strategy == .moveItemToTrash
        let shouldIncreaseFreeSpace = recommendation.strategy == .deleteContents || recommendation.strategy == .runCommand

        guard let targetIndex = categories.firstIndex(where: { $0.url.standardizedFileURL.path == targetPath }) else {
            if let sourceIndex = sourceCategoryIndex(for: recommendation.targetURL) {
                var updatedCategories = categories
                let removedItemCount = updatedCategories[sourceIndex].estimatedItemCount(for: recommendation.targetURL)
                updatedCategories[sourceIndex] = updatedCategories[sourceIndex].subtracting(
                    targetURL: recommendation.targetURL,
                    bytes: recommendation.estimatedBytes,
                    removesTarget: recommendation.strategy != .runCommand
                )

                if shouldMoveToTrash,
                   let trashIndex = updatedCategories.firstIndex(where: \.isTrashCategory) {
                    updatedCategories[trashIndex] = updatedCategories[trashIndex]
                        .adding(bytes: recommendation.estimatedBytes, itemCount: removedItemCount)
                }

                return StorageSnapshot(
                    volume: shouldIncreaseFreeSpace ? volume.adjustingAvailableBytes(by: recommendation.estimatedBytes) : volume,
                    scannedAt: Date(),
                    categories: updatedCategories,
                    largestFiles: largestFiles.filter { !$0.url.path.hasPrefix(targetPath) },
                    inaccessiblePaths: inaccessiblePaths,
                    developerRoutines: updatedDeveloperRoutines,
                    reviewRecommendations: updatedReviewRecommendations
                )
            }

            return StorageSnapshot(
                volume: volume,
                scannedAt: Date(),
                categories: categories,
                largestFiles: largestFiles,
                inaccessiblePaths: inaccessiblePaths,
                developerRoutines: updatedDeveloperRoutines,
                reviewRecommendations: updatedReviewRecommendations
            )
        }

        var updatedCategories = categories
        let targetCategory = categories[targetIndex]
        let removedBytes = targetCategory.totalBytes
        let removedItems = targetCategory.itemCount

        switch recommendation.strategy {
        case .trashContents:
            updatedCategories[targetIndex] = targetCategory.cleared()
            if let trashIndex = updatedCategories.firstIndex(where: \.isTrashCategory) {
                updatedCategories[trashIndex] = updatedCategories[trashIndex]
                    .adding(bytes: removedBytes, itemCount: removedItems)
            }

            return StorageSnapshot(
                volume: volume,
                scannedAt: Date(),
                categories: updatedCategories,
                largestFiles: largestFiles.filter { !$0.url.path.hasPrefix(targetPath) },
                inaccessiblePaths: inaccessiblePaths,
                developerRoutines: updatedDeveloperRoutines,
                reviewRecommendations: updatedReviewRecommendations
            )

        case .deleteContents:
            updatedCategories[targetIndex] = targetCategory.cleared()
            return StorageSnapshot(
                volume: volume.adjustingAvailableBytes(by: removedBytes),
                scannedAt: Date(),
                categories: updatedCategories,
                largestFiles: largestFiles.filter { !$0.url.path.hasPrefix(targetPath) },
                inaccessiblePaths: inaccessiblePaths,
                developerRoutines: updatedDeveloperRoutines,
                reviewRecommendations: updatedReviewRecommendations
            )

        case .moveItemToTrash:
            updatedCategories[targetIndex] = targetCategory.cleared()
            if let trashIndex = updatedCategories.firstIndex(where: \.isTrashCategory) {
                updatedCategories[trashIndex] = updatedCategories[trashIndex]
                    .adding(bytes: removedBytes, itemCount: removedItems)
            }

            return StorageSnapshot(
                volume: volume,
                scannedAt: Date(),
                categories: updatedCategories,
                largestFiles: largestFiles.filter { !$0.url.path.hasPrefix(targetPath) },
                inaccessiblePaths: inaccessiblePaths,
                developerRoutines: updatedDeveloperRoutines,
                reviewRecommendations: updatedReviewRecommendations
            )

        case .runCommand:
            updatedCategories[targetIndex] = targetCategory.subtracting(
                targetURL: recommendation.targetURL,
                bytes: recommendation.estimatedBytes,
                removesTarget: false
            )

            return StorageSnapshot(
                volume: volume.adjustingAvailableBytes(by: recommendation.estimatedBytes),
                scannedAt: Date(),
                categories: updatedCategories,
                largestFiles: largestFiles.filter { !$0.url.path.hasPrefix(targetPath) },
                inaccessiblePaths: inaccessiblePaths,
                developerRoutines: updatedDeveloperRoutines,
                reviewRecommendations: updatedReviewRecommendations
            )
        }
    }

    func applyingTrash(of item: StorageNode) -> StorageSnapshot {
        var updatedCategories = categories

        if let sourceIndex = sourceCategoryIndex(for: item.url) {
            updatedCategories[sourceIndex] = updatedCategories[sourceIndex]
                .subtracting(node: item)
        }

        if let trashIndex = updatedCategories.firstIndex(where: \.isTrashCategory) {
            updatedCategories[trashIndex] = updatedCategories[trashIndex]
                .adding(bytes: item.bytes, itemCount: max(item.itemCount, 1))
        }

        return StorageSnapshot(
            volume: volume,
            scannedAt: Date(),
            categories: updatedCategories,
            largestFiles: largestFiles.filter { $0.id != item.id },
            inaccessiblePaths: inaccessiblePaths,
            developerRoutines: developerRoutines,
            reviewRecommendations: reviewRecommendations
        )
    }

    private func shouldKeepRecommendation(_ existingRecommendation: CleanupRecommendation, afterApplying appliedRecommendation: CleanupRecommendation) -> Bool {
        guard existingRecommendation.id != appliedRecommendation.id else {
            return false
        }

        guard appliedRecommendation.strategy != .runCommand else {
            return true
        }

        let existingPath = existingRecommendation.targetURL.standardizedFileURL.path
        let appliedPath = appliedRecommendation.targetURL.standardizedFileURL.path
        return existingPath != appliedPath && existingPath.hasPrefix(appliedPath + "/") == false
    }

    private func sourceCategoryIndex(for url: URL) -> Int? {
        categories
            .enumerated()
            .filter { _, category in
                category.isTrashCategory == false &&
                url.standardizedFileURL.path.hasPrefix(category.url.standardizedFileURL.path)
            }
            .max { lhs, rhs in
                lhs.element.url.standardizedFileURL.path.count < rhs.element.url.standardizedFileURL.path.count
            }?
            .offset
    }
}

private extension StorageCategory {
    var isTrashCategory: Bool {
        url.lastPathComponent == ".Trash"
    }

    func cleared() -> StorageCategory {
        StorageCategory(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            url: url,
            totalBytes: 0,
            itemCount: 0,
            topChildren: [],
            cleanupRecommendation: nil
        )
    }

    func adding(bytes: Int64, itemCount: Int) -> StorageCategory {
        let updatedBytes = max(totalBytes + bytes, 0)
        let updatedCount = max(self.itemCount + itemCount, 0)

        return StorageCategory(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            url: url,
            totalBytes: updatedBytes,
            itemCount: updatedCount,
            topChildren: topChildren,
            cleanupRecommendation: cleanupRecommendation?.withEstimatedBytes(updatedBytes)
        )
    }

    func subtracting(node: StorageNode) -> StorageCategory {
        let updatedBytes = max(totalBytes - node.bytes, 0)
        let updatedCount = max(itemCount - max(node.itemCount, 1), 0)
        let updatedChildren = topChildren.filter { $0.id != node.id }

        return StorageCategory(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            url: url,
            totalBytes: updatedBytes,
            itemCount: updatedCount,
            topChildren: updatedChildren,
            cleanupRecommendation: cleanupRecommendation?.withEstimatedBytes(updatedBytes)
        )
    }

    func subtracting(bytes: Int64) -> StorageCategory {
        let updatedBytes = max(totalBytes - bytes, 0)
        let updatedChildren = topChildren.map { child in
            StorageNode(
                url: child.url,
                name: child.name,
                bytes: child.bytes,
                itemCount: child.itemCount,
                kind: child.kind,
                modifiedAt: child.modifiedAt
            )
        }

        return StorageCategory(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            url: url,
            totalBytes: updatedBytes,
            itemCount: itemCount,
            topChildren: updatedChildren,
            cleanupRecommendation: cleanupRecommendation?.withEstimatedBytes(updatedBytes)
        )
    }

    func subtracting(targetURL: URL, bytes: Int64, removesTarget: Bool) -> StorageCategory {
        let targetPath = targetURL.standardizedFileURL.path
        let updatedBytes = max(totalBytes - bytes, 0)
        var removedItemCount = 0

        let updatedChildren = topChildren.compactMap { child -> StorageNode? in
            let childPath = child.url.standardizedFileURL.path
            let targetMatchesChild = childPath == targetPath || childPath.hasPrefix(targetPath + "/")
            let targetIsInsideChild = targetPath.hasPrefix(childPath + "/")

            if removesTarget && targetMatchesChild {
                removedItemCount += max(child.itemCount, 1)
                return nil
            }

            guard targetMatchesChild || targetIsInsideChild else {
                return child
            }

            let childBytes = max(child.bytes - bytes, 0)
            guard childBytes > 0 else {
                removedItemCount += max(child.itemCount, 1)
                return nil
            }

            return StorageNode(
                url: child.url,
                name: child.name,
                bytes: childBytes,
                itemCount: child.itemCount,
                kind: child.kind,
                modifiedAt: child.modifiedAt
            )
        }

        return StorageCategory(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            url: url,
            totalBytes: updatedBytes,
            itemCount: max(itemCount - removedItemCount, 0),
            topChildren: updatedChildren.sorted { $0.bytes > $1.bytes },
            cleanupRecommendation: cleanupRecommendation?.withEstimatedBytes(updatedBytes)
        )
    }

    func estimatedItemCount(for targetURL: URL) -> Int {
        let targetPath = targetURL.standardizedFileURL.path
        return topChildren.first { child in
            let childPath = child.url.standardizedFileURL.path
            return childPath == targetPath || childPath.hasPrefix(targetPath + "/") || targetPath.hasPrefix(childPath + "/")
        }
        .map { max($0.itemCount, 1) } ?? 1
    }
}

private extension CleanupRecommendation {
    func withEstimatedBytes(_ updatedBytes: Int64) -> CleanupRecommendation? {
        guard updatedBytes > 0 else {
            return nil
        }

        return CleanupRecommendation(
            title: title,
            summary: summary,
            buttonLabel: buttonLabel,
            targetURL: targetURL,
            strategy: strategy,
            risk: risk,
            estimatedBytes: updatedBytes,
            systemImage: systemImage,
            scope: scope,
            detailText: detailText,
            command: command
        )
    }
}

private extension VolumeStats {
    func adjustingAvailableBytes(by delta: Int64) -> VolumeStats {
        let updatedAvailableBytes = min(max(availableBytes + delta, 0), totalBytes)
        let importantDelta = updatedAvailableBytes - availableBytes

        return VolumeStats(
            totalBytes: totalBytes,
            availableBytes: updatedAvailableBytes,
            importantAvailableBytes: min(max(importantAvailableBytes + importantDelta, 0), totalBytes),
            opportunisticAvailableBytes: min(max(opportunisticAvailableBytes + importantDelta, 0), totalBytes)
        )
    }
}

private extension URL {
    var prettyPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: homePath, with: "~")
    }
}
