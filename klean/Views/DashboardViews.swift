import SwiftUI

enum KleanTheme {
    static let canvasTop = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let canvasBottom = Color(red: 0.87, green: 0.91, blue: 0.87)
    static let canvasShadow = Color(red: 0.68, green: 0.75, blue: 0.69)
    static let hazeGreen = Color(red: 0.57, green: 0.75, blue: 0.63)
    static let hazeGold = Color(red: 0.93, green: 0.76, blue: 0.53)
    static let hazeBlue = Color(red: 0.55, green: 0.67, blue: 0.82)
    static let ink = Color(red: 0.14, green: 0.17, blue: 0.16)
    static let mutedInk = Color(red: 0.36, green: 0.40, blue: 0.37)
    static let quietInk = Color(red: 0.51, green: 0.55, blue: 0.51)
    static let panelTop = Color.white.opacity(0.93)
    static let panelBottom = Color(red: 0.94, green: 0.95, blue: 0.92).opacity(0.88)
    static let panelStroke = Color.white.opacity(0.76)
    static let panelShadow = Color.black.opacity(0.12)
    static let sidebarTop = Color(red: 0.10, green: 0.13, blue: 0.12)
    static let sidebarBottom = Color(red: 0.06, green: 0.08, blue: 0.09)
    static let highlight = Color(red: 0.90, green: 0.61, blue: 0.26)
    static let accent = Color(red: 0.22, green: 0.59, blue: 0.33)
    static let success = Color(red: 0.18, green: 0.62, blue: 0.39)
    static let warning = Color(red: 0.86, green: 0.55, blue: 0.14)
    static let danger = Color(red: 0.82, green: 0.23, blue: 0.19)
    static let info = Color(red: 0.28, green: 0.44, blue: 0.76)
}

struct DetailCanvasBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [KleanTheme.canvasTop, KleanTheme.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(KleanTheme.hazeGreen.opacity(0.30))
                .frame(width: 560, height: 560)
                .blur(radius: 95)
                .offset(x: -260, y: -200)

            Circle()
                .fill(KleanTheme.hazeGold.opacity(0.25))
                .frame(width: 460, height: 460)
                .blur(radius: 96)
                .offset(x: 320, y: -180)

            Circle()
                .fill(KleanTheme.hazeBlue.opacity(0.18))
                .frame(width: 620, height: 620)
                .blur(radius: 118)
                .offset(x: 210, y: 280)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
                .padding(36)
                .blur(radius: 0.4)

            VStack(spacing: 22) {
                HStack(spacing: 22) {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 180, height: 180)
                        .blur(radius: 36)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 260, height: 220)
                        .blur(radius: 56)
                }
            }
            .padding(60)
        }
    }
}

