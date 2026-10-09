import CryptoKit
import Foundation
import Testing
@testable import VaultCore

struct KeyServiceTests {
    @Test func linksTheInspectedLibsodium() {
        #expect(KeyService.libsodiumVersion == "1.0.22")
    }

    @Test func moderateParametersAreTheD7Values() {
        let parameters = KDFParameters.moderate()
        #expect(parameters.algorithm == "argon2id13")
        #expect(parameters.opsLimit == 3)
        #expect(parameters.memLimit == 268_435_456)
        #expect(parameters.salt.count == 16)
        #expect(parameters.salt != KDFParameters.moderate().salt)
    }

    @Test func sameInputsGiveTheSameKey() throws {
        let parameters = Fixture.fastKDF()
        let first = try KeyService.deriveKey(password: Fixture.password, parameters: parameters)
        let second = try KeyService.deriveKey(password: Fixture.password, parameters: parameters)
        #expect(first == second)
    }

    @Test func passwordOrSaltChangeTheKey() throws {
        let parameters = Fixture.fastKDF()
        let reference = try KeyService.deriveKey(password: Fixture.password, parameters: parameters)
        #expect(try KeyService.deriveKey(password: Fixture.password + "!", parameters: parameters) != reference)
        #expect(try KeyService.deriveKey(password: Fixture.password, parameters: Fixture.fastKDF()) != reference)
    }

    /// "é" typed as one character or as "e" plus an accent gives the same key.
    @Test func passwordIsNormalized() throws {
        let parameters = Fixture.fastKDF()
        let composed = try KeyService.deriveKey(password: "caf\u{E9}", parameters: parameters)
        let decomposed = try KeyService.deriveKey(password: "cafe\u{301}", parameters: parameters)
        #expect(composed == decomposed)
    }

    @Test func rejectsUnknownAlgorithmOrSalt() {
        let badSalt = KDFParameters(opsLimit: 1, memLimit: 8192, salt: Data([1, 2, 3]))
        #expect(throws: VaultError.corruptedFile) { try KeyService.deriveKey(password: "x", parameters: badSalt) }
    }

    @Test func wrapThenUnwrapReturnsTheVaultKey() throws {
        let keyEncryptionKey = SymmetricKey(size: .bits256)
        let vaultKey = KeyService.newVaultKey()
        let wrapped = try KeyService.wrap(vaultKey: vaultKey, with: keyEncryptionKey)
        #expect(try KeyService.unwrap(wrapped, with: keyEncryptionKey) == vaultKey)
    }

    @Test func wrongKeyOrTamperedWrapIsAWrongPassword() throws {
        let keyEncryptionKey = SymmetricKey(size: .bits256)
        var wrapped = try KeyService.wrap(vaultKey: KeyService.newVaultKey(), with: keyEncryptionKey)
        #expect(throws: VaultError.wrongPassword) { try KeyService.unwrap(wrapped, with: SymmetricKey(size: .bits256)) }
        wrapped[wrapped.startIndex + 20] ^= 0xFF
        #expect(throws: VaultError.wrongPassword) { try KeyService.unwrap(wrapped, with: keyEncryptionKey) }
    }
}
