import AppKit
import VaultCore

/// Owns the app model and the system lock observer for the life of the app.
@MainActor
public final class ClevaneAppDelegate: NSObject, NSApplicationDelegate {
    public let model: AppModel
    private var lockObserver: SystemLockObserver?

    override public init() {
        #if CLEVANE_SNAPSHOTS
        if SnapshotRunner.isRequested {
            model = SnapshotRunner.makeModel()
        } else if let demo = DemoVault.requestedURL {
            model = DemoVault.makeModel(at: demo)
        } else {
            model = AppModel()
        }
        #else
        model = AppModel()
        #endif
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model.applyAppearance()
        lockObserver = SystemLockObserver(model: model)
        #if CLEVANE_SNAPSHOTS
        if let demo = DemoVault.requestedURL { DemoVault.prepare(model, at: demo) }
        if SnapshotRunner.isRequested {
            SnapshotRunner.start(model: model)
            return
        }
        #endif
        NSApp.activate()
        if model.checksUpdatesAtLaunch {
            Task { await model.checkForUpdates(quietly: true) }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.lock(because: .appQuit)
        lockObserver?.stop()
    }
}