struct OverviewDashboard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel

    private let categoryColumns = [
        GridItem(.adaptive(minimum: 240), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                OverviewHeroCard(
                    snapshot: viewModel.snapshot,
                    scanState: viewModel.scanState,
                    isShowingCachedData: viewModel.isShowingCachedData,
                    startScan: { viewModel.startScan() },
                    openFullDiskAccessSettings: viewModel.openFullDiskAccessSettings
                )

                if let snapshot = viewModel.snapshot {
                    OverviewInsightsRow(snapshot: snapshot)

                    if !snapshot.developerCleanupRecommendations.isEmpty {
                        DeveloperRoutinesCard(
                            viewModel: viewModel,
                            recommendations: snapshot.developerCleanupRecommendations
                        )
                    }

                    if !snapshot.reviewCleanupRecommendations.isEmpty {
                        ReviewCleanupsCard(
                            viewModel: viewModel,
                            recommendations: snapshot.reviewCleanupRecommendations
                        )
                    }

                    HStack(alignment: .top, spacing: 18) {
                        StorageSummaryCard(snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: 366, alignment: .top)
                        QuickActionsCard(viewModel: viewModel, recommendations: snapshot.generalCleanupRecommendations)
                            .frame(maxWidth: .infinity, minHeight: 366, alignment: .top)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeadline(
                            eyebrow: "Categories",
                            title: "The largest storage blocks first",
                            subtitle: "The most important areas inside the scanned surface, weighted by used storage."
                        )

                        LazyVGrid(columns: categoryColumns, spacing: 18) {
                            ForEach(snapshot.sortedCategories.prefix(8)) { category in
                                CategoryTile(
                                    category: category,
                                    largestCategoryBytes: snapshot.sortedCategories.first?.totalBytes ?? 1
                                )
                                .onTapGesture {
                                    viewModel.select(category: category)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeadline(
                            eyebrow: "Files",
                            title: "The largest directly actionable files",
                            subtitle: "Outside app bundles, so you can inspect or remove them immediately."
                        )

                        FileListCard(
                            title: "Top Files",
                            subtitle: "Use Finder to inspect, or move them to Trash right away.",
                            items: snapshot.largestFiles,
                            viewModel: viewModel
                        )
                    }

                    if !snapshot.inaccessiblePaths.isEmpty {
                        NoticeCard(
                            title: "Part of the system stayed protected",
                            message: "Some paths could not be read during the scan. For deeper visibility, the app or Xcode usually needs Full Disk Access."
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(snapshot.inaccessiblePaths.prefix(5), id: \.path) { url in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(KleanTheme.warning.opacity(0.22))
                                            .frame(width: 8, height: 8)
                                        Text(url.prettyPath)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(KleanTheme.mutedInk)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateCard(
                        title: "The first scan is building your overview",
                        message: "klean is walking the usual storage hotspots and assembling an actionable view step by step."
                    )
                }
            }
            .padding(.bottom, 28)
            .animation(.snappy(duration: 0.24), value: viewModel.snapshot?.scannedAt)
        }
    }
}

struct CategoryDetailView: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let category: StorageCategory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                CategoryHeroCard(viewModel: viewModel, category: category)

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeadline(
                        eyebrow: "Structure",
                        title: "The heaviest contents in \(category.title)",
                        subtitle: "Direct children of this area, sorted by allocated storage."
                    )

                    FileListCard(
                        title: category.title,
                        subtitle: category.subtitle,
                        items: category.topChildren,
                        viewModel: viewModel
                    )
                }

                if let snapshot = viewModel.snapshot {
                    let filesInsideCategory = snapshot.largestFiles.filter {
                        $0.url.path.hasPrefix(category.url.path)
                    }

                    if !filesInsideCategory.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeadline(
                                eyebrow: "Deep Scan",
                                title: "Large individual files inside this area",
                                subtitle: "Useful when you want targeted cleanup instead of sweeping cleanup."
                            )

                            FileListCard(
                                title: "Individual Files",
                                subtitle: "Large files found inside \(category.title).",
                                items: filesInsideCategory,
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }
}

struct ScanStatusFooter: View {
    let scanState: ScanState
    let showsCachedData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scan Status", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))

                Spacer()

                if showsCachedData {
                    StatusCapsule(text: "Cached", tint: KleanTheme.hazeGold)
                }
            }

            switch scanState {
            case let .scanning(progress):
                ProgressView(value: progress.fractionComplete)
                    .tint(.white)
                Text(scanState.statusText)
                    .font(.caption)
                    .foregroundStyle(.white)
            default:
                Text(scanState.statusText)
                    .font(.caption)
                    .foregroundStyle(.white)
            }

            Text(showsCachedData ? "This view starts from the last snapshot and is replaced progressively with fresh scan data." : "The values shown come from the current run or the most recently completed scan.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct OverviewHeroCard: View {
    let snapshot: StorageSnapshot?
    let scanState: ScanState
    let isShowingCachedData: Bool
    let startScan: () -> Void
    let openFullDiskAccessSettings: () -> Void

    var body: some View {
        CardShell {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    HeroEyebrow(text: "Storage Control")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Storage overview")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(KleanTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("See scanned storage, reclaimable cleanup targets, and the remaining system space without waiting for a full rescan after every action.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(KleanTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        HeroMetricChip(
                            label: "Free",
                            value: snapshot.map { ByteCountFormatter.storageString($0.volume.availableBytes) } ?? "..."
                        )
                        HeroMetricChip(
                            label: "Reclaimable",
                            value: snapshot.map { ByteCountFormatter.storageString($0.reclaimableBytes) } ?? "..."
                        )
                        HeroMetricChip(
                            label: "Status",
                            value: isShowingCachedData ? "Cache" : "Live"
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            startScan()
                        } label: {
                            Label("Rescan", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(KleanPrimaryActionStyle())
                        .frame(height: 42)

                        Button {
                            openFullDiskAccessSettings()
                        } label: {
                            Label("Full Disk Access", systemImage: "lock.shield")
                        }
                        .buttonStyle(KleanGhostActionStyle())
                        .frame(height: 42)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HeroStorageArtwork(
                    scanState: scanState,
                    snapshot: snapshot
                )
                .frame(width: 280, height: 244)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OverviewInsightsRow: View {
    let snapshot: StorageSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            InsightCard(
                label: "Scanned",
                value: ByteCountFormatter.storageString(snapshot.scannedBytes),
                note: "\(scanCoverageText(snapshot)) of used volume is mapped",
                tint: KleanTheme.accent
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            InsightCard(
                label: "Reclaimable",
                value: ByteCountFormatter.storageString(snapshot.reclaimableBytes),
                note: "\(snapshot.allCleanupRecommendations.count.formatted()) cleanup opportunities visible",
                tint: KleanTheme.highlight
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            InsightCard(
                label: "System/Rest",
                value: ByteCountFormatter.storageString(snapshot.unexplainedUsedBytes),
                note: "Shown explicitly instead of pretending to know more",
                tint: KleanTheme.info
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func scanCoverageText(_ snapshot: StorageSnapshot) -> String {
        let used = max(snapshot.volume.usedBytes, 1)
        let fraction = Double(snapshot.scannedBytes) / Double(used)
        return "\(Int((fraction * 100).rounded()))%"
    }
}

private struct CategoryHeroCard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let category: StorageCategory

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)

                        Image(systemName: category.systemImage)
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(KleanTheme.accent, KleanTheme.highlight)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HeroEyebrow(text: "Category")

                        Text(category.title)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(KleanTheme.ink)

                        Text(category.subtitle)
                            .font(.title3)
                            .foregroundStyle(KleanTheme.mutedInk)

                        Text(category.url.prettyPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(KleanTheme.quietInk)
                    }

                    Spacer()

                    if let recommendation = category.cleanupRecommendation {
                        Button {
                            viewModel.requestCleanup(recommendation)
                        } label: {
                            Label(recommendation.buttonLabel, systemImage: "trash.fill")
                        }
                        .buttonStyle(KleanPrimaryActionStyle())
                    }
                }

                HStack(spacing: 12) {
                    StatPill(label: "Size", value: ByteCountFormatter.storageString(category.totalBytes))
                    StatPill(label: "Files", value: category.itemCount.formatted())
                    StatPill(label: "Children", value: category.topChildren.count.formatted())
                }
            }
        }
    }
}

private struct StorageSummaryCard: View {
    let snapshot: StorageSnapshot

    private var segments: [StorageSegment] {
        let scanned = min(snapshot.scannedBytes, snapshot.volume.usedBytes)
        let rest = snapshot.unexplainedUsedBytes
        let free = max(snapshot.volume.availableBytes, 0)

        return [
            StorageSegment(label: "Scanned", value: scanned, color: KleanTheme.success),
            StorageSegment(label: "System/Rest", value: rest, color: KleanTheme.warning),
            StorageSegment(label: "Free", value: free, color: KleanTheme.info)
        ]
    }

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeadline(
                    eyebrow: "Volume",
                    title: "The physical truth of the drive",
                    subtitle: "Volume-level numbers plus the storage the scan can clearly attribute."
                )

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(ByteCountFormatter.storageString(snapshot.volume.usedBytes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(KleanTheme.ink)
                    Text("used")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(KleanTheme.mutedInk)
                    Spacer()
                    StatusCapsule(text: "\(coveragePercent)% scanned", tint: KleanTheme.accent)
                }

                StorageUsageBar(segments: segments, totalBytes: snapshot.volume.totalBytes)
                    .frame(height: 22)

                VStack(spacing: 10) {
                    ForEach(segments) { segment in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 10, height: 10)

                            Text(segment.label)
                                .foregroundStyle(KleanTheme.mutedInk)

                            Spacer()

                            Text(ByteCountFormatter.storageString(segment.value))
                                .fontWeight(.semibold)
                                .foregroundStyle(KleanTheme.ink)
                        }
                    }
                }

                HStack(spacing: 12) {
                    SummaryMetricCard(title: "Total", value: ByteCountFormatter.storageString(snapshot.volume.totalBytes))
                    SummaryMetricCard(title: "Free", value: ByteCountFormatter.storageString(snapshot.volume.availableBytes))
                    SummaryMetricCard(title: "Important Free", value: ByteCountFormatter.storageString(snapshot.volume.importantAvailableBytes))
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var coveragePercent: Int {
        let used = max(snapshot.volume.usedBytes, 1)
        return Int(((Double(snapshot.scannedBytes) / Double(used)) * 100).rounded())
    }
}

private struct QuickActionsCard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let recommendations: [CleanupRecommendation]

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeadline(
                    eyebrow: "Quick Clean",
                    title: "Safe one-click cleanups",
                    subtitle: "Only cleanup actions that are low risk and usually safe to regenerate."
                )

                if recommendations.isEmpty {
                    EmptyStateCard(
                        title: "Nothing automatable right now",
                        message: "The current snapshot does not expose any low-risk one-click cleanup worth running right now."
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(recommendations.prefix(4).enumerated()), id: \.element.id) { index, recommendation in
                            QuickActionRow(
                                index: index + 1,
                                recommendation: recommendation,
                                execute: { viewModel.requestCleanup(recommendation) }
                            )
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ReviewCleanupsCard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let recommendations: [CleanupRecommendation]

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeadline(
                    eyebrow: "Review Cleanups",
                    title: "Large wins that need review",
                    subtitle: "Apps, Docker images, simulator data, archives, and support folders with enough impact to be worth checking before removal."
                )

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(recommendations.prefix(8)) { recommendation in
                        ReviewCleanupRow(
                            recommendation: recommendation,
                            execute: { viewModel.requestCleanup(recommendation) }
                        )
                    }
                }
                .animation(.snappy(duration: 0.22), value: recommendations.map(\.id))
            }
        }
    }
}

private struct DeveloperRoutinesCard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let recommendations: [CleanupRecommendation]

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeadline(
                    eyebrow: "Developer Cleanups",
                    title: "Routine jobs for your development Mac",
                    subtitle: "High-confidence candidates from Xcode, SwiftPM, Flutter, and Docker that you can run directly from the dashboard."
                )

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(recommendations.prefix(6)) { recommendation in
                        DeveloperRoutineRow(
                            recommendation: recommendation,
                            execute: { viewModel.requestCleanup(recommendation) }
                        )
                    }
                }
            }
        }
    }
}

