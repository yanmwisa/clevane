import CryptoKit
import Foundation
import Testing
@testable import VaultCore

struct VaultFileTests {
    private func sampleFile() throws -> (data: Data, key: SymmetricKey, content: VaultContent) {
        let key = KeyService.newVaultKey()
        let header = VaultHeader(vaultID: UUID(), kdf: Fixture.fastKDF(), wrappedKey: Data(repeating: 7, count: 60))
        let content = VaultContent(tables: [Fixture.tradingTable()])
        return (try VaultFile.encode(header: header, content: content, key: key), key, content)
    }

    @Test func encodeThenDecodeReturnsTheContent() throws {
        let (data, key, content) = try sampleFile()
        #expect(data.prefix(4) == Data("CLVT".utf8))
        let envelope = try VaultFile.decode(data)
        #expect(try VaultFile.openPayload(of: envelope, with: key) == content)
    }

    /// One altered byte anywhere is detected: in the header (authenticated) or in the payload.
    @Test(arguments: [0, 3, 12, 40, -40, -1])
    func alteredByteIsDetected(offset: Int) throws {
        let (data, key, _) = try sampleFile()
        var altered = data
        let index = offset >= 0 ? altered.startIndex + offset : altered.endIndex + offset
        altered[index] ^= 0x01
        #expect(throws: VaultError.self) {
            _ = try VaultFile.openPayload(of: try VaultFile.decode(altered), with: key)
        }
    }

    @Test(arguments: [0, 4, 9, 30, 200])
    func truncatedFileIsCorrupted(length: Int) throws {
        let (data, key, _) = try sampleFile()
        #expect(throws: VaultError.corruptedFile) {
            _ = try VaultFile.openPayload(of: try VaultFile.decode(data.prefix(length)), with: key)
        }
    }

    @Test(arguments: [0, 2, 9])
    func unknownVersionIsReported(version: UInt16) throws {
        var data = try sampleFile().data
        data[data.startIndex + 4] = UInt8(version >> 8)
        data[data.startIndex + 5] = UInt8(version & 0xFF)
        #expect(throws: VaultError.unsupportedVersion(Int(version))) { try VaultFile.decode(data) }
    }

    @Test func writtenFileIsPrivateAndHasNoLeftover() throws {
        let folder = try TemporaryFolder()
        let file = VaultFile(url: folder.file())
        try file.write(Data("first".utf8))
        try file.write(Data("second".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try Data(contentsOf: file.url) == Data("second".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.url.path)
        #expect(names == [file.url.lastPathComponent])
    }

    /// Disk refuses the write: error writeFailed, and the previous file is intact.
    @Test func failedWriteKeepsThePreviousFile() throws {
        let folder = try TemporaryFolder()
        let file = VaultFile(url: folder.file())
        try file.write(Data("previous".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.url.path)
        #expect(throws: VaultError.writeFailed) { try file.write(Data("next".utf8)) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.url.path)
        #expect(try Data(contentsOf: file.url) == Data("previous".utf8))
    }

    /// Two opens of the same vault: the second is refused while the first holds the lock.
    @Test func secondLockIsRefusedUntilReleased() throws {
        let folder = try TemporaryFolder()
        let file = VaultFile(url: folder.file())
        let first = try file.acquireLock()
        #expect(throws: VaultError.vaultAlreadyOpen) { _ = try file.acquireLock() }
        first.release()
        let second = try file.acquireLock()
        second.release()
    }
}
