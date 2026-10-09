import AppKit
import Observation
import UniformTypeIdentifiers
import VaultCore

public enum AppScreen: Equatable {
    case welcome, create, unlock, vault
}

public enum VaultSection: Hashable {
    case table(UUID), start, backup, settings
}

public enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// What macOS asks for when quick unlock is used: Touch ID when the Mac has it, otherwise its login password.
enum QuickUnlockKind {
    case touchID, macPassword

    var name: String {
        switch self {
        case .touchID: "Touch ID"
        case .macPassword: "Mac password"
        }
    }

    var symbol: String {
        switch self {
        case .touchID: "touchid"
        case .macPassword: "laptopcomputer"
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Screen state and user actions. Every vault operation goes through VaultSession (the only authority);
/// this model only routes, reports errors and wires system services.
@MainActor
@Observable
public final class AppModel {
    public private(set) var session: VaultSession
    public var screen: AppScreen
    public var section: VaultSection?
    public var selectedRowID: UUID?
    public var searchText = ""
    var revealedColumns: Set<UUID> = []
    var alert: AppAlert?
    var sheet: VaultSheet?
    var confirmation: Confirmation?
    var toast: String?
    var isWorking = false
    /// Increments when a row or table is opened, so the detail can play its entrance once.
    var detailEntrance = 0
    /// Set when creation started from the quick unlock prompt: the vault gets quick unlock and a backup passphrase.
    var createsWithQuickUnlock = false
    /// Read once at launch: it depends on the build's entitlements and the Mac's settings.
    var isQuickUnlockAvailable: Bool
    /// The guide's current bubble; nil when the guide is closed.
    var guideStop: GuideStop?
    /// A newer published version found by a check; the window offers to open its download page.
    var updateOffer: Release?
    /// Off by default: Clevane works offline unless the person chooses to check at launch.
    var checksUpdatesAtLaunch: Bool {
        didSet { preferences.set(checksUpdatesAtLaunch, forKey: PreferenceKey.checkUpdatesAtLaunch) }
    }

    @ObservationIgnored var releaseSource: ReleaseSource = GitHubReleaseSource()
    @ObservationIgnored var installedVersion = AppInfo.version
    @ObservationIgnored let keyStore: VaultKeyStore
    @ObservationIgnored let preferences: UserDefaults
    @ObservationIgnored private(set) var clipboard: ClipboardService?
    @ObservationIgnored private(set) var autoLock: AutoLockMonitor?
    @ObservationIgnored private let pasteboard = SystemPasteboard()
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// The passphrase written to a file during creation: once the vault exists, it is kept inside it and the
    /// plain text file is offered to the Trash.
    @ObservationIgnored private var savedPassphraseFile: (url: URL, passphrase: String)?
    /// Copies the passphrase proposed at creation; kept for the app's life so its clearing always runs.
    @ObservationIgnored private lazy var setupClipboard = ClipboardService(pasteboard: pasteboard, session: session)

    public init(vaultURL: URL? = nil, keyStore: VaultKeyStore = SecureEnclaveKeyStore(folder: AppModel.quickUnlockFolder()), preferences: UserDefaults = .standard) {
        self.keyStore = keyStore
        self.preferences = preferences
        isQuickUnlockAvailable = keyStore.isAvailable
        appearance = Appearance(rawValue: preferences.string(forKey: PreferenceKey.appearance) ?? "") ?? .system
        checksUpdatesAtLaunch = preferences.bool(forKey: PreferenceKey.checkUpdatesAtLaunch)
        let url = vaultURL ?? preferences.url(forKey: PreferenceKey.vaultPath) ?? Self.defaultVaultURL()
        let file = VaultFile(url: url)
        session = VaultSession(file: file)
        screen = file.exists ? .unlock : .welcome
    }

    public static func defaultVaultURL() -> URL {
        supportFolder().appendingPathComponent("Vault.clevane")
    }

    /// Sealed vault keys for quick unlock, one file per vault; only this Mac's Secure Enclave opens them.
    public static func quickUnlockFolder() -> URL {
        supportFolder().appendingPathComponent("QuickUnlock", isDirectory: true)
    }

    private static func supportFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Clevane", isDirectory: true)
    }

    var content: VaultContent { session.content }

    var currentTable: VaultTable? {
        guard case .table(let id) = section else { return nil }
        return content.table(id)
    }

    var selectedRow: Row? {
        guard let table = currentTable else { return nil }
        return table.rows.first { $0.id == selectedRowID } ?? table.rows.first
    }

    // MARK: Create, unlock, lock

    /// Fast path: the system prompt (Touch ID or Mac password) first, then the backup passphrase.
    /// A dismissed prompt simply leaves the user on Welcome.
    func startQuickCreate() async {
        guard isQuickUnlockAvailable else { return }
        do {
            try await keyStore.confirmPresence(reason: "create your Clevane vault")
            createsWithQuickUnlock = true
            screen = .create
        } catch VaultError.biometryCancelled {
            return
        } catch {
            report(error)
        }
    }

    func startPasswordCreate() {
        createsWithQuickUnlock = false
        screen = .create
    }

    /// Longer than for vault secrets: the passphrase must reach a safe place (a note, a password sheet)
    /// before it is cleared. A 30 second window lost one on the first try.
    func copyNewPassphrase(_ passphrase: String) {
        setupClipboard.copyBeforeVaultExists(passphrase, clearingAfter: .seconds(120))
        showToast("Passphrase copied. Clears in 2 minutes.")
    }

    /// A second way to keep the proposed passphrase when the clipboard is not enough: a plain text file,
    /// readable by its owner only, at a place the person chose.
    func savePassphrase(_ passphrase: String, to file: URL) {
        do {
            try Data("Clevane master passphrase\n\(passphrase)\n".utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            savedPassphraseFile = (file, passphrase)
            showToast("Passphrase saved to \(file.lastPathComponent).")
        } catch {
            report(.writeFailed)
        }
    }

    func createVault(name: String, password: String, confirmation: String, enableTouchID: Bool) async {
        guard !password.isEmpty else { return report(.invalidContent(.emptyPassword)) }
        guard password == confirmation else { return report(.invalidContent(.passwordsDoNotMatch)) }
        isWorking = true
        defer { isWorking = false }
        do {
            try FileManager.default.createDirectory(at: session.file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let created = try await VaultSession.create(at: session.file.url, password: password)
            try created.edit { $0.renameVault(to: name) }
            preferences.set(created.file.url, forKey: PreferenceKey.vaultPath)
            didOpen(created)
            if enableTouchID { setTouchID(enabled: true) }
            createsWithQuickUnlock = false
            keepSavedPassphrase(matching: password)
        } catch {
            report(error)
        }
    }

    /// The file holds the vault's passphrase: keep it in a Recovery table, then offer the file to the Trash.
    /// A file holding an earlier suggestion is only offered to the Trash.
    private func keepSavedPassphrase(matching password: String) {
        guard let saved = savedPassphraseFile else { return }
        savedPassphraseFile = nil
        let note = "Set when this vault was created, \(Date().formatted(date: .long, time: .omitted)). If you change the master password, update this row."
        var isKept = false
        if saved.passphrase == password, let tableID = perform({ try $0.keepRecoveryPassphrase(password, note: note) }) {
            open(.table(tableID))
            isKept = true
        }
        confirmation = .trashPassphraseFile(saved.url, isKeptInVault: isKept)
    }

    func unlock(password: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.unlock(password: password)
            didOpen(session)
            return true
        } catch {
            report(error)
            return false
        }
    }

    var isTouchIDEnabled: Bool {
        guard let vaultID = try? session.vaultID() else { return false }
        return touchIDVaults.contains(vaultID.uuidString)
    }


    /// The vault's file name: its own name is encrypted, so the Unlock screen names the file instead.
    var vaultFileName: String { session.file.url.deletingPathExtension().lastPathComponent }

    var quickUnlockKind: QuickUnlockKind { SecureEnclaveKeyStore.hasTouchID ? .touchID : .macPassword }

    func quickUnlock() async {
        guard let vaultID = try? session.vaultID() else { return }
        let store = keyStore
        do {
            let key = try await Task.detached { try store.loadKey(for: vaultID, reason: "unlock your Clevane vault") }.value
            try session.unlock(vaultKey: key)
            didOpen(session)
        } catch VaultError.biometryInvalidated {
            forgetTouchID(for: vaultID)
            report(VaultError.biometryInvalidated)
        } catch {
            report(error)
        }
    }

    /// Clears a copied secret, locks the session, then shows the Unlock screen.
    public func lock(because reason: LockReason = .manual) {
        if let autoLock {
            autoLock.lock(because: reason)
        } else if session.isOpen {
            session.lock()
        }
        showLockedScreen()
    }

    func recordActivity() {
        autoLock?.recordActivity()
    }

    func checkInactivity(now: Date = Date()) {
        guard let autoLock, autoLock.checkInactivity(now: now) else { return }
        showLockedScreen()
    }

    private func showLockedScreen() {
        guard screen == .vault else { return }
        clipboard = nil
        autoLock = nil
        selectedRowID = nil
        revealedColumns = []
        searchText = ""
        guideStop = nil
        screen = .unlock
    }

    private func didOpen(_ opened: VaultSession) {
        session = opened
        clipboard = ClipboardService(pasteboard: pasteboard, session: opened)
        autoLock = AutoLockMonitor(session: opened, clipboard: clipboard)
        section = homeSection
        selectedRowID = nil
        revealedColumns = []
        screen = .vault
        detailEntrance += 1
        session.removeUnusedAttachments()
        showGuideIfFirstTime()
    }

    /// The first table, or Get started while the vault is empty.
    private var homeSection: VaultSection {
        content.tables.first.map { .table($0.id) } ?? .start
    }

    // MARK: Guide

    /// Stops whose place is on screen now: columns and rows need an open table, details a selected row.
    var guideStops: [GuideStop] {
        GuideStop.allCases.filter { stop in
            switch stop {
            case .columns, .addRow: currentTable != nil
            case .rowDetail: selectedRow != nil
            default: true
            }
        }
    }

    public func showGuide() {
        guideStop = guideStops.first
    }

    /// The guide waits for a first table: an empty vault starts on Get started instead.
    private func showGuideIfFirstTime() {
        guard !content.tables.isEmpty, preferences.object(forKey: PreferenceKey.guideSeen) as? Bool != true else { return }
        showGuide()
    }

    /// Next or previous bubble; past the last one the guide closes.
    func moveGuide(by offset: Int) {
        let stops = guideStops
        guard let current = guideStop, let index = stops.firstIndex(of: current), stops.indices.contains(index + offset) else {
            return closeGuide()
        }
        guideStop = stops[index + offset]
    }

    /// Remembered for this Mac, so the guide only opens by itself the first time.
    func closeGuide() {
        guideStop = nil
        preferences.set(true, forKey: PreferenceKey.guideSeen)
    }

    // MARK: Navigation

    func open(_ newSection: VaultSection) {
        guard newSection != section else { return }
        section = newSection
        selectedRowID = nil
        revealedColumns = []
        searchText = ""
        detailEntrance += 1
    }

    /// Opens the table that holds a search hit and selects the row; the search is done.
    func openSearchResult(_ hit: SearchHit) {
        open(.table(hit.tableID))
        select(hit.rowID)
    }

    func select(_ rowID: UUID) {
        guard rowID != selectedRow?.id else { return }
        selectedRowID = rowID
        revealedColumns = []
        detailEntrance += 1
    }

    func toggleReveal(_ columnID: UUID) {
        if revealedColumns.contains(columnID) {
            revealedColumns.remove(columnID)
        } else {
            revealedColumns.insert(columnID)
        }
    }

    // MARK: Edits (each one validated, then written atomically by the session)

    @discardableResult
    func perform<Result>(_ change: (inout VaultContent) throws -> Result) -> Result? {
        do {
            return try session.edit(change)
        } catch {
            report(error)
            return nil
        }
    }

    func createTable(name: String, columns: [Column]) -> Bool {
        guard let tableID = perform({ try $0.addTable(name: name, columns: columns) }) else { return false }
        open(.table(tableID))
        showGuideIfFirstTime()
        return true
    }

    /// Reads a browser password export into a new Logins table, then offers to move the plain text file
    /// to the Trash: the vault now holds those passwords encrypted, the CSV still holds them in clear.
    func importBrowserExport(from file: URL) {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= BrowserImport.maximumBytes, let text = try? String(contentsOf: file, encoding: .utf8) else {
            return report(.unrecognizedImport)
        }
        do {
            let logins = try BrowserImport.logins(fromCSV: text)
            let name = content.availableTableName("Imported Logins")
            guard let tableID = perform({ try $0.importLogins(logins, tableName: name) }) else { return }
            open(.table(tableID))
            showGuideIfFirstTime()
            showToast("\(logins.count) \(logins.count == 1 ? "login" : "logins") imported.")
            confirmation = .trashImportedFile(file)
        } catch {
            report(error)
        }
    }

    func moveToTrash(_ file: URL) {
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            showToast("“\(file.lastPathComponent)” is in the Trash. Empty it to finish.")
        } catch {
            report(error)
        }
    }

    /// One click: the template's columns under its name, numbered if that name is taken.
    @discardableResult
    func createTable(from template: TableTemplate) -> Bool {
        createTable(name: content.availableTableName(template.name), columns: template.makeColumns())
    }

    func deleteTable(_ tableID: UUID) {
        guard perform({ try $0.deleteTable(tableID) }) != nil else { return }
        session.removeUnusedAttachments()
        section = homeSection
        selectedRowID = nil
    }

    /// Saves the whole row, files included; files the row no longer uses are then removed from disk.
    func saveRow(_ values: [UUID: String], attachments: [UUID: Attachment], editing rowID: UUID?, in tableID: UUID) -> Bool {
        defer { session.removeUnusedAttachments() }
        if let rowID {
            return perform { try $0.updateRow(rowID, in: tableID, values: values, attachments: attachments) } != nil
        }
        guard let newRowID = perform({ try $0.addRow(to: tableID, values: values, attachments: attachments) }) else { return false }
        select(newRowID)
        return true
    }

    func deleteRow(_ rowID: UUID, in tableID: UUID) {
        guard perform({ try $0.deleteRow(rowID, in: tableID) }) != nil else { return }
        session.removeUnusedAttachments()
        selectedRowID = nil
        detailEntrance += 1
    }

    func saveColumns(_ columns: [Column], of tableID: UUID) -> Bool {
        guard perform({ try $0.setColumns(columns, of: tableID) }) != nil else { return false }
        session.removeUnusedAttachments()
        return true
    }

    // MARK: Files

    /// Encrypts a chosen file for a File column. Too large a file is refused before it is read.
    func attachFile(at url: URL) -> Attachment? {
        let details = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard (details?.fileSize ?? 0) <= Attachment.maximumByteCount else {
            report(.fileTooLarge)
            return nil
        }
        do {
            let fileBytes = try Data(contentsOf: url)
            return try session.sealAttachment(fileBytes, name: url.lastPathComponent, contentType: (details?.contentType ?? .data).identifier)
        } catch {
            report(error)
            return nil
        }
    }

    /// Decrypted bytes, in memory only, for a photo preview.
    func attachmentData(_ attachment: Attachment) -> Data? {
        try? session.openAttachment(attachment)
    }

    /// The only way a file leaves the vault in clear: to a place the person chose in a save panel.
    func export(_ attachment: Attachment, to destination: URL) {
        do {
            try session.openAttachment(attachment).write(to: destination, options: .atomic)
            showToast("\(attachment.name) exported.")
        } catch {
            report(error)
        }
    }

    func copy(_ value: String, label: String) {
        guard let clipboard else { return }
        do {
            try clipboard.copy(value, startedIn: session.generation)
            showToast("\(label) copied. Clears in \(content.settings.clipboardClearDelay.rawValue) seconds.")
        } catch {
            report(error)
        }
    }

    // MARK: Settings

    func setAutoLockDelay(_ delay: AutoLockDelay) {
        perform { $0.settings.autoLockDelay = delay }
    }

    func setClipboardDelay(_ delay: ClipboardClearDelay) {
        perform { $0.settings.clipboardClearDelay = delay }
    }

    func setTouchID(enabled: Bool) {
        guard let vaultID = try? session.vaultID() else { return }
        guard enabled else { return forgetTouchID(for: vaultID) }
        do {
            try keyStore.storeKey(try session.vaultKeyForKeychain(), for: vaultID)
            touchIDVaults.insert(vaultID.uuidString)
        } catch {
            report(error)
        }
    }

    /// Opened with Touch ID or the Mac password: a new master password can be set without the current one.
    var canSetPasswordWithoutCurrent: Bool { session.unlockMethod == .storedKey }

    func changePassword(current: String, new newPassword: String, confirmation: String) async -> Bool {
        await replacePassword(with: newPassword, confirmation: confirmation) {
            try await self.session.changePassword(current: current, new: newPassword)
        }
    }

    /// The owner proves presence once more (Touch ID or the Mac password) right before the change.
    func setNewPassword(_ newPassword: String, confirmation: String) async -> Bool {
        await replacePassword(with: newPassword, confirmation: confirmation) {
            try await self.keyStore.confirmPresence(reason: "set a new master password for your Clevane vault")
            try await self.session.setNewPassword(newPassword)
        }
    }

    private func replacePassword(with newPassword: String, confirmation: String, _ rewrap: () async throws -> Void) async -> Bool {
        guard newPassword == confirmation else {
            report(.invalidContent(.passwordsDoNotMatch))
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await rewrap()
            if isTouchIDEnabled { setTouchID(enabled: true) }
            showToast("Master password changed.")
            return true
        } catch VaultError.biometryCancelled {
            return false
        } catch {
            report(error)
            return false
        }
    }

    /// Observed, so the Settings picker and the windows follow it at once; saved for the next launch.
    var appearance: Appearance {
        didSet {
            preferences.set(appearance.rawValue, forKey: PreferenceKey.appearance)
            applyAppearance()
        }
    }

    /// The palette is made of AppKit dynamic colors: they follow the app's NSAppearance, which SwiftUI's
    /// preferredColorScheme does not reliably set (Light stayed dark on a Mac in Dark mode).
    func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    // MARK: Backup and restore

    var backupFolder: URL {
        get {
            preferences.url(forKey: PreferenceKey.backupFolder)
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Clevane Backups", isDirectory: true)
        }
        set { preferences.set(newValue, forKey: PreferenceKey.backupFolder) }
    }

    /// Keeps `folder` for future backups, unless it belongs to a vault or a backup.
    func chooseBackupFolder(_ folder: URL) {
        do {
            try BackupService.checkDestination(folder)
            backupFolder = folder
        } catch {
            report(error)
        }
    }

    func createBackup() {
        do {
            try BackupService.checkDestination(backupFolder)
            try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            let backup = try BackupService.createBackup(of: session.file, in: backupFolder)
            showToast("Backup saved as \(backup.lastPathComponent).")
        } catch {
            report(error)
        }
    }

    func recentBackups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == BackupService.fileExtension }
            .sorted { modificationDate($0) > modificationDate($1) }
    }

