import Foundation

/// A backup is a package (a folder shown as one file) holding a copy of the encrypted vault and of its
/// encrypted files. It opens with the vault's master password alone, on any Mac. Backups made before File
/// columns existed are a single copied vault file; both restore. Restoring creates a separate vault; it never
/// overwrites the current one.
public enum BackupService {
    public static let fileExtension = "cvbackup"
    static let vaultEntry = "Vault.clevane"

    public static func backupFileName(on date: Date, attempt: Int = 1) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let suffix = attempt > 1 ? "-\(attempt)" : ""
        return "clevane-\(formatter.string(from: date))\(suffix).\(fileExtension)"
    }

    /// A backup never goes inside a vault's files folder (`<vault>.clevane.files`) or inside another backup:
    /// it would mix with what Clevane manages there.
    public static func checkDestination(_ folder: URL) throws {
        let isReserved = folder.standardizedFileURL.pathComponents.contains {
            $0.hasSuffix(".clevane.files") || $0.hasSuffix(".\(fileExtension)")
        }
        if isReserved { throw VaultError.backupFolderNotAllowed }
    }

    /// Copies the vault and its files into `folder` under a dated name that never replaces an existing backup.
    /// A failure leaves no partial backup behind.
    @discardableResult
    public static func createBackup(of file: VaultFile, in folder: URL, on date: Date = Date()) throws -> URL {
        try checkDestination(folder)
        let fileManager = FileManager.default
        let destination = (1...999).lazy
            .map { folder.appendingPathComponent(backupFileName(on: date, attempt: $0)) }
            .first { !fileManager.fileExists(atPath: $0.path) }
        guard let destination else { throw VaultError.writeFailed }
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let vaultCopy = destination.appendingPathComponent(vaultEntry)
            try fileManager.copyItem(at: file.url, to: vaultCopy)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultCopy.path)
            let files = AttachmentStore.folder(for: file.url)
            if fileManager.fileExists(atPath: files.path) {
                try fileManager.copyItem(at: files, to: AttachmentStore.folder(for: vaultCopy))
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw VaultError.writeFailed
        }
        return destination
    }

    /// Copies the backup to `vaultURL` and opens it with its password. On a wrong password or a damaged
    /// backup, the copy is removed and nothing else changes.
    @MainActor
    public static func restore(_ backupURL: URL, to vaultURL: URL, password: String) async throws -> VaultSession {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: vaultURL.path) else { throw VaultError.vaultExists }
        var isPackage: ObjCBool = false
        fileManager.fileExists(atPath: backupURL.path, isDirectory: &isPackage)
        let vaultCopy = isPackage.boolValue ? backupURL.appendingPathComponent(vaultEntry) : backupURL
        let restoredFiles = AttachmentStore.folder(for: vaultURL)
        do {
            try fileManager.copyItem(at: vaultCopy, to: vaultURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
            let files = AttachmentStore.folder(for: vaultCopy)
            if isPackage.boolValue && fileManager.fileExists(atPath: files.path) {
                try fileManager.copyItem(at: files, to: restoredFiles)
            }
        } catch {
            try? fileManager.removeItem(at: vaultURL)
            try? fileManager.removeItem(at: restoredFiles)
            throw VaultError.writeFailed
        }
        let session = VaultSession(file: VaultFile(url: vaultURL))
        do {
            try await session.unlock(password: password)
            return session
        } catch {
            try? fileManager.removeItem(at: vaultURL)
            try? fileManager.removeItem(at: restoredFiles)
            try? fileManager.removeItem(at: session.file.lockURL)
            throw (error as? VaultError) == .wrongPassword ? VaultError.wrongBackupPassword : error
        }
    }
}
