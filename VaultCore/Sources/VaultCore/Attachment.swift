import CryptoKit
import Foundation

/// A file kept in a File column. The row holds only this description; the bytes live encrypted in
/// `<vault>.files/<id>.blob`, sealed with the vault key.
public struct Attachment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let byteCount: Int
    /// Uniform type identifier, e.g. public.jpeg, used to show photos and pick an icon.
    public let contentType: String

    /// The most a vault keeps per file; larger files are refused before they are read.
    public static let maximumByteCount = 50 * 1024 * 1024

    public init(id: UUID = UUID(), name: String, byteCount: Int, contentType: String) {
        self.id = id
        self.name = name
        self.byteCount = byteCount
        self.contentType = contentType
    }
}

/// Encrypted file storage next to the vault. Each file is one AES-GCM box (CryptoKit) under the vault key;
/// the additional data binds it to its vault and to its own identifier, so a file swapped in from another
/// vault, or renamed to another attachment's identifier, fails to open.
enum AttachmentStore {
    static func folder(for vaultURL: URL) -> URL {
        vaultURL.appendingPathExtension("files")
    }

    static func blobURL(for attachmentID: UUID, vaultURL: URL) -> URL {
        folder(for: vaultURL).appendingPathComponent(attachmentID.uuidString).appendingPathExtension("blob")
    }

    static func additionalData(vaultID: UUID, attachmentID: UUID) -> Data {
        Data("clevane-attachment-v1:\(vaultID.uuidString):\(attachmentID.uuidString)".utf8)
    }

    static func seal(_ data: Data, as attachment: Attachment, vaultID: UUID, key: SymmetricKey, vaultURL: URL) throws {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.seal(data, using: key, authenticating: additionalData(vaultID: vaultID, attachmentID: attachment.id))
        } catch {
            throw VaultError.writeFailed
        }
        guard let combined = box.combined else { throw VaultError.writeFailed }
        do {
            try FileManager.default.createDirectory(at: folder(for: vaultURL), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw VaultError.writeFailed
        }
        try VaultFile(url: blobURL(for: attachment.id, vaultURL: vaultURL)).write(combined)
    }

    static func open(_ attachment: Attachment, vaultID: UUID, key: SymmetricKey, vaultURL: URL) throws -> Data {
        guard let combined = try? Data(contentsOf: blobURL(for: attachment.id, vaultURL: vaultURL)),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(box, using: key, authenticating: additionalData(vaultID: vaultID, attachmentID: attachment.id)) else {
            throw VaultError.corruptedFile
        }
        return data
    }

    /// Deletes stored files that no row refers to any more: removed from a row, row or table deleted,
    /// or picked in a sheet that was then cancelled. Returns how many were removed.
    @discardableResult
    static func removeUnused(keeping referenced: Set<UUID>, vaultURL: URL) -> Int {
        let fileManager = FileManager.default
        let stored = (try? fileManager.contentsOfDirectory(at: folder(for: vaultURL), includingPropertiesForKeys: nil)) ?? []
        let unused = stored.filter { file in
            guard file.pathExtension == "blob", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return false }
            return !referenced.contains(id)
        }
        return unused.filter { (try? fileManager.removeItem(at: $0)) != nil }.count
    }
}

extension VaultContent {
    /// Every attachment any row refers to.
    var attachmentIDs: Set<UUID> {
        Set(tables.flatMap { $0.rows.flatMap { $0.attachments.values.map(\.id) } })
    }
}
