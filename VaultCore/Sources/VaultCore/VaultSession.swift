import CryptoKit
import Foundation
import Observation

public enum SessionState: Equatable, Sendable {
    case locked, unlocking, open
}

/// How the open session was unlocked. A stored key (Touch ID or the Mac password) already proved the owner,
/// so it may set a new master password without the current one.
public enum UnlockMethod: Equatable, Sendable {
    case password, storedKey
}

/// The only authority on access to the vault.
///
/// Each lock increments `generation`. Work started under one generation (a key derivation, a copy)
/// is rejected if the generation changed meanwhile (A4): nothing from a closed session can show or copy a secret.
@MainActor
@Observable
public final class VaultSession {
    public let file: VaultFile
    public private(set) var state: SessionState = .locked
    public private(set) var generation = 0
    /// Empty while locked. The decrypted content exists only in memory, only while open.
    public private(set) var content = VaultContent()
    /// nil while locked.
    public private(set) var unlockMethod: UnlockMethod?

    @ObservationIgnored private var vaultKey: SymmetricKey?
    @ObservationIgnored private var header: VaultHeader?
    @ObservationIgnored private var fileLock: VaultLock?

    public init(file: VaultFile) {
        self.file = file
    }

    public var isOpen: Bool { state == .open }

    /// Creates a new, empty vault at `url` and opens it. Never overwrites an existing file.
    public static func create(at url: URL, password: String, kdf: KDFParameters = .moderate()) async throws -> VaultSession {
        guard !password.isEmpty else { throw VaultError.invalidContent(.emptyPassword) }
        let session = VaultSession(file: VaultFile(url: url))
        guard !session.file.exists else { throw VaultError.vaultExists }
        let lock = try session.file.acquireLock()
        let keyEncryptionKey = try await deriveOffMain(password: password, parameters: kdf)
        let vaultKey = KeyService.newVaultKey()
        let header = VaultHeader(vaultID: UUID(), kdf: kdf, wrappedKey: try KeyService.wrap(vaultKey: vaultKey, with: keyEncryptionKey))
        try session.file.write(VaultFile.encode(header: header, content: VaultContent(), key: vaultKey))
        session.open(content: VaultContent(), key: vaultKey, header: header, lock: lock, by: .password)
        return session
    }

    /// Identifier stored in the clear header, used to find the Touch ID item before unlocking.
    public func vaultID() throws -> UUID {
        try header?.vaultID ?? file.read().header.vaultID
    }

    public func unlock(password: String) async throws {
        guard state == .locked else { return }
        let (lock, envelope) = try lockAndRead()
        let startGeneration = generation
        state = .unlocking
        do {
            let keyEncryptionKey = try await Self.deriveOffMain(password: password, parameters: envelope.header.kdf)
            guard generation == startGeneration else { throw VaultError.vaultLocked }
            let key = try KeyService.unwrap(envelope.header.wrappedKey, with: keyEncryptionKey)
            open(content: try VaultFile.openPayload(of: envelope, with: key), key: key, header: envelope.header, lock: lock, by: .password)
        } catch {
            lock.release()
            if state == .unlocking { state = .locked }
            throw error
        }
    }

    /// Touch ID path: the vault key comes from the keychain. A key that no longer opens the vault
    /// means the stored item is stale; the caller falls back to the password.
    public func unlock(vaultKey keyData: Data) throws {
        guard state == .locked else { return }
        let (lock, envelope) = try lockAndRead()
        do {
            let key = SymmetricKey(data: keyData)
            guard let content = try? VaultFile.openPayload(of: envelope, with: key) else { throw VaultError.biometryInvalidated }
            open(content: content, key: key, header: envelope.header, lock: lock, by: .storedKey)
        } catch {
            lock.release()
            throw error
        }
    }

    /// Hides content, forgets the key, releases the file lock and closes the generation.
    /// Edits are already on disk: each one is written when it is validated.
    public func lock() {
        generation += 1
        content = VaultContent()
        vaultKey = nil
        unlockMethod = nil
        fileLock?.release()
        fileLock = nil
        state = .locked
    }

    /// True only for work started in the current, still open session.
    public func isCurrent(_ generation: Int) -> Bool {
        state == .open && generation == self.generation
    }

    /// Applies a validated edit, writes the vault atomically, then publishes it. If the write fails,
    /// the in-memory content stays as it was, so the screen never shows something that is not saved.
    @discardableResult
    public func edit<Result>(_ change: (inout VaultContent) throws -> Result) throws -> Result {
        guard state == .open, let vaultKey, let header else { throw VaultError.vaultLocked }
        var updated = content
        let result = try change(&updated)
        try file.write(VaultFile.encode(header: header, content: updated, key: vaultKey))
        content = updated
        return result
    }