private struct CategoryTile: View {
    let category: StorageCategory
    let largestCategoryBytes: Int64

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.84))
                            .frame(width: 46, height: 46)

                        Image(systemName: category.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(KleanTheme.accent, KleanTheme.highlight)
                    }

                    Spacer()

                    if category.cleanupRecommendation != nil {
                        StatusCapsule(text: "Ready", tint: KleanTheme.highlight)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(.headline)
                        .foregroundStyle(KleanTheme.ink)
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundStyle(KleanTheme.mutedInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text(ByteCountFormatter.storageString(category.totalBytes))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(KleanTheme.ink)

                    Text("\(category.itemCount.formatted()) files")
                        .foregroundStyle(KleanTheme.mutedInk)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.06))

                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [KleanTheme.accent, KleanTheme.highlight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(proxy.size.width * share, 16))
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int((share * 100).rounded()))% of the largest category")
                        .font(.caption)
                        .foregroundStyle(KleanTheme.quietInk)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        }
    }

    private var share: CGFloat {
        let total = max(Double(largestCategoryBytes), 1)
        return CGFloat(Double(category.totalBytes) / total)
    }
}

private struct FileListCard: View {
    let title: String
    let subtitle: String
    let items: [StorageNode]
    @ObservedObject var viewModel: StorageDashboardViewModel

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeadline(eyebrow: "List", title: title, subtitle: subtitle)

