import CryptoKit
import Foundation
import LocalAuthentication
import Security
import Testing
@testable import VaultCore

@MainActor
struct ClipboardTests {
    @Test func copyIsConcealedAndClearedAfterTheDelay() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let pasteboard = FakePasteboard()
        let clipboard = ClipboardService(pasteboard: pasteboard, session: session, clearDelayOverride: .milliseconds(50))
        try clipboard.copy("Sample-Trade-01", startedIn: session.generation)
        #expect(pasteboard.value == "Sample-Trade-01")
        #expect(pasteboard.isConcealed)
        #expect(await eventually { pasteboard.value == nil })
    }

    @Test func somethingCopiedLaterIsNotErased() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let pasteboard = FakePasteboard()
        let clipboard = ClipboardService(pasteboard: pasteboard, session: session, clearDelayOverride: .milliseconds(50))
        try clipboard.copy("Sample-Trade-01", startedIn: session.generation)
        pasteboard.simulateOtherCopy("a grocery list")
        try await Task.sleep(for: .milliseconds(200))
        #expect(pasteboard.value == "a grocery list")
    }

    /// The passphrase proposed at creation is copied while no vault is open, and still cleared.
    @Test func passphraseCopiedBeforeTheVaultExistsIsCleared() async throws {
        let folder = try TemporaryFolder()
        let session = VaultSession(file: VaultFile(url: folder.url.appendingPathComponent("Not yet.clevane")))
        let pasteboard = FakePasteboard()
        let clipboard = ClipboardService(pasteboard: pasteboard, session: session, clearDelayOverride: .milliseconds(50))
        clipboard.copyBeforeVaultExists("sample-demo-words-only-for-tests", clearingAfter: .seconds(120))
        #expect(pasteboard.value == "sample-demo-words-only-for-tests")
        #expect(pasteboard.isConcealed)
        #expect(await eventually { pasteboard.value == nil })
    }

    /// A4: a copy started before a lock is refused.
    @Test func copyFromAClosedGenerationIsRefused() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let pasteboard = FakePasteboard()
        let clipboard = ClipboardService(pasteboard: pasteboard, session: session)
        let generation = session.generation
        session.lock()
        #expect(throws: VaultError.vaultLocked) { try clipboard.copy("Sample-Trade-01", startedIn: generation) }
        #expect(pasteboard.value == nil)
    }
}

@MainActor
struct AutoLockTests {
    @Test func inactivityRule() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(!AutoLockMonitor.isInactive(since: start, now: start.addingTimeInterval(299), delay: .fiveMinutes))
        #expect(AutoLockMonitor.isInactive(since: start, now: start.addingTimeInterval(300), delay: .fiveMinutes))
        #expect(AutoLockMonitor.isInactive(since: start, now: start.addingTimeInterval(60), delay: .oneMinute))
    }

    @Test func inactivityLocksAndClearsTheCopiedSecret() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let pasteboard = FakePasteboard()
        let clipboard = ClipboardService(pasteboard: pasteboard, session: session)
        let start = Date()
        let monitor = AutoLockMonitor(session: session, clipboard: clipboard, now: start)
        try clipboard.copy("Sample-Trade-01", startedIn: session.generation)
        #expect(!monitor.checkInactivity(now: start.addingTimeInterval(120)))
        monitor.recordActivity(at: start.addingTimeInterval(120))
        #expect(!monitor.checkInactivity(now: start.addingTimeInterval(400)))
        #expect(monitor.checkInactivity(now: start.addingTimeInterval(421)))
        #expect(session.state == .locked)
        #expect(monitor.lastReason == .inactivity)
        #expect(pasteboard.value == nil)
    }

    @Test func systemEventsLockImmediately() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let monitor = AutoLockMonitor(session: session, clipboard: nil)
        monitor.lock(because: .systemSleep)
        #expect(session.state == .locked)
        #expect(monitor.lastReason == .systemSleep)
    }
}

