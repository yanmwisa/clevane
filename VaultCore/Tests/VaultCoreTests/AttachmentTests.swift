import Foundation
import Testing
@testable import VaultCore

/// File columns: encrypted storage, clean-up, rules, search and backups. Fictional bytes only.
@MainActor
struct AttachmentTests {
    private let photoBytes = Data("FAKE-PHOTO-\(Fixture.sentinel)".utf8)

    private func documentsVault(in folder: TemporaryFolder) async throws -> (VaultSession, UUID, [Column]) {
        let session = try await makeOpenVault(in: folder)
        let columns = TableTemplate.documents.makeColumns()
        let tableID = try session.edit { try $0.addTable(name: "Documents", columns: columns) }
        return (session, tableID, columns)
    }

    @Test func sealedFileOpensAndHoldsNoClearBytes() async throws {
        let folder = try TemporaryFolder()
        let (session, _, _) = try await documentsVault(in: folder)
        let attachment = try session.sealAttachment(photoBytes, name: "passport.jpg", contentType: "public.jpeg")
        #expect(attachment.byteCount == photoBytes.count)
        #expect(try session.openAttachment(attachment) == photoBytes)

        let blob = AttachmentStore.blobURL(for: attachment.id, vaultURL: session.file.url)
        let stored = try Data(contentsOf: blob)
        #expect(stored.range(of: Data(Fixture.sentinel.utf8)) == nil)
        #expect(try FileManager.default.attributesOfItem(atPath: blob.path)[.posixPermissions] as? Int == 0o600)
    }

    /// A stored file altered on disk, or moved under another attachment's identifier, refuses to open.
    @Test func tamperedOrSwappedFilesRefuse() async throws {
        let folder = try TemporaryFolder()
        let (session, _, _) = try await documentsVault(in: folder)
        let first = try session.sealAttachment(photoBytes, name: "a.jpg", contentType: "public.jpeg")
        let second = try session.sealAttachment(photoBytes, name: "b.jpg", contentType: "public.jpeg")
        let firstBlob = AttachmentStore.blobURL(for: first.id, vaultURL: session.file.url)
        let secondBlob = AttachmentStore.blobURL(for: second.id, vaultURL: session.file.url)

        try FileManager.default.removeItem(at: secondBlob)
        try FileManager.default.copyItem(at: firstBlob, to: secondBlob)
        #expect(throws: VaultError.corruptedFile) { try session.openAttachment(second) }

        var bytes = try Data(contentsOf: firstBlob)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: firstBlob)
        #expect(throws: VaultError.corruptedFile) { try session.openAttachment(first) }
    }

    @Test func tooLargeOrLockedIsRefused() async throws {
        let folder = try TemporaryFolder()
        let (session, _, _) = try await documentsVault(in: folder)
        #expect(throws: VaultError.fileTooLarge) {
            try session.sealAttachment(Data(count: Attachment.maximumByteCount + 1), name: "big.mov", contentType: "public.movie")
        }
        let attachment = try session.sealAttachment(photoBytes, name: "a.jpg", contentType: "public.jpeg")
        session.lock()
        #expect(throws: VaultError.vaultLocked) { try session.openAttachment(attachment) }
    }

    /// Files leave disk once no row refers to them: removed from the row, row deleted, or a cancelled pick.
    @Test func unusedFilesAreRemoved() async throws {
        let folder = try TemporaryFolder()
        let (session, tableID, columns) = try await documentsVault(in: folder)
        let kept = try session.sealAttachment(photoBytes, name: "kept.jpg", contentType: "public.jpeg")
        let abandoned = try session.sealAttachment(photoBytes, name: "cancelled.jpg", contentType: "public.jpeg")
        let rowID = try session.edit { try $0.addRow(to: tableID, values: [columns[0].id: "Passport"], attachments: [columns[1].id: kept]) }

        session.removeUnusedAttachments()
        #expect(FileManager.default.fileExists(atPath: AttachmentStore.blobURL(for: kept.id, vaultURL: session.file.url).path))
        #expect(!FileManager.default.fileExists(atPath: AttachmentStore.blobURL(for: abandoned.id, vaultURL: session.file.url).path))

        try session.edit { try $0.deleteRow(rowID, in: tableID) }
        session.removeUnusedAttachments()
        #expect(!FileManager.default.fileExists(atPath: AttachmentStore.blobURL(for: kept.id, vaultURL: session.file.url).path))
    }

    @Test func rulesKeepFilesInFileColumns() throws {
        var content = VaultContent()
        let columns = TableTemplate.documents.makeColumns()
        let tableID = try content.addTable(name: "Documents", columns: columns)
        let file = Attachment(name: "scan.pdf", byteCount: 10, contentType: "com.adobe.pdf")

        let rowID = try content.addRow(to: tableID, values: [columns[1].id: "text in a file column"], attachments: [columns[1].id: file, columns[0].id: file])
        let row = try #require(content.table(tableID)?.rows.first { $0.id == rowID })
        #expect(row.values.isEmpty)
        #expect(row.attachments == [columns[1].id: file])
        #expect(content.table(tableID)?.rows(matching: "SCAN").count == 1)

        var retyped = columns
        retyped[1].type = .text
        #expect(throws: VaultError.invalidContent(.fileTypeChange)) { try content.setColumns(retyped, of: tableID) }
        try content.setColumns([columns[0], columns[2]], of: tableID)
        #expect(content.table(tableID)?.rows.first?.attachments.isEmpty == true)
    }

    /// Vaults written before File columns existed still decode: their rows have no attachments key.
    @Test func olderRowsDecode() throws {
        struct RowBeforeFiles: Encodable {
            let id: UUID
            let values: [UUID: String]
        }
        let columnID = UUID()
        let json = try JSONEncoder().encode(RowBeforeFiles(id: UUID(), values: [columnID: "ACC-1042"]))
        let row = try JSONDecoder().decode(Row.self, from: json)
        #expect(row.values[columnID] == "ACC-1042")
        #expect(row.attachments.isEmpty)
    }

    /// A backup carries the files; it restores elsewhere with the password alone, and so does an older backup
    /// that is a single vault file.
    @Test func backupsCarryFilesAndOldBackupsStillRestore() async throws {
        let folder = try TemporaryFolder()
        let (session, tableID, columns) = try await documentsVault(in: folder)
        let attachment = try session.sealAttachment(photoBytes, name: "passport.jpg", contentType: "public.jpeg")
        try session.edit { try $0.addRow(to: tableID, values: [:], attachments: [columns[1].id: attachment]) }
        let backup = try BackupService.createBackup(of: session.file, in: folder.url)

        let other = try TemporaryFolder()
        let restored = try await BackupService.restore(backup, to: other.file("Restored.clevane"), password: Fixture.password)
        #expect(try restored.openAttachment(attachment) == photoBytes)

        let older = folder.url.appendingPathComponent("older.\(BackupService.fileExtension)")
        try FileManager.default.copyItem(at: session.file.url, to: older)
        let fromOlder = try await BackupService.restore(older, to: other.file("From Older.clevane"), password: Fixture.password)
        #expect(fromOlder.content.tables.count == 1)
    }
}