                if items.isEmpty {
                    Text("No relevant items found.")
                        .foregroundStyle(KleanTheme.mutedInk)
                } else {
                    VStack(spacing: 10) {
                        ForEach(items.prefix(14)) { item in
                            FileRowCard(
                                item: item,
                                reveal: { viewModel.reveal(item.url) },
                                trash: { viewModel.requestTrash(item) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct FileRowCard: View {
    let item: StorageNode
    let reveal: () -> Void
    let trash: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 42, height: 42)

                Image(systemName: symbol(for: item.kind))
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(KleanTheme.accent, KleanTheme.highlight)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(KleanTheme.ink)
                    .lineLimit(1)

                Text(item.url.deletingLastPathComponent().prettyPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(KleanTheme.mutedInk)
                    .lineLimit(1)

                Text(detailLine(for: item))
                    .font(.caption)
                    .foregroundStyle(KleanTheme.quietInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteCountFormatter.storageString(item.bytes))
                    .font(.headline)
                    .foregroundStyle(KleanTheme.ink)

                HStack(spacing: 8) {
                    Button(action: reveal) {
                        Label("Reveal", systemImage: "magnifyingglass")
                    }
                        .buttonStyle(KleanSecondaryActionStyle())
                    Button(action: trash) {
                        Label("Trash", systemImage: "trash.fill")
                    }
                        .buttonStyle(KleanPrimaryActionStyle())
                }
            }
            .frame(minWidth: 152, alignment: .trailing)
        }
        .padding(14)
        .frame(minHeight: 94)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }
    }

    private func symbol(for kind: StorageNode.Kind) -> String {
        switch kind {
        case .file:
            return "doc.fill"
        case .folder:
            return "folder.fill"
        case .package:
            return "shippingbox.fill"
        }
    }

    private func detailLine(for item: StorageNode) -> String {
        let base = item.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
        if item.isDirectoryLike {
            return "\(item.itemCount.formatted()) files • \(base)"
        }
        return base
    }
}

private struct NoticeCard<Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder var content: Content

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeadline(eyebrow: "Notice", title: title, subtitle: message)
                content
            }
        }
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(KleanTheme.ink)
            Text(message)
                .foregroundStyle(KleanTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.48))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.52), lineWidth: 1)
        }
    }
}

