import ClevaneUI
import SwiftUI

@main
struct ClevaneApp: App {
    @NSApplicationDelegateAdaptor(ClevaneAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Clevane") {
            RootView(model: delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Clevane") { AboutPanel.show() }
                Button("Check for Updates…") { Task { await delegate.model.checkForUpdates() } }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Vault") {
                Button("Lock Vault") { delegate.model.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .help) {
                Button("Clevane Guide") { delegate.model.showGuide() }
                    .disabled(delegate.model.screen != .vault)
            }
        }
    }
}
