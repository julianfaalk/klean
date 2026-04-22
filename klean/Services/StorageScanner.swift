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

            let developerRoutines = makeDeveloperRoutines(home: home, categories: categories)
            let update = ScanUpdate(
                snapshot: makeSnapshot(
                    volume: volume,
                    categories: categories,
                    largestFiles: largestFiles,
                    inaccessiblePaths: inaccessiblePaths,
                    developerRoutines: developerRoutines
                ),
                progress: .init(
                    currentTargetTitle: target.title,
                    completedTargets: index + 1,
                    totalTargets: targets.count
                )
            )
            await partialUpdate(update)
        }

        let developerRoutines = makeDeveloperRoutines(home: home, categories: categories)
        return makeSnapshot(
            volume: volume,
            categories: categories,
            largestFiles: largestFiles,
            inaccessiblePaths: inaccessiblePaths,
            developerRoutines: developerRoutines
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
                    estimatedBytes: totalBytes,
                    systemImage: target.systemImage,
                    scope: descriptor.scope,
                    detailText: target.url.prettyPath
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

    private func makeDeveloperRoutines(home: URL, categories: [StorageCategory]) -> [CleanupRecommendation] {
        var routines: [CleanupRecommendation] = []

        appendDirectoryRoutine(
            to: &routines,
            title: "SwiftPM Cache bereinigen",
            summary: "Entfernt den lokalen Swift Package Manager Download-Cache. Pakete werden bei Bedarf erneut geladen.",
            buttonLabel: "SwiftPM Cache cleanen",
            targetURL: home.appending(path: "Library/Caches/org.swift.swiftpm", directoryHint: .isDirectory),
            systemImage: "shippingbox.fill",
            risk: .low,
            categories: categories
        )

        appendDirectoryRoutine(
            to: &routines,
            title: "Flutter Pub Cache bereinigen",
            summary: "Raeumt den globalen Flutter- und Dart-Paketcache auf. Abhaengigkeiten werden spaeter erneut geladen.",
            buttonLabel: "Pub Cache cleanen",
            targetURL: home.appending(path: ".pub-cache", directoryHint: .isDirectory),
            systemImage: "square.stack.3d.up.fill",
            risk: .low,
            categories: categories
        )

        appendDirectoryRoutine(
            to: &routines,
            title: "CoreSimulator Caches bereinigen",
            summary: "Entfernt temporaere CoreSimulator-Caches, ohne Simulator-Devices und App-Daten direkt anzufassen.",
            buttonLabel: "Simulator Caches cleanen",
            targetURL: home.appending(path: "Library/Developer/CoreSimulator/Caches", directoryHint: .isDirectory),
            systemImage: "iphone.gen3",
            risk: .low,
            categories: categories
        )

        if let dockerRoutine = makeDockerBuildCacheRoutine(home: home) {
            routines.append(dockerRoutine)
        }

        return routines.sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    private func appendDirectoryRoutine(
        to routines: inout [CleanupRecommendation],
        title: String,
        summary: String,
        buttonLabel: String,
        targetURL: URL,
        systemImage: String,
        risk: CleanupRisk,
        categories: [StorageCategory]
    ) {
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return
        }

        let estimatedBytes = estimatedBytes(for: targetURL, categories: categories)
        guard estimatedBytes > 0 else {
            return
        }

        routines.append(
            CleanupRecommendation(
                title: title,
                summary: summary,
                buttonLabel: buttonLabel,
                targetURL: targetURL,
                strategy: .trashContents,
                risk: risk,
                estimatedBytes: estimatedBytes,
                systemImage: systemImage,
                scope: .developer,
                detailText: targetURL.prettyPath
            )
        )
    }

    private func estimatedBytes(for targetURL: URL, categories: [StorageCategory]) -> Int64 {
        if let matchingCategory = categories.first(where: { $0.url.standardizedFileURL.path == targetURL.standardizedFileURL.path }) {
            return matchingCategory.totalBytes
        }

        return directorySize(at: targetURL)
    }

    private func directorySize(at rootURL: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: resourceKeys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values?.isDirectory == true {
                continue
            }

            totalBytes += fileAllocatedBytes(from: values)
        }

        return totalBytes
    }

    private func makeDockerBuildCacheRoutine(home: URL) -> CleanupRecommendation? {
        guard let dockerExecutable = resolvedExecutable(named: "docker") else {
            return nil
        }

        guard let output = try? runCommand(
            executable: dockerExecutable,
            arguments: ["system", "df", "--format", "json"]
        ) else {
            return nil
        }

        let reclaimableBytes = dockerBuildCacheBytes(from: output)
        guard reclaimableBytes > 0 else {
            return nil
        }

        let dockerRoot = home.appending(path: "Library/Containers/com.docker.docker", directoryHint: .isDirectory)

        return CleanupRecommendation(
            title: "Docker Build Cache bereinigen",
            summary: "Fuehrt `docker buildx prune --all --force` aus und entfernt nur den Build-Cache. Images, Volumes und Container bleiben unberuehrt.",
            buttonLabel: "Docker Cache cleanen",
            targetURL: dockerRoot,
            strategy: .runCommand,
            risk: .medium,
            estimatedBytes: reclaimableBytes,
            systemImage: "shippingbox.fill",
            scope: .developer,
            detailText: "docker buildx prune --all --force",
            command: CleanupCommand(
                executable: dockerExecutable,
                arguments: ["buildx", "prune", "--all", "--force"]
            )
        )
    }

    private func dockerBuildCacheBytes(from output: String) -> Int64 {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Int64? in
                guard let data = line.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (payload["Type"] as? String) == "Build Cache",
                      let reclaimable = payload["Reclaimable"] as? String else {
                    return nil
                }
                return parseHumanReadableBytes(reclaimable)
            }
            .first ?? 0
    }

    private func parseHumanReadableBytes(_ rawValue: String) -> Int64 {
        let trimmedValue = rawValue
            .components(separatedBy: " ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawValue

        let pattern = #"([0-9]+(?:\.[0-9]+)?)([KMGTP]?B)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: trimmedValue,
                range: NSRange(trimmedValue.startIndex..., in: trimmedValue)
              ),
              let valueRange = Range(match.range(at: 1), in: trimmedValue),
              let unitRange = Range(match.range(at: 2), in: trimmedValue),
              let numericValue = Double(trimmedValue[valueRange]) else {
            return 0
        }

        let multiplier: Double
        switch String(trimmedValue[unitRange]) {
        case "KB":
            multiplier = 1_024
        case "MB":
            multiplier = 1_024 * 1_024
        case "GB":
            multiplier = 1_024 * 1_024 * 1_024
        case "TB":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024
        case "PB":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024 * 1_024
        default:
            multiplier = 1
        }

        return Int64(numericValue * multiplier)
    }

    private func resolvedExecutable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func runCommand(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "StorageScanner", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errorMessage?.isEmpty == false ? errorMessage! : "Command failed"
            ])
        }

        return String(data: outputData, encoding: .utf8) ?? ""
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
        inaccessiblePaths: Set<String>,
        developerRoutines: [CleanupRecommendation]
    ) -> StorageSnapshot {
        let sortedInaccessiblePaths = inaccessiblePaths
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .sorted { $0.path < $1.path }

        return StorageSnapshot(
            volume: volume,
            scannedAt: Date(),
            categories: categories.sorted { $0.totalBytes > $1.totalBytes },
            largestFiles: largestFiles.sorted { $0.bytes > $1.bytes },
            inaccessiblePaths: sortedInaccessiblePaths,
            developerRoutines: developerRoutines
        )
    }
}

private extension URL {
    var prettyPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: homePath, with: "~")
    }
}
