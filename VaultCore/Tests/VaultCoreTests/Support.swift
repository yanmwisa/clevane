import Foundation
@testable import VaultCore

/// Fictional values only. The sentinel is searched for in every file the tests write (vigil test).
enum Fixture {
    static let password = "correct horse battery staple"
    static let sentinel = "SENTINEL-clevane-4f1c9e"

    /// Smallest Argon2id cost libsodium accepts, so the suite derives keys quickly.
    /// One test (`moderateParametersRoundTrip`) uses the real D7 values.
    static func fastKDF() -> KDFParameters {
        KDFParameters(opsLimit: 1, memLimit: 8192, salt: KeyService.randomBytes(KDFParameters.saltLength))
    }

    static func tradingTable() -> VaultTable {
        let account = Column(name: "Account ID", type: .text)
        let password = Column(name: "Password", type: .secret)
        let note = Column(name: "Note", type: .note)
        let rows = [
            Row(values: [account.id: "ACC-1042", password.id: "Sample-Trade-01", note.id: "Sample note"]),
            Row(values: [account.id: "ACC-2087", password.id: "Sample-Trade-02"]),
        ]
        return VaultTable(name: "Trading", columns: [account, password, note], rows: rows)
    }
}

/// A fresh folder per test, removed at the end.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("clevane-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String = "Personal Vault.clevane") -> URL {
        url.appendingPathComponent(name)
    }

    /// Every byte written under this folder, file by file.
    func allFileContents() throws -> [(URL, Data)] {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        return try (enumerator?.allObjects as? [URL] ?? []).compactMap { fileURL in
            let isFile = try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
            return isFile ? (fileURL, try Data(contentsOf: fileURL)) : nil
        }
    }

    deinit {
        let fileManager = FileManager.default
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? fileManager.removeItem(at: url)
    }
}

@MainActor
final class FakePasteboard: Pasteboard {
    private(set) var changeCount = 0
    private(set) var value: String?
    private(set) var isConcealed = false

    func writeConcealed(_ value: String) -> Int {
        self.value = value
        isConcealed = true
        changeCount += 1
        return changeCount
    }

    /// Something else copied text: the pasteboard is no longer Clevane's.
    func simulateOtherCopy(_ value: String) {
        self.value = value
        isConcealed = false
        changeCount += 1
    }

    func clear() {
        value = nil
        isConcealed = false
        changeCount += 1
    }
}

final class FakeKeyStore: VaultKeyStore, @unchecked Sendable {
    var storedKeys: [UUID: Data] = [:]
    var failure: VaultError?
    var isAvailable = true

    func confirmPresence(reason: String) async throws {
        if let failure { throw failure }
    }

    func storeKey(_ key: Data, for vaultID: UUID) throws {
        storedKeys[vaultID] = key
    }

    func loadKey(for vaultID: UUID, reason: String) throws -> Data {
        if let failure { throw failure }
        guard let key = storedKeys[vaultID] else { throw VaultError.biometryInvalidated }
        return key
    }

    func deleteKey(for vaultID: UUID) throws {
        storedKeys[vaultID] = nil
    }
}

@MainActor
func makeOpenVault(in folder: TemporaryFolder, name: String = "Personal Vault.clevane") async throws -> VaultSession {
    try await VaultSession.create(at: folder.file(name), password: Fixture.password, kdf: Fixture.fastKDF())
}

/// Waits for a condition driven by a timer (clipboard clearing) without a fixed sleep that fails under load.
@MainActor
func eventually(within limit: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: limit)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
