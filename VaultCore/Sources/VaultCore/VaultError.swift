import Foundation

/// Every failure VaultCore reports. Codes are stable; messages never contain a vault value,
/// a table or column name, a password or a key.
public enum VaultError: Error, Equatable, Sendable {
    case wrongPassword
    case wrongBackupPassword
    case corruptedFile
    case unsupportedVersion(Int)
    case vaultAlreadyOpen
    case vaultExists
    case vaultLocked
    case writeFailed
    case biometryUnavailable
    case biometryInvalidated
    case biometryCancelled
    case unrecognizedImport
    case fileTooLarge
    case backupFolderNotAllowed
    case quickUnlockRequired
    case invalidContent(ContentProblem)

    public var code: String {
        switch self {
        case .wrongPassword: "WRONG_PASSWORD"
        case .wrongBackupPassword: "WRONG_BACKUP_PASSWORD"
        case .corruptedFile: "CORRUPTED_FILE"
        case .unsupportedVersion: "UNSUPPORTED_VERSION"
        case .vaultAlreadyOpen: "VAULT_ALREADY_OPEN"
        case .vaultExists: "VAULT_EXISTS"
        case .vaultLocked: "VAULT_LOCKED"
        case .writeFailed: "WRITE_FAILED"
        case .biometryUnavailable: "BIOMETRY_UNAVAILABLE"
        case .biometryInvalidated: "BIOMETRY_INVALIDATED"
        case .biometryCancelled: "BIOMETRY_CANCELLED"
        case .unrecognizedImport: "IMPORT_UNRECOGNIZED"
        case .fileTooLarge: "FILE_TOO_LARGE"
        case .backupFolderNotAllowed: "BACKUP_FOLDER_NOT_ALLOWED"
        case .quickUnlockRequired: "QUICK_UNLOCK_REQUIRED"
        case .invalidContent(let problem): problem.rawValue
        }
    }
}

extension VaultError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .wrongPassword: "That password did not unlock this vault."
        case .wrongBackupPassword: "That password did not open this backup. Use the master password the backup was made with."
        case .corruptedFile: "This vault file is damaged or was changed outside Clevane."
        case .unsupportedVersion(let version): "This vault uses format version \(version), which this version of Clevane cannot read."
        case .vaultAlreadyOpen: "Vault already open in another Clevane window."
        case .vaultExists: "A vault already exists at this location."
        case .vaultLocked: "The vault is locked."
        case .writeFailed: "Clevane could not save the vault. The previous version is intact."
        case .biometryUnavailable: "Touch ID and Mac password unlock are not available here. Use your master password."
        case .biometryInvalidated: "Quick unlock was reset. Unlock with your master password, then turn it on again in Settings."
        case .biometryCancelled: "Authentication was cancelled. Use your master password or try again."
        case .unrecognizedImport: "This file is not a password export from Chrome, Google, Safari or Firefox, or it holds no logins."
        case .fileTooLarge: "This file is larger than 50 MB, the most Clevane keeps in a vault."
        case .backupFolderNotAllowed: "This folder belongs to a vault or to a backup. Choose another folder to keep backups."
        case .quickUnlockRequired: "Enter the current master password, or open the vault with Touch ID or your Mac password to set a new one without it."
        case .invalidContent(let problem): problem.message
        }
    }
}

/// Rules broken by an edit, reported to the person editing. Names are never repeated back.
public enum ContentProblem: String, Equatable, Sendable, CaseIterable {
    case emptyTableName = "EMPTY_TABLE_NAME"
    case duplicateTableName = "DUPLICATE_TABLE_NAME"
    case noColumns = "NO_COLUMNS"
    case emptyColumnName = "EMPTY_COLUMN_NAME"
    case duplicateColumnName = "DUPLICATE_COLUMN_NAME"
    case emptyRow = "EMPTY_ROW"
    case unknownTable = "UNKNOWN_TABLE"
    case unknownRow = "UNKNOWN_ROW"
    case emptyPassword = "EMPTY_PASSWORD"
    case passwordsDoNotMatch = "PASSWORDS_DO_NOT_MATCH"
    case fileTypeChange = "FILE_TYPE_CHANGE"

    public var message: String {
        switch self {
        case .emptyTableName: "Enter a table name."
        case .duplicateTableName: "A table with this name already exists."
        case .noColumns: "Add at least one column."
        case .emptyColumnName: "Name every column."
        case .duplicateColumnName: "Two columns have the same name."
        case .emptyRow: "Fill in at least one field."
        case .unknownTable: "This table no longer exists."
        case .unknownRow: "This row no longer exists."
        case .emptyPassword: "Enter a master password."
        case .passwordsDoNotMatch: "The two passwords do not match."
        case .fileTypeChange: "A column cannot change to or from File. Add a new File column instead."
        }
    }
}
