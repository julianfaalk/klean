import SwiftUI

@main
struct KleanApp: App {
    @StateObject private var viewModel = StorageDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Neu Scannen") {
                    viewModel.startScan()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
