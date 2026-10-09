import Foundation

/// Why the vault locked. Locking is mandatory and cannot be turned off; only the inactivity delay is a setting.
public enum LockReason: String, Sendable {
    case manual, inactivity, systemSleep, screenLocked, appQuit
}

/// Decides when inactivity requires a lock. The app records activity and asks on a timer;
/// system sleep and screen lock call `lock(because:)` directly.
@MainActor
public final class AutoLockMonitor {
    private let session: VaultSession
    private let clipboard: ClipboardService?
    private var lastActivity: Date

    public private(set) var lastReason: LockReason?

    public init(session: VaultSession, clipboard: ClipboardService?, now: Date = Date()) {
        self.session = session
        self.clipboard = clipboard
        self.lastActivity = now
    }

    public func recordActivity(at date: Date = Date()) {
        lastActivity = date
    }

    public static func isInactive(since lastActivity: Date, now: Date, delay: AutoLockDelay) -> Bool {
        now.timeIntervalSince(lastActivity) >= TimeInterval(delay.rawValue)
    }

    /// Returns true when it locked the vault.
    @discardableResult
    public func checkInactivity(now: Date = Date()) -> Bool {
        guard session.isOpen, Self.isInactive(since: lastActivity, now: now, delay: session.content.settings.autoLockDelay) else {
            return false
        }
        lock(because: .inactivity)
        return true
    }

    /// Clears a secret Clevane copied, then locks.
    public func lock(because reason: LockReason) {
        guard session.isOpen else { return }
        clipboard?.clearIfStillOurs()
        session.lock()
        lastReason = reason
    }
}