@MainActor
struct BackupTests {
    @Test func backupNamesAreDatedAndNeverReplaced() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let backups = folder.url.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_791_456_000)
        let first = try BackupService.createBackup(of: session.file, in: backups, on: date)
        let second = try BackupService.createBackup(of: session.file, in: backups, on: date)
        #expect(first.lastPathComponent == BackupService.backupFileName(on: date))
        #expect(second.lastPathComponent == BackupService.backupFileName(on: date, attempt: 2))
    }

    /// Success criterion: a backup restores elsewhere with the password alone.
    @Test func restoreElsewhereWithThePasswordAlone() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let table = Fixture.tradingTable()
        try session.edit { try $0.addTable(name: table.name, columns: table.columns) }
        let content = session.content
        let backup = try BackupService.createBackup(of: session.file, in: folder.url)

        let other = try TemporaryFolder()
        let restored = try await BackupService.restore(backup, to: other.file("Restored.clevane"), password: Fixture.password)
        #expect(restored.content == content)
    }

    @Test func backupsStayOutOfVaultFilesAndOtherBackups() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let vaultFiles = folder.file("Demo.clevane.files")
        try FileManager.default.createDirectory(at: vaultFiles, withIntermediateDirectories: true)

        #expect(throws: VaultError.backupFolderNotAllowed) { try BackupService.createBackup(of: session.file, in: vaultFiles) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: vaultFiles.path).isEmpty)
        #expect(throws: VaultError.backupFolderNotAllowed) { try BackupService.checkDestination(vaultFiles.appendingPathComponent("Inside")) }
        #expect(throws: VaultError.backupFolderNotAllowed) { try BackupService.checkDestination(folder.file("clevane-2026-10-08.cvbackup")) }
        try BackupService.checkDestination(folder.file("Clevane Backups"))
    }

    @Test func wrongPasswordLeavesNoRestoredFile() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let backup = try BackupService.createBackup(of: session.file, in: folder.url)
        let other = try TemporaryFolder()
        let target = other.file("Restored.clevane")
        await #expect(throws: VaultError.wrongBackupPassword) { _ = try await BackupService.restore(backup, to: target, password: "wrong") }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
}

struct QuickUnlockStoreTests {
    /// Prompt outcomes map to stable errors; anything else (enclave key gone, data altered) resets to the password.
    @Test func failuresMapToStableErrors() {
        #expect(SecureEnclaveKeyStore.error(for: LAError(.userCancel)) == .biometryCancelled)
        #expect(SecureEnclaveKeyStore.error(for: LAError(.systemCancel)) == .biometryCancelled)
        #expect(SecureEnclaveKeyStore.error(for: LAError(.biometryNotAvailable)) == .biometryUnavailable)
        #expect(SecureEnclaveKeyStore.error(for: LAError(.passcodeNotSet)) == .biometryUnavailable)
        #expect(SecureEnclaveKeyStore.error(for: CryptoKitError.authenticationFailure) == .biometryInvalidated)
    }

    @Test func missingOrAlteredEntryResetsQuickUnlock() throws {
        let folder = try TemporaryFolder()
        let store = SecureEnclaveKeyStore(folder: folder.url)
        let vaultID = UUID()
        #expect(throws: VaultError.biometryInvalidated) { try store.loadKey(for: vaultID, reason: "test") }
        try Data("not a sealed key".utf8).write(to: store.fileURL(for: vaultID))
        #expect(throws: VaultError.biometryInvalidated) { try store.loadKey(for: vaultID, reason: "test") }
        try store.deleteKey(for: vaultID)
        try store.deleteKey(for: vaultID)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: vaultID).path))
    }

    /// Sealing needs the Secure Enclave but no prompt: the entry is private to the user and holds no clear key.
    @Test(.enabled(if: SecureEnclave.isAvailable, "Needs a Mac with a Secure Enclave"))
    func sealedEntryHoldsNoClearKey() throws {
        let folder = try TemporaryFolder()
        let store = SecureEnclaveKeyStore(folder: folder.url)
        let vaultID = UUID()
        let fictionalKey = Data(Fixture.sentinel.utf8)
        try store.storeKey(fictionalKey, for: vaultID)
        let url = store.fileURL(for: vaultID)
        let written = try Data(contentsOf: url)
        #expect(written.range(of: fictionalKey) == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(SecureEnclaveKeyStore.info(for: vaultID) != SecureEnclaveKeyStore.info(for: UUID()))
    }
}