private struct CardShell<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [KleanTheme.panelTop, KleanTheme.panelBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(KleanTheme.panelStroke, lineWidth: 1)
            }
            .shadow(color: KleanTheme.panelShadow, radius: 30, y: 18)
    }
}

private struct SectionHeadline: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeroEyebrow(text: eyebrow)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(KleanTheme.ink)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(KleanTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HeroEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(KleanTheme.quietInk)
    }
}

private struct HeroMetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(KleanTheme.quietInk)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(KleanTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 102, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
    }
}

private struct HeroStorageArtwork: View {
    let scanState: ScanState
    let snapshot: StorageSnapshot?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.70),
                            Color.white.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.54))
                        .frame(width: 196, height: 176)
                        .blur(radius: 8)

                    Image("BrandMark")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .shadow(color: .black.opacity(0.14), radius: 24, y: 14)
                }
                .overlay(alignment: .topTrailing) {
                    StatusCapsule(
                        text: snapshot.map { ByteCountFormatter.storageString($0.reclaimableBytes) } ?? "...",
                        tint: KleanTheme.highlight
                    )
                    .offset(x: 2, y: -6)
                }
                .overlay(alignment: .bottomLeading) {
                    StatusCapsule(
                        text: "\(Int((usageFraction * 100).rounded()))% used",
                        tint: KleanTheme.accent
                    )
                    .offset(x: -2, y: 8)
                }

                VStack(spacing: 6) {
                    Text(scanStateTitle)
                        .font(.headline)
                        .foregroundStyle(KleanTheme.ink)
                    Text(scanStateSubtitle)
                        .font(.caption)
                        .foregroundStyle(KleanTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 210)
                }
            }
            .padding(22)
        }
    }

    private var usageFraction: Double {
        guard let snapshot else { return 0.35 }
        let total = max(snapshot.volume.totalBytes, 1)
        return Double(snapshot.volume.usedBytes) / Double(total)
    }

    private var scanStateTitle: String {
        switch scanState {
        case .idle:
            return "Ready"
        case .scanning:
            return "Scanning"
        case .ready:
            return "Snapshot Current"
        case .failed:
            return "Scan Stopped"
        }
    }

    private var scanStateSubtitle: String {
        switch scanState {
        case .idle:
            return "The interface is waiting for the next run."
        case let .scanning(progress):
            return progress.statusSummary
        case let .ready(date):
            return "Last refreshed on \(date.formatted(date: .abbreviated, time: .shortened))."
        case let .failed(message):
            return message
        }
    }
}

private struct InsightCard: View {
    let label: String
    let value: String
    let note: String
    let tint: Color

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 10) {
                HeroEyebrow(text: label)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(KleanTheme.ink)
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(KleanTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.32)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        }
    }
}

private struct QuickActionRow: View {
    let index: Int
    let recommendation: CleanupRecommendation
    let execute: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(KleanTheme.ink.opacity(0.08))
                    .frame(width: 34, height: 34)
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(KleanTheme.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(KleanTheme.ink)

                    Spacer()

                    RiskBadge(risk: recommendation.risk)
                }

                Text(recommendation.summary)
                    .foregroundStyle(KleanTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label(ByteCountFormatter.storageString(recommendation.estimatedBytes), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KleanTheme.ink)
                    Spacer()
                    Button(action: execute) {
                        Label(recommendation.buttonLabel, systemImage: "sparkles")
                    }
                        .buttonStyle(KleanPrimaryActionStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(minHeight: 132)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.52))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        }
    }
}

