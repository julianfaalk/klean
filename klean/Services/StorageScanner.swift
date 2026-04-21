import Foundation

struct StorageScanner: Sendable {
    struct ScanUpdate: Sendable {
        let snapshot: StorageSnapshot
        let progress: ScanProgress
    }

    private struct BucketSeed {
        let url: URL
        let name: String
        let kind: StorageNode.Kind
        var bytes: Int64
        var itemCount: Int
        var modifiedAt: Date?
    }

    private struct InspectedTarget {
        let category: StorageCategory
        let largestFiles: [StorageNode]
        let inaccessiblePaths: [URL]
    }

    private let maximumLargestFiles = 18
    private let maximumChildrenPerCategory = 14
    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isPackageKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    func scan(
        progress: @escaping @MainActor (ScanProgress) -> Void,
        partialUpdate: @escaping @MainActor (ScanUpdate) -> Void
    ) async throws -> StorageSnapshot {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let targets = DefaultScanTargets.make(home: home)
            .filter { fileManager.fileExists(atPath: $0.url.path) }

        let volume = volumeStats(for: home)
        var categories: [StorageCategory] = []
        var largestFiles: [StorageNode] = []
        var inaccessiblePaths = Set<String>()

        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            await progress(.init(
                currentTargetTitle: target.title,
                completedTargets: index,
                totalTargets: targets.count
            ))

            do {
                let inspected = try inspect(target: target)
                categories.append(inspected.category)
                largestFiles = mergeLargestFiles(existing: largestFiles, incoming: inspected.largestFiles)
                inaccessiblePaths.formUnion(inspected.inaccessiblePaths.map(\.path))
            } catch {
                inaccessiblePaths.insert(target.url.path)
            }

             let update = ScanUpdate(
                snapshot: makeSnapshot(
                    volume: volume,
                    categories: categories,
                    largestFiles: largestFiles,
                    inaccessiblePaths: inaccessiblePaths
                ),
                progress: .init(
                    currentTargetTitle: target.title,
                    completedTargets: index + 1,
                    totalTargets: targets.count
                )
            )
            await partialUpdate(update)
        }

