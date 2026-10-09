import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Where the vault key is kept for quick unlock (Touch ID or the Mac password). Tests use a fake.
/// The master password always remains a way in.
public protocol VaultKeyStore: Sendable {
    /// Whether quick unlock can work on this Mac.
    var isAvailable: Bool { get }
    /// Shows the system prompt (Touch ID or Mac password) and returns once it is answered.
    func confirmPresence(reason: String) async throws
    func storeKey(_ key: Data, for vaultID: UUID) throws
    /// Shows the system prompt and blocks until it is answered: call it off the main thread.
    func loadKey(for vaultID: UUID, reason: String) throws -> Data
    func deleteKey(for vaultID: UUID) throws
}

/// Quick unlock through the Secure Enclave:
/// a P-256 key that never leaves this Mac's Secure Enclave and only works after Touch ID with the fingers
/// enrolled today, or the Mac password. The vault key is sealed to it with HPKE (CryptoKit, RFC 9180).
/// The file on disk holds the sealed key and the enclave key's opaque handle, both useless on another Mac.
/// Unlike a keychain item, this needs no provisioning profile, so it works in Clevane's own build.
public struct SecureEnclaveKeyStore: VaultKeyStore {
    static let fileExtension = "quickunlock"
    private static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256

    private let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Touch ID itself, for wording: without it macOS asks for the Mac password.
    public static var hasTouchID: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    public var isAvailable: Bool {
        SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    public func confirmPresence(reason: String) async throws {
        do {
            _ = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw Self.error(for: error)
        }
    }

    public func storeKey(_ key: Data, for vaultID: UUID) throws {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet, .or, .devicePasscode], &accessError
        ) else {
            accessError?.release()
            throw VaultError.biometryUnavailable
        }
        let sealed: SealedKey
        do {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
            var sender = try HPKE.Sender(recipientKey: enclaveKey.publicKey, ciphersuite: Self.suite, info: Self.info(for: vaultID))
            let ciphertext = try sender.seal(key)
            sealed = SealedKey(version: 1, enclaveKey: enclaveKey.dataRepresentation, encapsulatedKey: sender.encapsulatedKey, ciphertext: ciphertext)
        } catch {
            throw VaultError.biometryUnavailable
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try VaultFile(url: fileURL(for: vaultID)).write(JSONEncoder().encode(sealed))
    }

    public func loadKey(for vaultID: UUID, reason: String) throws -> Data {
        guard let data = try? Data(contentsOf: fileURL(for: vaultID)),
              let sealed = try? JSONDecoder().decode(SealedKey.self, from: data), sealed.version == 1 else {
            throw VaultError.biometryInvalidated
        }
        let context = LAContext()
        context.localizedReason = reason
        do {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: sealed.enclaveKey, authenticationContext: context)
            var recipient = try HPKE.Recipient(privateKey: enclaveKey, ciphersuite: Self.suite, info: Self.info(for: vaultID), encapsulatedKey: sealed.encapsulatedKey)
            return try recipient.open(sealed.ciphertext)
        } catch {
            throw Self.error(for: error)
        }
    }

    public func deleteKey(for vaultID: UUID) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: vaultID))
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw VaultError.writeFailed
        }
    }

    func fileURL(for vaultID: UUID) -> URL {
        folder.appendingPathComponent(vaultID.uuidString).appendingPathExtension(Self.fileExtension)
    }

    /// Binds the sealed key to its vault: a file copied under another vault's name does not open.
    static func info(for vaultID: UUID) -> Data {
        Data("clevane-quick-unlock-v1:\(vaultID.uuidString)".utf8)
    }

    /// Prompt outcome to a stable error: a dismissed prompt is a cancel, a missing Mac password or sensor is
    /// unavailable, anything else (enclave key gone, sealed data altered) resets quick unlock to the password.
    static func error(for failure: Error) -> VaultError {
        switch (failure as? LAError)?.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: .biometryCancelled
        case .biometryNotAvailable, .passcodeNotSet, .biometryNotEnrolled, .notInteractive: .biometryUnavailable
        case .none: .biometryInvalidated
        default: .biometryUnavailable
        }
    }
}

/// On-disk form of a quick unlock entry. None of it opens anything without this Mac's Secure Enclave.
struct SealedKey: Codable {
    let version: Int
    let enclaveKey: Data
    let encapsulatedKey: Data
    let ciphertext: Data
}
