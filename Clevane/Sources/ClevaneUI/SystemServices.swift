import AppKit
import VaultCore

/// NSPasteboard behind VaultCore's Pasteboard boundary.
@MainActor
final class SystemPasteboard: VaultCore.Pasteboard {
    /// nspasteboard.org convention: clipboard managers do not record items carrying this type.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    func writeConcealed(_ value: String) -> Int {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedType], owner: nil)
        pasteboard.setString(value, forType: .string)
        pasteboard.setString("", forType: Self.concealedType)
        return pasteboard.changeCount
    }

    func clear() {
        pasteboard.clearContents()
    }
}

/// Locks on system sleep, display sleep, screen lock and user switch (quit is handled by the app delegate); records activity for the
/// inactivity delay. Locking cannot be turned off: only the delay is a setting.
@MainActor
final class SystemLockObserver {
    private weak var model: AppModel?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var eventMonitor: Any?
    private var timer: Timer?

    nonisolated static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")

    /// Centers are injectable so tests can post on private centers instead of broadcasting system events.
    init(
        model: AppModel,
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.model = model
        observe(workspace, NSWorkspace.willSleepNotification, reason: .systemSleep)
        observe(workspace, NSWorkspace.screensDidSleepNotification, reason: .systemSleep)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, reason: .screenLocked)
        observe(distributed, Self.screenIsLocked, reason: .screenLocked)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            self?.model?.recordActivity()
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.checkInactivity() }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, reason: LockReason) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.lock(because: reason) }
        }
        tokens.append((center, token))
    }

    func stop() {
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens = []
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        timer?.invalidate()
        timer = nil
    }
}
