import SwiftUI

enum KleanTheme {
    static let canvasTop = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let canvasBottom = Color(red: 0.90, green: 0.93, blue: 0.89)
    static let hazeGreen = Color(red: 0.63, green: 0.78, blue: 0.67)
    static let hazeGold = Color(red: 0.90, green: 0.77, blue: 0.58)
    static let ink = Color(red: 0.15, green: 0.18, blue: 0.17)
    static let mutedInk = Color(red: 0.38, green: 0.41, blue: 0.38)
    static let panelTop = Color.white.opacity(0.92)
    static let panelBottom = Color.white.opacity(0.72)
    static let panelStroke = Color.white.opacity(0.70)
    static let sidebarTop = Color(red: 0.12, green: 0.15, blue: 0.15)
    static let sidebarBottom = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let highlight = Color(red: 0.92, green: 0.62, blue: 0.27)
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
                .fill(KleanTheme.hazeGreen.opacity(0.32))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: -240, y: -220)

            Circle()
                .fill(KleanTheme.hazeGold.opacity(0.28))
                .frame(width: 480, height: 480)
                .blur(radius: 100)
                .offset(x: 260, y: -160)

            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 600, height: 600)
                .blur(radius: 120)
                .offset(x: 180, y: 260)
        }
    }
}

struct OverviewDashboard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel

    private let categoryColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let snapshot = viewModel.snapshot {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StorageSummaryCard(snapshot: snapshot)
                        QuickActionsCard(viewModel: viewModel, recommendations: snapshot.cleanupRecommendations)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeadline(title: "Groesste Bereiche", subtitle: "Die wichtigsten Speicherblöcke im gescannten Bereich.")
                        LazyVGrid(columns: categoryColumns, spacing: 16) {
                            ForEach(snapshot.sortedCategories.prefix(8)) { category in
                                CategoryTile(category: category)
                                    .onTapGesture {
                                        viewModel.select(category: category)
                                    }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeadline(title: "Groesste Dateien", subtitle: "Direkt verwaltbare Einzeldateien ausserhalb von App-Paketen.")
                        FileListCard(
                            title: "Top Dateien",
                            subtitle: "Per Finder pruefen oder direkt in den Papierkorb verschieben.",
                            items: snapshot.largestFiles,
                            viewModel: viewModel
                        )
                    }

                    if !snapshot.inaccessiblePaths.isEmpty {
                        NoticeCard(
                            title: "Nicht alles war lesbar",
                            message: "Einige Pfade waren fuer den Scan nicht zugaenglich. Fuer tiefere Einblicke brauchst du meist Full Disk Access fuer die App oder fuer Xcode."
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(snapshot.inaccessiblePaths.prefix(5), id: \.path) { url in
                                    Text(url.prettyPath)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(KleanTheme.mutedInk)
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateCard(
                        title: "Speicher wird gescannt",
                        message: "klean laeuft die typischen Speicher-Hotspots durch und baut daraus einen verwaltbaren Ueberblick auf."
                    )
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speicher endlich greifbar")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(KleanTheme.ink)

            Text("Die App zeigt dir grosse Speicherbereiche, einzelne Verursacher und sichere Aufraeumaktionen. Nicht aufschluesselbare macOS-Systemdaten bleiben als Restblock sichtbar, statt versteckt zu werden.")
                .font(.title3)
                .foregroundStyle(KleanTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CategoryDetailView: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let category: StorageCategory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 56, height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(KleanTheme.ink)
                            Text(category.subtitle)
                                .foregroundStyle(KleanTheme.mutedInk)
                        }

                        Spacer()

                        if let recommendation = category.cleanupRecommendation {
                            Button(recommendation.buttonLabel) {
                                viewModel.requestCleanup(recommendation)
                            }
                            .buttonStyle(KleanPrimaryActionStyle())
                        }
                    }

                    HStack(spacing: 10) {
                        StatPill(label: "Groesse", value: ByteCountFormatter.storageString(category.totalBytes))
                        StatPill(label: "Dateien", value: category.itemCount.formatted())
                        StatPill(label: "Pfad", value: category.url.prettyPath)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeadline(title: "Groesste Inhalte", subtitle: "Direkte Kinder dieses Bereichs, sortiert nach belegtem Speicher.")
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
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeadline(title: "Tiefe Einzeldateien", subtitle: "Die groessten Dateien innerhalb dieses Bereichs, sofern sie nicht in App-Paketen liegen.")
                            FileListCard(
                                title: "Einzeldateien",
                                subtitle: "Hilfreich fuer punktuelle Bereinigung.",
                                items: filesInsideCategory,
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

struct ScanStatusFooter: View {
    let scanState: ScanState
    let showsCachedData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))

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

            if showsCachedData {
                Text("Zeige zuletzt erkannten Stand aus dem Cache.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
            StorageSegment(label: "Analysiert", value: scanned, color: Color(red: 0.17, green: 0.62, blue: 0.39)),
            StorageSegment(label: "System/Rest", value: rest, color: Color(red: 0.85, green: 0.55, blue: 0.18)),
            StorageSegment(label: "Frei", value: free, color: Color(red: 0.24, green: 0.42, blue: 0.79))
        ]
    }

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeadline(title: "Volume", subtitle: "Echte Volumenwerte plus das, was der Scan konkret aufgeschluesselt hat.")

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ByteCountFormatter.storageString(snapshot.volume.usedBytes))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(KleanTheme.ink)
                        Text("belegt")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(KleanTheme.mutedInk)
                        Spacer()
                        Text("\(Int((Double(snapshot.scannedBytes) / Double(max(snapshot.volume.usedBytes, 1))) * 100)) % analysiert")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }

                    StorageUsageBar(segments: segments, totalBytes: snapshot.volume.totalBytes)
                        .frame(height: 20)

                    ForEach(segments) { segment in
                        HStack {
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

                Divider()

                HStack(spacing: 14) {
                    SummaryMetric(title: "Gesamt", value: ByteCountFormatter.storageString(snapshot.volume.totalBytes))
                    SummaryMetric(title: "Frei", value: ByteCountFormatter.storageString(snapshot.volume.availableBytes))
                    SummaryMetric(title: "Scanned", value: ByteCountFormatter.storageString(snapshot.scannedBytes))
                }
            }
        }
    }
}

private struct QuickActionsCard: View {
    @ObservedObject var viewModel: StorageDashboardViewModel
    let recommendations: [CleanupRecommendation]

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeadline(title: "Quick Clean", subtitle: "Nur fuer Bereiche mit halbwegs sicherer automatischer Bereinigung.")

                if recommendations.isEmpty {
                    EmptyStateCard(
                        title: "Keine Sofort-Aktionen",
                        message: "Gerade gibt es nichts Sinnvolles, das die App automatisch bereinigen sollte."
                    )
                } else {
                    ForEach(recommendations.prefix(4)) { recommendation in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(recommendation.title)
                                        .font(.headline)
                                        .foregroundStyle(KleanTheme.ink)
                                    Spacer()
                                    RiskBadge(risk: recommendation.risk)
                                }

                                Text(recommendation.summary)
                                    .foregroundStyle(KleanTheme.mutedInk)
                                Text("Potenzial: \(ByteCountFormatter.storageString(recommendation.estimatedBytes))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KleanTheme.ink)
                            }

                            Button(recommendation.buttonLabel) {
                                viewModel.requestCleanup(recommendation)
                            }
                            .buttonStyle(KleanPrimaryActionStyle())
                            .controlSize(.regular)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.48))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryTile: View {
    let category: StorageCategory

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: category.systemImage)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if category.cleanupRecommendation != nil {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.orange)
                    }
                }

                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(KleanTheme.ink)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(KleanTheme.mutedInk)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(ByteCountFormatter.storageString(category.totalBytes))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KleanTheme.ink)
                Text("\(category.itemCount.formatted()) Dateien")
                    .foregroundStyle(KleanTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        }
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
                SectionHeadline(title: title, subtitle: subtitle)

                if items.isEmpty {
                    Text("Keine relevanten Elemente gefunden.")
                        .foregroundStyle(KleanTheme.mutedInk)
                } else {
                    ForEach(items.prefix(14)) { item in
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: symbol(for: item.kind))
                                .font(.title3)
                                .frame(width: 24)
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundStyle(KleanTheme.ink)
                                    .lineLimit(1)
                                Text(item.url.deletingLastPathComponent().prettyPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(KleanTheme.mutedInk)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 16)

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(ByteCountFormatter.storageString(item.bytes))
                                    .font(.headline)
                                    .foregroundStyle(KleanTheme.ink)
                                Text(detailLine(for: item))
                                    .font(.caption)
                                    .foregroundStyle(KleanTheme.mutedInk)
                            }

                            HStack(spacing: 8) {
                                Button("Finder") {
                                    viewModel.reveal(item.url)
                                }
                                .buttonStyle(KleanSecondaryActionStyle())

                                Button("Trash") {
                                    viewModel.requestTrash(item)
                                }
                                .buttonStyle(KleanPrimaryActionStyle())
                            }
                        }
                        .padding(.vertical, 4)

                        if item.id != items.prefix(14).last?.id {
                            Divider()
                        }
                    }
                }
            }
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
        let base = item.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "ohne Datum"
        if item.isDirectoryLike {
            return "\(item.itemCount.formatted()) Dateien • \(base)"
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
                Text(title)
                    .font(.headline)
                    .foregroundStyle(KleanTheme.ink)
                Text(message)
                    .foregroundStyle(KleanTheme.mutedInk)
                content
            }
        }
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        CardShell {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(KleanTheme.ink)
                Text(message)
                    .foregroundStyle(KleanTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                KleanTheme.panelTop,
                                KleanTheme.panelBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(KleanTheme.panelStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 24, y: 14)
    }
}

private struct SectionHeadline: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(KleanTheme.ink)
            Text(subtitle)
                .foregroundStyle(KleanTheme.mutedInk)
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(KleanTheme.mutedInk)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(KleanTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KleanTheme.mutedInk)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(KleanTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.66))
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

private struct KleanPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(isEnabled ? 1 : 0.65),
                                KleanTheme.highlight.opacity(isEnabled ? 0.95 : 0.55)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
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
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.86 : 0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct StorageUsageBar: View {
    let segments: [StorageSegment]
    let totalBytes: Int64

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(totalBytes), 1)
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    segment.color
                        .frame(width: width(for: segment, total: total, available: proxy.size.width))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
    }

    private func width(for segment: StorageSegment, total: Double, available: CGFloat) -> CGFloat {
        guard segment.value > 0 else { return 0 }
        let ratio = Double(segment.value) / total
        return max(CGFloat(ratio) * available, 12)
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
            return Color(red: 0.17, green: 0.62, blue: 0.39)
        case .medium:
            return Color(red: 0.86, green: 0.55, blue: 0.14)
        case .high:
            return Color(red: 0.82, green: 0.23, blue: 0.19)
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
