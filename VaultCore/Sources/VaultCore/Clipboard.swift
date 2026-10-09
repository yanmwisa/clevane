import Foundation

/// The system pasteboard, implemented by the app with NSPasteboard (VaultCore imports no AppKit).
@MainActor
public protocol Pasteboard: AnyObject {
    /// Number that changes whenever anyone writes to the pasteboard.
    var changeCount: Int { get }
    /// Writes `value` marked as concealed (nspasteboard.org convention) so clipboard history tools skip it,
    /// and returns the change count right after the write.
    func writeConcealed(_ value: String) -> Int
    func clear()
}

/// Copy with automatic clearing. A copy started in a session that has since been locked is refused (A4).
@MainActor
public final class ClipboardService {
    private let pasteboard: Pasteboard
    private let session: VaultSession
    private let clearDelayOverride: Duration?
    private var ownChangeCount: Int?
    private var pendingClear: Task<Void, Never>?

    public convenience init(pasteboard: Pasteboard, session: VaultSession) {
        self.init(pasteboard: pasteboard, session: session, clearDelayOverride: nil)
    }

    /// Tests use a short delay instead of the 30 or 60 seconds of the settings.
    init(pasteboard: Pasteboard, session: VaultSession, clearDelayOverride: Duration?) {
        self.pasteboard = pasteboard
        self.session = session
        self.clearDelayOverride = clearDelayOverride
    }

    public func copy(_ value: String, startedIn generation: Int) throws {
        guard session.isCurrent(generation) else { throw VaultError.vaultLocked }
        write(value, clearingAfter: .seconds(session.content.settings.clipboardClearDelay.rawValue))
    }

    /// For a value that is not in a vault yet (the passphrase proposed at creation): there is no
    /// session to check, so the caller sets the delay. The caller must keep this service alive.
    public func copyBeforeVaultExists(_ value: String, clearingAfter delay: Duration) {
        write(value, clearingAfter: delay)
    }

    private func write(_ value: String, clearingAfter defaultDelay: Duration) {
        ownChangeCount = pasteboard.writeConcealed(value)
        let delay = clearDelayOverride ?? defaultDelay
        pendingClear?.cancel()
        pendingClear = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.clearIfStillOurs()
        }
    }

    /// Clears only if the pasteboard still holds what Clevane copied: never erases something copied later elsewhere.
    public func clearIfStillOurs() {
        pendingClear?.cancel()
        pendingClear = nil
        guard let ownChangeCount, pasteboard.changeCount == ownChangeCount else { return }
        pasteboard.clear()
        self.ownChangeCount = nil
    }
}