        return makeSnapshot(
            volume: volume,
            categories: categories,
            largestFiles: largestFiles,
            inaccessiblePaths: inaccessiblePaths
        )
    }

    private func inspect(target: ScanTargetDefinition) throws -> InspectedTarget {
        let fileManager = FileManager.default
        var inaccessiblePaths = Set<String>()
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var largestFiles: [StorageNode] = []

        var buckets = try seedBuckets(for: target.url, fileManager: fileManager)
        let enumerator = fileManager.enumerator(
            at: target.url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { url, _ in
                inaccessiblePaths.insert(url.path)
                return true
            }
        )

        while let item = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()

            let values = try? item.resourceValues(forKeys: resourceKeys)
            if values?.isSymbolicLink == true {
                enumerator?.skipDescendants()
                continue
            }

            if values?.isDirectory == true {
                continue
            }

            let size = fileAllocatedBytes(from: values)
            totalBytes += size
            totalFiles += 1

            guard let bucketName = immediateChildName(of: item, relativeTo: target.url) else {
                continue
            }

            if var bucket = buckets[bucketName] {
                bucket.bytes += size
                bucket.itemCount += 1
                if bucket.modifiedAt == nil {
                    bucket.modifiedAt = values?.contentModificationDate
                }
                buckets[bucketName] = bucket

                if bucket.kind != .package {
                    let candidate = StorageNode(
                        url: item,
                        name: item.lastPathComponent,
                        bytes: size,
                        itemCount: 1,
                        kind: .file,
                        modifiedAt: values?.contentModificationDate
                    )
                    largestFiles = insertLargestFile(candidate, into: largestFiles)
                }
            }
        }

        let topChildren = buckets.values
            .map {
                StorageNode(
                    url: $0.url,
                    name: $0.name,
                    bytes: $0.bytes,
                    itemCount: $0.itemCount,
                    kind: $0.kind,
                    modifiedAt: $0.modifiedAt
                )
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(maximumChildrenPerCategory)

        let recommendation = target.cleanupDescriptor.flatMap { descriptor in
            totalBytes > 0
                ? CleanupRecommendation(
                    title: descriptor.title,
                    summary: descriptor.summary,
                    buttonLabel: descriptor.buttonLabel,
                    targetURL: target.url,
                    strategy: descriptor.strategy,
                    risk: descriptor.risk,
                    estimatedBytes: totalBytes
                )
                : nil
        }

        return InspectedTarget(
            category: StorageCategory(
                title: target.title,
                subtitle: target.subtitle,
                systemImage: target.systemImage,
                url: target.url,
                totalBytes: totalBytes,
                itemCount: totalFiles,
                topChildren: Array(topChildren),
                cleanupRecommendation: recommendation
            ),
            largestFiles: largestFiles,
            inaccessiblePaths: inaccessiblePaths
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }

    private func seedBuckets(for rootURL: URL, fileManager: FileManager) throws -> [String: BucketSeed] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        let directChildren = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: []
        )

        return directChildren.reduce(into: [:]) { partialResult, childURL in
            let values = try? childURL.resourceValues(forKeys: Set(keys))
            let kind: StorageNode.Kind
            if values?.isPackage == true {
                kind = .package
            } else if values?.isDirectory == true {
                kind = .folder
            } else {
                kind = .file
            }

            partialResult[childURL.lastPathComponent] = BucketSeed(
                url: childURL,
                name: childURL.lastPathComponent,
                kind: kind,
                bytes: 0,
                itemCount: 0,
                modifiedAt: values?.contentModificationDate
            )
        }
    }

    private func immediateChildName(of itemURL: URL, relativeTo rootURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = itemURL.standardizedFileURL.path

        guard itemPath.hasPrefix(rootPath) else {
            return nil
        }

        var relativePath = String(itemPath.dropFirst(rootPath.count))
        if relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }

        return relativePath
            .split(separator: "/")
            .first
            .map(String.init)
    }

    private func fileAllocatedBytes(from values: URLResourceValues?) -> Int64 {
        let totalAllocated = values?.totalFileAllocatedSize.map(Int64.init)
        let allocated = values?.fileAllocatedSize.map(Int64.init)
        let fileSize = values?.fileSize.map(Int64.init)
        return max(totalAllocated ?? allocated ?? fileSize ?? 0, 0)
    }

    private func volumeStats(for url: URL) -> VolumeStats {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let totalBytes = Int64(values?.volumeTotalCapacity ?? 0)
        let availableBytes = Int64(values?.volumeAvailableCapacity ?? 0)
        let importantBytes = values?.volumeAvailableCapacityForImportantUsage.map { Int64($0) } ?? availableBytes
        let opportunisticBytes = values?.volumeAvailableCapacityForOpportunisticUsage.map { Int64($0) } ?? availableBytes

        return VolumeStats(
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            importantAvailableBytes: importantBytes,
            opportunisticAvailableBytes: opportunisticBytes
        )
    }

    private func insertLargestFile(_ candidate: StorageNode, into list: [StorageNode]) -> [StorageNode] {
        var updated = list
        updated.append(candidate)
        updated.sort { $0.bytes > $1.bytes }
        if updated.count > maximumLargestFiles {
            updated.removeLast(updated.count - maximumLargestFiles)
        }
        return updated
    }

    private func mergeLargestFiles(existing: [StorageNode], incoming: [StorageNode]) -> [StorageNode] {
        var merged = existing + incoming
        merged.sort { $0.bytes > $1.bytes }
        if merged.count > maximumLargestFiles {
            merged.removeLast(merged.count - maximumLargestFiles)
        }
        return merged
    }

    private func makeSnapshot(
        volume: VolumeStats,
        categories: [StorageCategory],
        largestFiles: [StorageNode],
        inaccessiblePaths: Set<String>
    ) -> StorageSnapshot {
        let sortedInaccessiblePaths = inaccessiblePaths
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .sorted { $0.path < $1.path }

        return StorageSnapshot(
            volume: volume,
            scannedAt: Date(),
            categories: categories.sorted { $0.totalBytes > $1.totalBytes },
            largestFiles: largestFiles.sorted { $0.bytes > $1.bytes },
            inaccessiblePaths: sortedInaccessiblePaths
        )
    }
}