    /// Opens a backup as a separate vault next to the current one; the current vault is locked, never replaced.
    /// It is locked only once the backup has opened: a mistyped backup password leaves it as it was.
    func restore(_ backupURL: URL, password: String) async -> Bool {
        let destination = uniqueRestoreURL()
        isWorking = true
        defer { isWorking = false }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let restored = try await BackupService.restore(backupURL, to: destination, password: password)
            if session.isOpen { lock() }
            preferences.set(destination, forKey: PreferenceKey.vaultPath)
            didOpen(restored)
            showToast("Backup opened as a separate vault.")
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Switches to another vault file; it opens locked.
    func useVault(at url: URL) {
        if session.isOpen { lock() }
        session = VaultSession(file: VaultFile(url: url))
        preferences.set(url, forKey: PreferenceKey.vaultPath)
        screen = .unlock
    }

    // MARK: Updates

    /// Compares the installed version with the latest published one. A quiet check (at launch) speaks
    /// only when a newer version exists; a check the person asked for always answers.
    public func checkForUpdates(quietly: Bool = false) async {
        guard let current = AppVersion(installedVersion) else { return }
        do {
            switch UpdateResult(current: current, latest: try await releaseSource.latestRelease()) {
            case .available(let release): updateOffer = release
            case .upToDate where !quietly: showToast("Clevane \(current) is up to date.")
            case .nothingPublished where !quietly: showToast("No published version of Clevane yet.")
            default: break
            }
        } catch where !quietly {
            alert = AppAlert(title: "Clevane", message: "Clevane could not reach GitHub to check for updates. Check your connection and try again.")
        } catch {
            return
        }
    }

    // MARK: Messages

    func report(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? "Something unexpected happened. Nothing was changed."
        alert = AppAlert(title: "Clevane", message: message)
    }

    private func report(_ error: VaultError) {
        report(error as Error)
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Private

    private var touchIDVaults: Set<String> {
        get { Set(preferences.stringArray(forKey: PreferenceKey.touchIDVaults) ?? []) }
        set { preferences.set(Array(newValue).sorted(), forKey: PreferenceKey.touchIDVaults) }
    }

    private func forgetTouchID(for vaultID: UUID) {
        try? keyStore.deleteKey(for: vaultID)
        touchIDVaults.remove(vaultID.uuidString)
    }

    private func uniqueRestoreURL() -> URL {
        let folder = session.file.url.deletingLastPathComponent()
        let candidates = (1...999).lazy.map { folder.appendingPathComponent($0 == 1 ? "Restored Vault.clevane" : "Restored Vault \($0).clevane") }
        return candidates.first { !FileManager.default.fileExists(atPath: $0.path) } ?? folder.appendingPathComponent("Restored \(UUID().uuidString).clevane")
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Non-secret preferences only (paths, appearance, which vault IDs use Touch ID).
enum PreferenceKey {
    static let vaultPath = "vaultPath"
    static let appearance = "appearance"
    static let backupFolder = "backupFolder"
    static let touchIDVaults = "touchIDVaults"
    static let guideSeen = "guideSeen"
    static let checkUpdatesAtLaunch = "checkUpdatesAtLaunch"
}
