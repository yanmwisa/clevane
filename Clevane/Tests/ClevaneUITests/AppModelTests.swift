import Foundation
import Testing
import VaultCore
@testable import ClevaneUI

/// App-level flows on a temporary vault, with fictional values, isolated preferences and a fake keychain.
@MainActor
struct AppModelTests {
    private static let password = AppFixture.password

    private func openVault() async throws -> AppFixture {
        try await AppFixture.openVault()
    }

    @Test func launchWithoutVaultShowsWelcome() throws {
        let fixture = try AppFixture()
        #expect(fixture.model.screen == .welcome)
    }

    @Test func mismatchedConfirmationCreatesNothing() async throws {
        let fixture = try AppFixture()
        await fixture.model.createVault(name: "Personal Vault", password: Self.password, confirmation: "other", enableTouchID: false)
        #expect(fixture.model.alert?.message == ContentProblem.passwordsDoNotMatch.message)
        #expect(!fixture.model.session.file.exists)
    }

    @Test func createLockUnlockCycle() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(model.content.name == "Personal Vault")
        model.lock()
        #expect(model.screen == .unlock)
        #expect(!model.session.isOpen)
        #expect(await model.unlock(password: "wrong") == false)
        #expect(model.alert?.message == VaultError.wrongPassword.errorDescription)
        #expect(model.screen == .unlock)
        #expect(await model.unlock(password: Self.password))
        #expect(model.screen == .vault)
    }

    @Test func tablesAndRowsThroughTheModel() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        let account = Column(name: "Account ID", type: .text)
        let secret = Column(name: "Password", type: .secret)
        #expect(model.createTable(name: "Trading", columns: [account, secret]))
        #expect(model.currentTable?.name == "Trading")
        #expect(!model.createTable(name: "trading", columns: [account]))
        #expect(model.alert?.message == ContentProblem.duplicateTableName.message)

        let tableID = try #require(model.currentTable?.id)
        #expect(model.saveRow([account.id: "ACC-1042", secret.id: "Sample-Trade-01"], attachments: [:], editing: nil, in: tableID))
        let rowID = try #require(model.selectedRow?.id)
        #expect(model.saveRow([account.id: "ACC-1042", secret.id: "Sample-Trade-02"], attachments: [:], editing: rowID, in: tableID))
        #expect(model.selectedRow?.values[secret.id] == "Sample-Trade-02")
        model.deleteRow(rowID, in: tableID)
        #expect(model.currentTable?.rows.isEmpty == true)
        model.deleteTable(tableID)
        #expect(model.content.tables.isEmpty)
        #expect(model.section == .start)
    }

    @Test func revealResetsWhenAnotherRowIsSelected() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        let secret = Column(name: "Password", type: .secret)
        _ = model.createTable(name: "Bank Accounts", columns: [Column(name: "Username", type: .text), secret])
        let tableID = try #require(model.currentTable?.id)
        _ = model.saveRow([secret.id: "Sample-Bank-01"], attachments: [:], editing: nil, in: tableID)
        _ = model.saveRow([secret.id: "Sample-Bank-02"], attachments: [:], editing: nil, in: tableID)
        let rows = try #require(model.currentTable?.rows)
        model.select(rows[0].id)
        model.toggleReveal(secret.id)
        #expect(model.revealedColumns.contains(secret.id))
        model.select(rows[1].id)
        #expect(model.revealedColumns.isEmpty)
    }

    /// Ad hoc builds cannot use the keychain: turning Touch ID on reports it and stays off.
    @Test func touchIDUnavailableStaysOff() async throws {
        let fixture = try await openVault()
        fixture.keyStore.storeFailure = .biometryUnavailable
        fixture.model.setTouchID(enabled: true)
        #expect(!fixture.model.isTouchIDEnabled)
        #expect(fixture.model.alert?.message == VaultError.biometryUnavailable.errorDescription)
    }

    @Test func touchIDUnlockAndInvalidatedFallback() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        model.setTouchID(enabled: true)
        #expect(model.isTouchIDEnabled)
        model.lock()
        await model.quickUnlock()
        #expect(model.screen == .vault)

        model.lock()
        fixture.keyStore.loadFailure = .biometryInvalidated
        await model.quickUnlock()
        #expect(model.screen == .unlock)
        #expect(!model.isTouchIDEnabled)
        #expect(await model.unlock(password: Self.password))
    }

    /// Touch ID opened the vault: a new master password needs no current one, but Touch ID once more.
    @Test func touchIDUnlockSetsANewPasswordWithoutTheCurrentOne() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(!model.canSetPasswordWithoutCurrent)
        model.setTouchID(enabled: true)
        model.lock()
        await model.quickUnlock()
        #expect(model.canSetPasswordWithoutCurrent)

        fixture.keyStore.presenceFailure = .biometryCancelled
        #expect(await model.setNewPassword("new sample passphrase", confirmation: "new sample passphrase") == false)
        #expect(model.alert == nil)

        fixture.keyStore.presenceFailure = nil
        #expect(await model.setNewPassword("new sample passphrase", confirmation: "new sample passphrase"))
        model.lock()
        #expect(await model.unlock(password: Self.password) == false)
        #expect(await model.unlock(password: "new sample passphrase"))
        #expect(!model.canSetPasswordWithoutCurrent)
        model.lock()
        await model.quickUnlock()
        #expect(model.screen == .vault)
    }

    /// Fast path: the system prompt first, then the backup passphrase; Start creates the vault with quick unlock on.
    @Test func quickCreateConfirmsPresenceThenEnablesQuickUnlock() async throws {
        let fixture = try AppFixture()
        let model = fixture.model
        await model.startQuickCreate()
        #expect(model.screen == .create)
        #expect(model.createsWithQuickUnlock)

        let backup = Passphrase.generate()
        await model.createVault(name: "Personal Vault", password: backup, confirmation: backup, enableTouchID: true)
        #expect(model.screen == .vault)
        #expect(model.isTouchIDEnabled)
        #expect(!model.createsWithQuickUnlock)
        model.lock()
        #expect(await model.unlock(password: backup))
    }

    /// Dismissing the prompt leaves the user on Welcome without an alert.
    @Test func quickCreateCancelledStaysOnWelcome() async throws {
        let fixture = try AppFixture()
        fixture.keyStore.presenceFailure = .biometryCancelled
        await fixture.model.startQuickCreate()
        #expect(fixture.model.screen == .welcome)
        #expect(fixture.model.alert == nil)
    }

    /// An ad hoc build has no keychain entitlement: the fast path is not offered and cannot start.
    @Test func quickCreateUnavailableDoesNothing() async throws {
        let fixture = try AppFixture(quickUnlockAvailable: false)
        #expect(!fixture.model.isQuickUnlockAvailable)
        await fixture.model.startQuickCreate()
        #expect(fixture.model.screen == .welcome)
    }

    /// An empty vault opens on Get started; the guide waits for the first table, then opens once.
    @Test func guideOpensOnceThenOnDemand() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(model.section == .start)
        #expect(model.guideStop == nil)
        #expect(model.createTable(from: .logins))
        #expect(model.currentTable?.name == "Logins")
        #expect(model.guideStop == .tables)
        model.closeGuide()
        #expect(model.createTable(from: .logins))
        #expect(model.currentTable?.name == "Logins 2")
        #expect(model.guideStop == nil)
        model.lock()
        #expect(await model.unlock(password: Self.password))
        #expect(model.guideStop == nil)
        model.showGuide()
        #expect(model.guideStop == .tables)
    }

    /// Stops whose place is not on screen are skipped; Next past the last stop closes the guide.
    @Test func guideFollowsWhatIsOnScreen() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(model.guideStops == [.tables, .newTable, .lock, .backup, .settings, .guide])

        let account = Column(name: "Account ID", type: .text)
        _ = model.createTable(name: "Trading", columns: [account])
        let tableID = try #require(model.currentTable?.id)
        _ = model.saveRow([account.id: "ACC-1042"], attachments: [:], editing: nil, in: tableID)
        #expect(model.guideStops == GuideStop.allCases)

        model.showGuide()
        for _ in GuideStop.allCases { model.moveGuide(by: 1) }
        #expect(model.guideStop == nil)
    }

    /// Light must apply on a Mac set to Dark: the choice is observed and kept for the next launch.
    @Test func appearanceIsKeptForTheNextLaunch() throws {
        let preferences = MemoryPreferences()
        let model = AppModel(vaultURL: URL(fileURLWithPath: "/nonexistent/Vault.clevane"), keyStore: FakeKeyStore(), preferences: preferences)
        #expect(model.appearance == .system)
        model.appearance = .light
        let relaunched = AppModel(vaultURL: URL(fileURLWithPath: "/nonexistent/Vault.clevane"), keyStore: FakeKeyStore(), preferences: preferences)
        #expect(relaunched.appearance == .light)
        #expect(Appearance.light.nsAppearance?.name == .aqua)
        #expect(Appearance.dark.nsAppearance?.name == .darkAqua)
        #expect(Appearance.system.nsAppearance == nil)
    }

    /// A hit in another table opens that table with the row selected, and clears the search.
    @Test func searchResultOpensItsRow() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(model.createTable(from: .wifi))
        let wifi = try #require(model.currentTable)
        let network = try #require(wifi.columns.first)
        #expect(model.saveRow([network.id: "Cabin network"], attachments: [:], editing: nil, in: wifi.id))
        let rowID = try #require(model.currentTable?.rows.first?.id)
        #expect(model.createTable(from: .logins))
        model.searchText = "cabin"
        let hits = model.content.search(model.searchText, excluding: model.currentTable?.id)
        let hit = try #require(hits.first)
        model.openSearchResult(hit)
        #expect(model.section == .table(wifi.id))
        #expect(model.selectedRow?.id == rowID)
        #expect(model.searchText.isEmpty)
    }

    /// A fictional Chrome export becomes an Imported Logins table, then the plain text file is offered to the Trash.
    @Test func browserExportBecomesATable() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        let export = fixture.folder.appendingPathComponent("Chrome Passwords.csv")
        try "name,url,username,password,note\nexample.com,https://example.com,alex.sample,Sample-Pass-01,\n".write(to: export, atomically: true, encoding: .utf8)
        model.importBrowserExport(from: export)
        #expect(model.currentTable?.name == "Imported Logins")
        #expect(model.currentTable?.rows.count == 1)
        guard case .trashImportedFile(let offered) = model.confirmation else {
            Issue.record("The export was not offered to the Trash")
            return
        }
        #expect(offered == export)

        let unrelated = fixture.folder.appendingPathComponent("Budget.csv")
        try "date,amount\n2026-10-08,12\n".write(to: unrelated, atomically: true, encoding: .utf8)
        model.confirmation = nil
        model.importBrowserExport(from: unrelated)
        #expect(model.alert?.message == VaultError.unrecognizedImport.errorDescription)
        #expect(model.content.tables.count == 1)
    }

    /// A file goes in encrypted, comes out only to a chosen place, and leaves disk with its row.
    @Test func fileColumnLifecycle() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(model.createTable(from: .documents))
        let table = try #require(model.currentTable)
        let fileColumn = try #require(table.columns.first { $0.type == .file })
        let original = fixture.folder.appendingPathComponent("scan.txt")
        try Data("FICTIONAL SCAN".utf8).write(to: original)

        let attachment = try #require(model.attachFile(at: original))
        #expect(model.saveRow([table.columns[0].id: "Passport"], attachments: [fileColumn.id: attachment], editing: nil, in: table.id))
        let exported = fixture.folder.appendingPathComponent("exported.txt")
        model.export(attachment, to: exported)
        #expect(try Data(contentsOf: exported) == Data("FICTIONAL SCAN".utf8))

        let stored = fixture.folder.appendingPathComponent("Vault.clevane.files/\(attachment.id.uuidString).blob")
        #expect(FileManager.default.fileExists(atPath: stored.path))
        let rowID = try #require(model.selectedRow?.id)
        model.deleteRow(rowID, in: table.id)
        #expect(!FileManager.default.fileExists(atPath: stored.path))

        let huge = fixture.folder.appendingPathComponent("huge.bin")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(Attachment.maximumByteCount + 1))
        try handle.close()
        #expect(model.attachFile(at: huge) == nil)
        #expect(model.alert?.message == VaultError.fileTooLarge.errorDescription)
    }

    /// Deleting a table takes its rows and its files with it; the confirmation counts both.
    @Test func deletingATableRemovesItsFiles() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(model.createTable(from: .documents))
        let table = try #require(model.currentTable)
        let fileColumn = try #require(table.columns.first { $0.type == .file })
        let original = fixture.folder.appendingPathComponent("scan.txt")
        try Data("FICTIONAL SCAN".utf8).write(to: original)
        let attachment = try #require(model.attachFile(at: original))
        #expect(model.saveRow([table.columns[0].id: "Passport"], attachments: [fileColumn.id: attachment], editing: nil, in: table.id))
        #expect(model.currentTable?.attachmentCount == 1)

        let stored = fixture.folder.appendingPathComponent("Vault.clevane.files/\(attachment.id.uuidString).blob")
        model.deleteTable(table.id)
        #expect(model.content.tables.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
        #expect(model.section == .start)
    }

    @Test func settingsAreSavedInTheVault() async throws {
        let fixture = try await openVault()
        fixture.model.setAutoLockDelay(.fifteenMinutes)
        fixture.model.setClipboardDelay(.sixtySeconds)
        fixture.model.lock()
        _ = await fixture.model.unlock(password: Self.password)
        #expect(fixture.model.content.settings == VaultSettings(autoLockDelay: .fifteenMinutes, clipboardClearDelay: .sixtySeconds))
    }

    @Test func aVaultFilesFolderIsRefusedForBackups() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        let kept = model.backupFolder
        let vaultFiles = model.session.file.url.appendingPathExtension("files")

        model.chooseBackupFolder(vaultFiles)
        #expect(model.backupFolder == kept)
        #expect(model.alert?.message == VaultError.backupFolderNotAllowed.errorDescription)
    }

    @Test func backupThenRestoreOpensASeparateVault() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        _ = model.createTable(name: "Trading", columns: [Column(name: "Account ID", type: .text)])
        model.createBackup()
        let backup = try #require(model.recentBackups().first)
        let original = model.session.file.url

        #expect(await model.restore(backup, password: Self.password))
        #expect(model.screen == .vault)
        #expect(model.session.file.url.lastPathComponent == "Restored Vault.clevane")
        #expect(model.content.tables.map(\.name) == ["Trading"])
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    /// A mistyped backup password used to lock the open vault first; it now stays open, with a backup message.
    @Test func wrongBackupPasswordKeepsTheVaultOpen() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        model.createBackup()
        let backup = try #require(model.recentBackups().first)
        let original = model.session.file.url

        #expect(await model.restore(backup, password: "wrong") == false)
        #expect(model.screen == .vault)
        #expect(model.session.isOpen)
        #expect(model.session.file.url == original)
        #expect(model.alert?.message == VaultError.wrongBackupPassword.errorDescription)
    }

    @Test func unlockScreenNamesTheVaultFile() async throws {
        let fixture = try await openVault()
        #expect(fixture.model.vaultFileName == "Vault")
    }

    /// The passphrase saved to a file at creation is kept in a Recovery table; the file is offered to the Trash.
    @Test func savedPassphraseIsKeptInTheVault() async throws {
        let fixture = try AppFixture()
        let model = fixture.model
        let file = fixture.folder.appendingPathComponent("Clevane passphrase.txt")
        model.savePassphrase(Self.password, to: file)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try String(contentsOf: file, encoding: .utf8).contains(Self.password))

        await model.createVault(name: "Personal Vault", password: Self.password, confirmation: Self.password, enableTouchID: false)
        let recovery = try #require(model.currentTable)
        #expect(recovery.name == "Recovery")
        let secret = try #require(recovery.columns.first { $0.type == .secret })
        #expect(recovery.rows.first?.values[secret.id] == Self.password)
        guard case .trashPassphraseFile(let offered, true)? = model.confirmation else {
            Issue.record("No trash offer for the passphrase file: \(String(describing: model.confirmation))")
            return
        }
        #expect(offered == file)
    }

    @Test func anEarlierSuggestionIsOnlyOfferedToTheTrash() async throws {
        let fixture = try AppFixture()
        let model = fixture.model
        let file = fixture.folder.appendingPathComponent("Clevane passphrase.txt")
        model.savePassphrase("earlier suggestion words", to: file)

        await model.createVault(name: "Personal Vault", password: Self.password, confirmation: Self.password, enableTouchID: false)
        #expect(model.content.tables.isEmpty)
        guard case .trashPassphraseFile(_, false)? = model.confirmation else {
            Issue.record("Expected a trash offer without Recovery: \(String(describing: model.confirmation))")
            return
        }
    }

    @Test func changePasswordRequiresMatchingConfirmation() async throws {
        let fixture = try await openVault()
        let model = fixture.model
        #expect(await model.changePassword(current: Self.password, new: "new sample passphrase", confirmation: "typo") == false)
        #expect(await model.changePassword(current: Self.password, new: "new sample passphrase", confirmation: "new sample passphrase"))
        model.lock()
        #expect(await model.unlock(password: "new sample passphrase"))
    }
}
