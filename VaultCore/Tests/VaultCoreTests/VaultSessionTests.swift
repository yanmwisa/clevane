import Foundation
import Testing
@testable import VaultCore

@MainActor
struct VaultSessionTests {
    @Test func createOpensAnEmptyVaultAndRefusesToOverwrite() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        #expect(session.state == .open)
        #expect(session.content == VaultContent())
        session.lock()
        await #expect(throws: VaultError.vaultExists) {
            _ = try await VaultSession.create(at: folder.file(), password: "other", kdf: Fixture.fastKDF())
        }
    }

    @Test func createRefusesAnEmptyPassword() async throws {
        let folder = try TemporaryFolder()
        await #expect(throws: VaultError.invalidContent(.emptyPassword)) {
            _ = try await VaultSession.create(at: folder.file(), password: "", kdf: Fixture.fastKDF())
        }
    }

    @Test func lockHidesContentAndClosesTheGeneration() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        try session.edit { try $0.addTable(name: "Trading", columns: [Column(name: "Account ID", type: .text)]) }
        let generation = session.generation
        session.lock()
        #expect(session.state == .locked)
        #expect(session.content.tables.isEmpty)
        #expect(!session.isCurrent(generation))
        #expect(throws: VaultError.vaultLocked) { try session.edit { _ in } }
        #expect(throws: VaultError.vaultLocked) { _ = try session.vaultKeyForKeychain() }
    }

    @Test func wrongPasswordIsRefusedAndStaysLocked() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        session.lock()
        await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: "wrong") }
        #expect(session.state == .locked)
        try await session.unlock(password: Fixture.password)
        #expect(session.state == .open)
    }

    /// D5: a validated edit is on disk, so a fresh launch finds it.
    @Test func validatedEditSurvivesARelaunch() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let table = Fixture.tradingTable()
        let tableID = try session.edit { try $0.addTable(name: table.name, columns: table.columns) }
        try session.edit { try $0.addRow(to: tableID, values: [table.columns[1].id: "Sample-Trade-01"]) }
        session.lock()

        let relaunched = VaultSession(file: VaultFile(url: folder.file()))
        try await relaunched.unlock(password: Fixture.password)
        let reopened = try #require(relaunched.content.table(tableID))
        #expect(reopened.rows.first?.values[table.columns[1].id] == "Sample-Trade-01")
    }

    @Test func refusedEditChangesNothing() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let before = try Data(contentsOf: folder.file())
        #expect(throws: VaultError.invalidContent(.noColumns)) { try session.edit { try $0.addTable(name: "Empty", columns: []) } }
        #expect(session.content.tables.isEmpty)
        #expect(try Data(contentsOf: folder.file()) == before)
    }

    /// D4: a second window cannot open a vault that is already open.
    @Test func secondSessionOnTheSameVaultIsRefused() async throws {
        let folder = try TemporaryFolder()
        let first = try await makeOpenVault(in: folder)
        let second = VaultSession(file: VaultFile(url: folder.file()))
        await #expect(throws: VaultError.vaultAlreadyOpen) { try await second.unlock(password: Fixture.password) }
        first.lock()
        try await second.unlock(password: Fixture.password)
        #expect(second.isOpen)
    }

    /// A4: an unlock still deriving when the vault is locked is discarded.
    @Test func lockDuringUnlockDiscardsTheResult() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        session.lock()
        let pending = Task { try await session.unlock(password: Fixture.password) }
        while session.state != .unlocking { await Task.yield() }
        // No suspension between this check and the lock: the derivation cannot complete in between.
        session.lock()
        await #expect(throws: VaultError.vaultLocked) { try await pending.value }
        #expect(session.state == .locked)
        try await session.unlock(password: Fixture.password)
        #expect(session.isOpen)
    }

    /// D8: old password refused afterwards, new one accepted, content intact.
    @Test func changePassword() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let table = Fixture.tradingTable()
        try session.edit { try $0.addTable(name: table.name, columns: table.columns) }
        await #expect(throws: VaultError.wrongPassword) { try await session.changePassword(current: "wrong", new: "next") }
        try await session.changePassword(current: Fixture.password, new: "new sample passphrase")
        let content = session.content
        session.lock()
        await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: Fixture.password) }
        try await session.unlock(password: "new sample passphrase")
        #expect(session.content == content)
    }

    /// A lost password can be replaced only from a session opened with the stored key; afterwards the old
    /// password is refused, the new one and the same stored key still open the vault.
    @Test func storedKeySessionSetsANewPassword() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let key = try session.vaultKeyForKeychain()
        #expect(session.unlockMethod == .password)
        await #expect(throws: VaultError.quickUnlockRequired) { try await session.setNewPassword("new sample passphrase") }

        session.lock()
        #expect(session.unlockMethod == nil)
        try session.unlock(vaultKey: key)
        #expect(session.unlockMethod == .storedKey)
        try await session.setNewPassword("new sample passphrase")

        session.lock()
        await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: Fixture.password) }
        try await session.unlock(password: "new sample passphrase")
        session.lock()
        try session.unlock(vaultKey: key)
        #expect(session.isOpen)
    }

    @Test func touchIDKeyOpensTheVaultAndAStaleKeyFallsBack() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let store = FakeKeyStore()
        let vaultID = try session.vaultID()
        try store.storeKey(try session.vaultKeyForKeychain(), for: vaultID)
        session.lock()

        try session.unlock(vaultKey: try store.loadKey(for: vaultID, reason: "Unlock"))
        #expect(session.isOpen)
        session.lock()

        #expect(throws: VaultError.biometryInvalidated) { try session.unlock(vaultKey: Data(repeating: 1, count: 32)) }
        #expect(session.state == .locked)
        store.failure = .biometryInvalidated
        #expect(throws: VaultError.biometryInvalidated) { _ = try store.loadKey(for: vaultID, reason: "Unlock") }
        try await session.unlock(password: Fixture.password)
        #expect(session.isOpen)
    }

    @Test func damagedFileIsReportedNotOpened() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        session.lock()
        var data = try Data(contentsOf: folder.file())
        data[data.endIndex - 5] ^= 0x10
        try data.write(to: folder.file())
        await #expect(throws: VaultError.corruptedFile) { try await session.unlock(password: Fixture.password) }
        #expect(session.state == .locked)
    }

    /// The real D7 cost (256 MiB, 3 passes): create, lock, reopen.
    @Test func moderateParametersRoundTrip() async throws {
        let folder = try TemporaryFolder()
        let session = try await VaultSession.create(at: folder.file(), password: Fixture.password)
        session.lock()
        try await session.unlock(password: Fixture.password)
        #expect(session.isOpen)
    }
}
