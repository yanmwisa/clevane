#if CLEVANE_SNAPSHOTS
import AppKit
import SwiftUI
import VaultCore

/// Debug builds only. With CLEVANE_SNAPSHOT_DIR set, the app runs on a temporary vault filled with
/// fictional data, walks through every screen, writes a PNG of its own window for each, then quits.
/// It never touches the real vault, the real preferences or the keychain.
@MainActor
enum SnapshotRunner {
    private static let outputFolder = ProcessInfo.processInfo.environment["CLEVANE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    private static let workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("clevane-snapshots-\(UUID().uuidString)")
    /// With a throwaway home (CFFIXED_USER_HOME), backups go where a real user's go, so the Backup screen shows no path of this Mac.
    private static let backupFolder = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]
        .map { _ in FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Clevane Backups", isDirectory: true) }
        ?? workFolder.appendingPathComponent("Backups")

    static var isRequested: Bool { outputFolder != nil }

    static func makeModel() -> AppModel {
        let preferences = MemoryPreferences()
        preferences.set(backupFolder, forKey: PreferenceKey.backupFolder)
        return AppModel(vaultURL: workFolder.appendingPathComponent("Vault.clevane"), keyStore: NoKeyStore(), preferences: preferences)
    }

    static func start(model: AppModel) {
        Task {
            await run(model: model)
            try? FileManager.default.removeItem(at: workFolder)
            NSApp.terminate(nil)
        }
    }

    private static func run(model: AppModel) async {
        guard let outputFolder else { return }
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        model.appearance = .light
        exportAppIcon(to: outputFolder.appendingPathComponent("AppIcon-1024.png"))
        await settle(seconds: 1.5)
        mainWindow?.setContentSize(NSSize(width: 1120, height: 720))
        await capture("01-welcome")

        // Pictures the signed build's quick path; this build cannot use it.
        model.isQuickUnlockAvailable = true
        await capture("01b-welcome-quick-unlock")
        model.createsWithQuickUnlock = true
        model.screen = .create
        await capture("02b-create-quick-passphrase")
        model.isQuickUnlockAvailable = false
        model.createsWithQuickUnlock = false
        model.screen = .welcome
        await settle(seconds: 0.4)

        model.screen = .create
        await capture("02-create-vault")

        await model.createVault(name: "Personal Vault", password: DemoContent.password, confirmation: DemoContent.password, enableTouchID: false)
        model.closeGuide()
        await capture("03b-get-started")
        DemoContent.fill(model, scratch: workFolder)
        model.lock()
        await capture("03-unlock")

        _ = await model.unlock(password: DemoContent.password)
        guard let trading = model.content.tables.first(where: { $0.name == "Trading" }) else { return }
        model.open(.table(trading.id))
        await capture("04-vault")

        if let secret = trading.columns.last { model.toggleReveal(secret.id) }
        model.select(trading.rows[2].id)
        if let secret = trading.columns.last { model.toggleReveal(secret.id) }
        await capture("05-vault-row-revealed")

        model.showGuide()
        await capture("05b-guide-tables")
        while model.guideStop != .rowDetail { model.moveGuide(by: 1) }
        await capture("05c-guide-row-detail")
        model.closeGuide()
        await settle(seconds: 0.6)

        model.searchText = "sample"
        await capture("05d-search-all-tables")
        model.searchText = ""
        if let documents = model.content.tables.first(where: { $0.name == "Documents" }) {
            model.open(.table(documents.id))
            await capture("05e-documents-photo")
            model.open(.table(trading.id))
        }

        await present(.columns(trading.id), as: "06-sheet-columns", model: model)
        await present(.addRow(trading.id), as: "07-sheet-add-row", model: model)
        await present(.newTable, as: "08-sheet-new-table", model: model)
        model.confirmation = .deleteTable(trading)
        await capture("08b-delete-table-confirmation")
        model.confirmation = nil
        await settle(seconds: 0.8)

        model.createBackup()
        model.open(.backup)
        await capture("09-backup-restore")
        model.toast = nil
        model.open(.settings)
        await capture("10-settings")

        model.appearance = .dark
        model.open(.table(trading.id))
        await capture("11-vault-dark")
        model.open(.settings)
        await capture("12-settings-dark")
        model.lock()
        await capture("13-unlock-dark")
        model.appearance = .system
    }

    private static func exportAppIcon(to url: URL) {
        let renderer = ImageRenderer(content: AppIconArtwork())
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private static func present(_ sheet: VaultSheet, as name: String, model: AppModel) async {
        model.sheet = sheet
        await capture(name)
        model.sheet = nil
        await settle(seconds: 0.8)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.contentView != nil }
    }

    private static func settle(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Draws the window, its sheet and its child windows (guide bubbles) into a bitmap: no screen recording permission involved.
    private static func capture(_ name: String) async {
        await settle(seconds: 1.4)
        guard let outputFolder, let window = mainWindow, let frameView = window.contentView?.superview else { return }
        let size = frameView.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        draw(frameView, at: .zero)
        let overlays = [window.attachedSheet].compactMap { $0 } + (window.childWindows ?? []).filter(\.isVisible)
        for overlay in overlays {
            guard let overlayView = overlay.contentView?.superview else { continue }
            draw(overlayView, at: NSPoint(x: overlay.frame.minX - window.frame.minX, y: overlay.frame.minY - window.frame.minY))
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: outputFolder.appendingPathComponent("\(name).png"))
    }

    private static func draw(_ view: NSView, at origin: NSPoint) {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        representation.draw(in: NSRect(origin: origin, size: view.bounds.size))
    }
}

/// Snapshots never write to the real keychain.
private struct NoKeyStore: VaultKeyStore {
    var isAvailable: Bool { false }
    func confirmPresence(reason: String) async throws { throw VaultError.biometryUnavailable }
    func storeKey(_ key: Data, for vaultID: UUID) throws { throw VaultError.biometryUnavailable }
    func loadKey(for vaultID: UUID, reason: String) throws -> Data { throw VaultError.biometryUnavailable }
    func deleteKey(for vaultID: UUID) throws {}
}
#endif