    // MARK: Files

    /// Encrypts a file for a File column and stores it next to the vault. The row refers to it only once it is
    /// saved; until then `removeUnusedAttachments` may delete it (a cancelled sheet leaves nothing behind).
    public func sealAttachment(_ data: Data, name: String, contentType: String) throws -> Attachment {
        guard state == .open, let vaultKey, let header else { throw VaultError.vaultLocked }
        guard data.count <= Attachment.maximumByteCount else { throw VaultError.fileTooLarge }
        let attachment = Attachment(name: name, byteCount: data.count, contentType: contentType)
        try AttachmentStore.seal(data, as: attachment, vaultID: header.vaultID, key: vaultKey, vaultURL: file.url)
        return attachment
    }

    /// Decrypts a stored file into memory. It is never written in clear unless the person exports it.
    public func openAttachment(_ attachment: Attachment) throws -> Data {
        guard state == .open, let vaultKey, let header else { throw VaultError.vaultLocked }
        return try AttachmentStore.open(attachment, vaultID: header.vaultID, key: vaultKey, vaultURL: file.url)
    }

    /// Deletes stored files no row refers to. Only while open: a locked session has no content to compare with.
    public func removeUnusedAttachments() {
        guard state == .open else { return }
        AttachmentStore.removeUnused(keeping: content.attachmentIDs, vaultURL: file.url)
    }

    /// Raw vault key, only to store it behind Touch ID right after an unlock.
    public func vaultKeyForKeychain() throws -> Data {
        guard state == .open, let vaultKey else { throw VaultError.vaultLocked }
        return vaultKey.withUnsafeBytes { Data($0) }
    }

    /// Re-wraps the same vault key under a new password. The content is not re-encrypted with a
    /// new key, so the Touch ID item, if any, still opens the vault; the app recreates it anyway.
    public func changePassword(current: String, new newPassword: String) async throws {
        guard state == .open, let header else { throw VaultError.vaultLocked }
        guard !newPassword.isEmpty else { throw VaultError.invalidContent(.emptyPassword) }
        let currentKey = try await Self.deriveOffMain(password: current, parameters: header.kdf)
        _ = try KeyService.unwrap(header.wrappedKey, with: currentKey)
        try await rewrap(under: newPassword)
    }

    /// For a vault opened with its stored key: the current password is not needed, so a lost one can be
    /// replaced while Touch ID still works. Refused after a password unlock.
    public func setNewPassword(_ newPassword: String) async throws {
        guard state == .open else { throw VaultError.vaultLocked }
        guard unlockMethod == .storedKey else { throw VaultError.quickUnlockRequired }
        guard !newPassword.isEmpty else { throw VaultError.invalidContent(.emptyPassword) }
        try await rewrap(under: newPassword)
    }

    // MARK: Private

    private func rewrap(under newPassword: String) async throws {
        guard let vaultKey, let header else { throw VaultError.vaultLocked }
        let startGeneration = generation
        let renewed = KDFParameters(opsLimit: header.kdf.opsLimit, memLimit: header.kdf.memLimit, salt: KeyService.randomBytes(KDFParameters.saltLength))
        let newKey = try await Self.deriveOffMain(password: newPassword, parameters: renewed)
        guard generation == startGeneration else { throw VaultError.vaultLocked }
        let newHeader = VaultHeader(vaultID: header.vaultID, kdf: renewed, wrappedKey: try KeyService.wrap(vaultKey: vaultKey, with: newKey))
        try file.write(VaultFile.encode(header: newHeader, content: content, key: vaultKey))
        self.header = newHeader
    }

    private func lockAndRead() throws -> (VaultLock, VaultFile.Envelope) {
        let lock = try file.acquireLock()
        do {
            return (lock, try file.read())
        } catch {
            lock.release()
            throw error
        }
    }

    private func open(content: VaultContent, key: SymmetricKey, header: VaultHeader, lock: VaultLock, by method: UnlockMethod) {
        self.content = content
        unlockMethod = method
        self.vaultKey = key
        self.header = header
        self.fileLock = lock
        state = .open
    }

    /// Argon2id takes about a second and 256 MiB: never on the main thread.
    private nonisolated static func deriveOffMain(password: String, parameters: KDFParameters) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            try KeyService.deriveKey(password: password, parameters: parameters)
        }.value
    }
}
