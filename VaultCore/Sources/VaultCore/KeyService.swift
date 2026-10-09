import CryptoKit
import Foundation
import Sodium

/// Argon2id parameters, stored in the clear in the file header so they can be raised later.
public struct KDFParameters: Codable, Equatable, Sendable {
    public static let algorithm = "argon2id13"
    public static let saltLength = 16

    public let algorithm: String
    public let opsLimit: Int
    public let memLimit: Int
    public let salt: Data

    /// libsodium "moderate" values: 3 passes, 256 MiB. Every new vault uses them.
    public static func moderate() -> KDFParameters {
        KDFParameters(opsLimit: 3, memLimit: 268_435_456, salt: KeyService.randomBytes(saltLength))
    }

    /// Smaller values are only for tests, which derive hundreds of keys.
    init(opsLimit: Int, memLimit: Int, salt: Data) {
        self.algorithm = Self.algorithm
        self.opsLimit = opsLimit
        self.memLimit = memLimit
        self.salt = salt
    }
}

/// The only place that turns a password into a key. libsodium stays behind this boundary.
public enum KeyService {
    static let keyLength = 32
    private static let wrapContext = Data("clevane-v1-vault-key".utf8)

    /// Derives the key-encryption key with Argon2id. Slow by design: call it off the main thread.
    /// The password is normalized (NFC) so the same characters typed two ways give the same key.
    public static func deriveKey(password: String, parameters: KDFParameters) throws -> SymmetricKey {
        guard parameters.algorithm == KDFParameters.algorithm, parameters.salt.count == KDFParameters.saltLength else {
            throw VaultError.corruptedFile
        }
        let passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
        // Sodium() runs sodium_init(), which libsodium requires before any call; it is idempotent.
        let derived = Sodium().pwHash.hash(
            outputLength: keyLength,
            passwd: passwordBytes,
            salt: Array(parameters.salt),
            opsLimit: parameters.opsLimit,
            memLimit: parameters.memLimit,
            alg: .Argon2ID13
        )
        guard let derived else { throw VaultError.corruptedFile }
        return SymmetricKey(data: derived)
    }

    /// Version of the linked libsodium, checked by a test against the inspected 1.0.22.
    public static var libsodiumVersion: String {
        Sodium().version.lib.VersionString
    }

    public static func newVaultKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Seals the vault key with the password-derived key (AES-GCM, CryptoKit).
    static func wrap(vaultKey: SymmetricKey, with keyEncryptionKey: SymmetricKey) throws -> Data {
        let keyBytes = vaultKey.withUnsafeBytes { Data($0) }
        guard let sealed = try AES.GCM.seal(keyBytes, using: keyEncryptionKey, authenticating: wrapContext).combined else {
            throw VaultError.corruptedFile
        }
        return sealed
    }

    /// A wrong password and a tampered wrapped key are indistinguishable by design: both fail authentication.
    static func unwrap(_ wrappedKey: Data, with keyEncryptionKey: SymmetricKey) throws -> SymmetricKey {
        do {
            let box = try AES.GCM.SealedBox(combined: wrappedKey)
            let keyBytes = try AES.GCM.open(box, using: keyEncryptionKey, authenticating: wrapContext)
            guard keyBytes.count == keyLength else { throw VaultError.corruptedFile }
            return SymmetricKey(data: keyBytes)
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.wrongPassword
        }
    }

    static func randomBytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }
}
