import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: StorageDashboardViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .frame(minWidth: 320, idealWidth: 340)
        } detail: {
            ZStack {
                DetailCanvasBackground()
                    .ignoresSafeArea()

                Group {
                    if case .overview = viewModel.selection {
                        OverviewDashboard(viewModel: viewModel)
                    } else if let category = viewModel.selectedCategory {
                        CategoryDetailView(viewModel: viewModel, category: category)
                    } else {
                        OverviewDashboard(viewModel: viewModel)
                    }
                }
                .padding(28)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                ToolbarActionButton(title: "Rescan", systemImage: "arrow.clockwise.circle.fill") {
                    viewModel.startScan()
                }

                if case .scanning = viewModel.scanState {
                    ToolbarActionButton(title: "Stop Scan", systemImage: "stop.circle.fill") {
                        viewModel.cancelScan()
                    }
                }

                ToolbarActionButton(title: "Full Disk Access", systemImage: "lock.shield.fill") {
                    viewModel.openFullDiskAccessSettings()
                }
            }
        }
        .alert(item: $viewModel.activeAlert) { alert in
            switch alert.kind {
            case let .info(title, message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case let .confirmation(title, message, action):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    primaryButton: .destructive(Text("Run")) {
                        viewModel.perform(action)
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: StorageDashboardViewModel

    private var categories: [StorageCategory] {
        viewModel.snapshot?.sortedCategories ?? []
    }

    private var largestCategoryBytes: Int64 {
        categories.first?.totalBytes ?? 1
    }

    var body: some View {
        ZStack {
            SidebarBackground()

            VStack(alignment: .leading, spacing: 16) {
                SidebarHeader(snapshot: viewModel.snapshot)

                SidebarOverviewButton(
                    isSelected: matches(.overview)
                ) {
                    viewModel.selection = .overview
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Hotspots")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(1.1)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(categories) { category in
                                SidebarCategoryButton(
                                    category: category,
                                    isSelected: matches(.category(category.id)),
                                    maxBytes: largestCategoryBytes
                                ) {
                                    viewModel.select(category: category)
                                }
                            }
                        }
                        .padding(.trailing, 6)
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: .infinity)
                }

                ScanStatusFooter(
                    scanState: viewModel.scanState,
                    showsCachedData: viewModel.isShowingCachedData
                )
            }
            .padding(18)
        }
    }

    private func matches(_ selection: SidebarSelection) -> Bool {
        viewModel.selection == selection
    }
}

private struct SidebarHeader: View {
    let snapshot: StorageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SidebarAppMark()

                VStack(alignment: .leading, spacing: 2) {
                    Text("klean")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Storage control center")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }

            if let snapshot {
                HStack(spacing: 10) {
                    SidebarInfoChip(
                        label: "Used",
                        value: ByteCountFormatter.storageString(snapshot.volume.usedBytes)
                    )
                    SidebarInfoChip(
                        label: "Free",
                        value: ByteCountFormatter.storageString(snapshot.volume.availableBytes)
                    )
                }
            }

            Text(snapshotStatus)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.54))
        }
    }

    private var snapshotStatus: String {
        guard let snapshot else {
            return "No snapshot loaded yet."
        }

        return "Last snapshot: \(snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct SidebarInfoChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

private struct SidebarAppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)

            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
    }
}

private struct SidebarOverviewButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overview")
                        .font(.headline)
                    Text("All major hotspots at a glance")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .white.opacity(0.52))
                }
                Spacer()
            }
            .padding(14)
            .frame(minHeight: 62)
            .foregroundStyle(.white)
            .background(sidebarSelectionBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarCategoryButton: View {
    let category: StorageCategory
    let isSelected: Bool
    let maxBytes: Int64
    let action: () -> Void

    private var progress: Double {
        Double(category.totalBytes) / Double(max(maxBytes, 1))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.12) : Color.black.opacity(0.16))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: category.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.78))
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(category.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if category.cleanupRecommendation != nil {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(KleanTheme.highlight)
                            }
                        }
                        Text(ByteCountFormatter.storageString(category.totalBytes))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer(minLength: 8)
                }

                GeometryReader { proxy in
                    let width = max(proxy.size.width * progress, 18)
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, KleanTheme.highlight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: width)
                        }
                }
                .frame(height: 6)
            }
            .padding(14)
            .frame(minHeight: 88)
            .background(sidebarSelectionBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private struct ToolbarActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .tint(buttonTint)
    }

    private var buttonTint: Color {
        switch systemImage {
        case "stop.circle.fill":
            return .red
        case "lock.shield.fill":
            return KleanTheme.highlight
        default:
            return .accentColor
        }
    }
}

private struct SidebarBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KleanTheme.sidebarTop,
                    KleanTheme.sidebarBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 80)
                .offset(x: -70, y: -180)

            Circle()
                .fill(KleanTheme.highlight.opacity(0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 90)
                .offset(x: 140, y: 260)
        }
    }
}

private func sidebarSelectionBackground(isSelected: Bool) -> some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(
            isSelected
                ? LinearGradient(
                    colors: [Color.accentColor.opacity(0.92), KleanTheme.highlight.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04), lineWidth: 1)
        }
}
