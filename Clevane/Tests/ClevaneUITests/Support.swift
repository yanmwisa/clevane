import Foundation
import Testing
import VaultCore
@testable import ClevaneUI

/// An app model on a temporary vault, with in-memory preferences and a fake keychain.
/// The folder is deleted when the fixture goes away; nothing is written to ~/Library/Preferences.
@MainActor
final class AppFixture {
    static let password = "sample demo passphrase"

    let folder: URL
    let keyStore = FakeKeyStore()
    let model: AppModel
    private let preferences = MemoryPreferences()

    var vaultURL: URL { folder.appendingPathComponent("Vault.clevane") }

    init(quickUnlockAvailable: Bool = true) throws {
        keyStore.isAvailable = quickUnlockAvailable
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("clevane-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        preferences.set(folder.appendingPathComponent("Backups"), forKey: PreferenceKey.backupFolder)
        model = AppModel(vaultURL: folder.appendingPathComponent("Vault.clevane"), keyStore: keyStore, preferences: preferences)
    }

    /// A fixture whose vault is created and open.
    static func openVault() async throws -> AppFixture {
        let fixture = try AppFixture()
        await fixture.model.createVault(name: "Personal Vault", password: password, confirmation: password, enableTouchID: false)
        #expect(fixture.model.screen == .vault)
        return fixture
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

final class FakeKeyStore: VaultKeyStore, @unchecked Sendable {
    var keys: [UUID: Data] = [:]
    var storeFailure: VaultError?
    var loadFailure: VaultError?
    var presenceFailure: VaultError?
    var isAvailable = true

    func confirmPresence(reason: String) async throws {
        if let presenceFailure { throw presenceFailure }
    }

    func storeKey(_ key: Data, for vaultID: UUID) throws {
        if let storeFailure { throw storeFailure }
        keys[vaultID] = key
    }

    func loadKey(for vaultID: UUID, reason: String) throws -> Data {
        if let loadFailure { throw loadFailure }
        guard let key = keys[vaultID] else { throw VaultError.biometryInvalidated }
        return key
    }

    func deleteKey(for vaultID: UUID) throws {
        keys[vaultID] = nil
    }
}