private struct DeveloperRoutineRow: View {
    let recommendation: CleanupRecommendation
    let execute: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.80))
                    .frame(width: 50, height: 50)

                Image(systemName: recommendation.systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(KleanTheme.accent, KleanTheme.highlight)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(KleanTheme.ink)

                    RiskBadge(risk: recommendation.risk)

                    Spacer()

                    Text(ByteCountFormatter.storageString(recommendation.estimatedBytes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(KleanTheme.ink)
                }

                Text(recommendation.summary)
                    .foregroundStyle(KleanTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let detailText = recommendation.detailText {
                        Label(detailText, systemImage: recommendation.strategy == .runCommand ? "terminal.fill" : "folder.fill")
                            .font(.caption)
                            .foregroundStyle(KleanTheme.quietInk)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: execute) {
                        Label(recommendation.buttonLabel, systemImage: "sparkles")
                    }
                        .buttonStyle(KleanPrimaryActionStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(minHeight: 124)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        }
    }
}

private struct ReviewCleanupRow: View {
    let recommendation: CleanupRecommendation
    let execute: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.80))
                    .frame(width: 52, height: 52)

                Image(systemName: recommendation.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(KleanTheme.warning, KleanTheme.highlight)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(KleanTheme.ink)

                    ScopeBadge(scope: recommendation.scope)
                    RiskBadge(risk: recommendation.risk)

                    Spacer()

                    Text(ByteCountFormatter.storageString(recommendation.estimatedBytes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(KleanTheme.ink)
                }

                Text(recommendation.summary)
                    .foregroundStyle(KleanTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let detailText = recommendation.detailText {
                        Label(detailText, systemImage: recommendation.strategy == .runCommand ? "terminal.fill" : "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(KleanTheme.quietInk)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: execute) {
                        Label(recommendation.buttonLabel, systemImage: "trash.fill")
                    }
                        .buttonStyle(KleanSecondaryActionStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(minHeight: 128)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        }
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(KleanTheme.quietInk)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(KleanTheme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.48))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(KleanTheme.quietInk)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(KleanTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
    }
}

private struct StatusCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
    }
}

private struct RiskBadge: View {
    let risk: CleanupRisk

    var body: some View {
        Text(risk.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(risk.color.opacity(0.18))
            )
            .foregroundStyle(risk.color)
    }
}

private struct ScopeBadge: View {
    let scope: CleanupRecommendationScope

    var body: some View {
        Text(scope == .developer ? "Developer" : "Storage")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(KleanTheme.info.opacity(0.15))
            )
            .foregroundStyle(KleanTheme.info)
    }
}

private struct KleanPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                KleanTheme.accent.opacity(isEnabled ? 1 : 0.66),
                                KleanTheme.highlight.opacity(isEnabled ? 0.96 : 0.56)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.14), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct KleanSecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(KleanTheme.ink.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.90 : 0.74))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct KleanGhostActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(KleanTheme.mutedInk.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.34))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
            }
    }
}

private struct StorageUsageBar: View {
    let segments: [StorageSegment]
    let totalBytes: Int64

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(totalBytes), 1)

            HStack(spacing: 3) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(segment.color)
                        .frame(width: width(for: segment, total: total, available: proxy.size.width))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.08))
            )
        }
    }

    private func width(for segment: StorageSegment, total: Double, available: CGFloat) -> CGFloat {
        guard segment.value > 0 else { return 0 }
        let ratio = Double(segment.value) / total
        return max(CGFloat(ratio) * max(available - 6, 0), 12)
    }
}

private struct StorageSegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Int64
    let color: Color
}

private extension CleanupRisk {
    var color: Color {
        switch self {
        case .low:
            return KleanTheme.success
        case .medium:
            return KleanTheme.warning
        case .high:
            return KleanTheme.danger
        }
    }
}

private extension StorageSnapshot {
    var reclaimableBytes: Int64 {
        allCleanupRecommendations.reduce(into: 0) { partialResult, recommendation in
            partialResult += recommendation.estimatedBytes
        }
    }
}

extension ByteCountFormatter {
    static func storageString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        return formatter.string(fromByteCount: bytes)
    }
}

private extension URL {
    var prettyPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: homePath, with: "~")
    }
}
