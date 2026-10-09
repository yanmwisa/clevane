import CryptoKit
import Foundation

/// Clear part of the file: what is needed to derive the key and unwrap the vault key. No vault data.
struct VaultHeader: Codable, Equatable, Sendable {
    let vaultID: UUID
    let kdf: KDFParameters
    let wrappedKey: Data
}

/// Vault file format v1:
///
///     "CLVT" | version: UInt16 big-endian | header length: UInt32 big-endian | header JSON | payload
///
/// The payload is an AES-GCM sealed box (nonce, ciphertext, tag) of the content JSON. Everything before
/// it is authenticated as additional data, so a changed header, salt or wrapped key is detected.
public struct VaultFile: Sendable {
    public static let formatVersion = 1
    static let magic = Data("CLVT".utf8)
    private static let prefixLength = 4 + 2 + 4

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The advisory lock lives in its own file because an atomic replace gives the vault a new inode.
    var lockURL: URL {
        url.appendingPathExtension("lock")
    }

    struct Envelope: Equatable {
        let header: VaultHeader
        let authenticatedPrefix: Data
        let payload: Data
    }

    // MARK: Encoding

    static func encode(header: VaultHeader, content: VaultContent, key: SymmetricKey) throws -> Data {
        let prefix = try authenticatedPrefix(for: header)
        guard let payload = try AES.GCM.seal(try contentEncoder.encode(content), using: key, authenticating: prefix).combined else {
            throw VaultError.corruptedFile
        }
        return prefix + payload
    }

    static func decode(_ data: Data) throws -> Envelope {
        guard data.count > prefixLength, data.prefix(4) == magic else { throw VaultError.corruptedFile }
        let version = Int(data.bigEndianInteger(at: 4, as: UInt16.self))
        guard version == formatVersion else { throw VaultError.unsupportedVersion(version) }
        let headerLength = Int(data.bigEndianInteger(at: 6, as: UInt32.self))
        let headerEnd = prefixLength + headerLength
        guard headerLength > 0, data.count > headerEnd else { throw VaultError.corruptedFile }
        let headerBytes = data.subdata(in: (data.startIndex + prefixLength)..<(data.startIndex + headerEnd))
        guard let header = try? JSONDecoder().decode(VaultHeader.self, from: headerBytes) else { throw VaultError.corruptedFile }
        return Envelope(
            header: header,
            authenticatedPrefix: data.subdata(in: data.startIndex..<(data.startIndex + headerEnd)),
            payload: data.subdata(in: (data.startIndex + headerEnd)..<data.endIndex)
        )
    }

    /// The vault key is right (it unwrapped), so any failure here means the payload was altered.
    static func openPayload(of envelope: Envelope, with key: SymmetricKey) throws -> VaultContent {
        guard
            let box = try? AES.GCM.SealedBox(combined: envelope.payload),
            let json = try? AES.GCM.open(box, using: key, authenticating: envelope.authenticatedPrefix),
            let content = try? JSONDecoder().decode(VaultContent.self, from: json),
            ContentRules.isConsistent(content)
        else { throw VaultError.corruptedFile }
        return content
    }

    private static func authenticatedPrefix(for header: VaultHeader) throws -> Data {
        let headerBytes = try JSONEncoder().encode(header)
        var prefix = magic
        prefix.appendBigEndian(UInt16(formatVersion))
        prefix.appendBigEndian(UInt32(headerBytes.count))
        return prefix + headerBytes
    }

    private static let contentEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    // MARK: Disk

    func read() throws -> Envelope {
        guard let data = try? Data(contentsOf: url) else { throw VaultError.corruptedFile }
        return try Self.decode(data)
    }

    /// Atomic replace: the encrypted bytes go to a temporary file in the same folder, are flushed,
    /// then replace the vault. On any failure the previous file is untouched.
    func write(_ data: Data) throws {
        let fileManager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw VaultError.writeFailed
            }
            let handle = try FileHandle(forUpdating: temporary)
            try handle.synchronize()
            try handle.close()
            if exists {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw VaultError.writeFailed
        }
    }

    /// Exclusive advisory lock held while the vault is open. A second holder gets vaultAlreadyOpen.
    func acquireLock() throws -> VaultLock {
        try VaultLock(url: lockURL)
    }
}

/// Holds an flock(2) lock until released or deallocated.
final class VaultLock {
    private var descriptor: Int32

    init(url: URL) throws {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw VaultError.writeFailed }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw VaultError.vaultAlreadyOpen
        }
        self.descriptor = descriptor
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

private extension Data {
    func bigEndianInteger<T: FixedWidthInteger>(at offset: Int, as type: T.Type) -> T {
        let start = startIndex + offset
        return self[start..<(start + MemoryLayout<T>.size)].reduce(T(0)) { ($0 << 8) | T($1) }
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
