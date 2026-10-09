import Foundation

/// Ready-made tables for the secrets people keep most. Each call to `makeColumns()` gives fresh identifiers.
public enum TableTemplate: CaseIterable, Sendable {
    case logins, bankAccounts, apiKeys, wifi, privateNotes, documents

    public var name: String {
        switch self {
        case .logins: "Logins"
        case .bankAccounts: "Bank Accounts"
        case .apiKeys: "API Keys"
        case .wifi: "Wi-Fi"
        case .privateNotes: "Private Notes"
        case .documents: "Documents"
        }
    }

    public func makeColumns() -> [Column] {
        switch self {
        case .logins:
            [Column(name: "Website", type: .text), Column(name: "Username", type: .text), Column(name: "Password", type: .secret),
             Column(name: "URL", type: .text), Column(name: "Note", type: .note)]
        case .bankAccounts:
            [Column(name: "Bank", type: .text), Column(name: "Account number", type: .text), Column(name: "PIN", type: .secret),
             Column(name: "Note", type: .note)]
        case .apiKeys:
            [Column(name: "Service", type: .text), Column(name: "Key", type: .secret), Column(name: "Note", type: .note)]
        case .wifi:
            [Column(name: "Network", type: .text), Column(name: "Password", type: .secret)]
        case .privateNotes:
            [Column(name: "Title", type: .text), Column(name: "Note", type: .note)]
        case .documents:
            [Column(name: "Title", type: .text), Column(name: "File", type: .file), Column(name: "Note", type: .note)]
        }
    }
}

extension VaultContent {
    /// Keeps the master passphrase chosen at creation in a "Recovery" table, as a record: the passphrase is
    /// what opens the vault, so this copy helps to read it again later, never to get in.
    public mutating func keepRecoveryPassphrase(_ passphrase: String, note: String) throws -> UUID {
        let item = Column(name: "Item", type: .text), secret = Column(name: "Passphrase", type: .secret), remark = Column(name: "Note", type: .note)
        var draft = self
        let tableID = try draft.addTable(name: availableTableName("Recovery"), columns: [item, secret, remark])
        _ = try draft.addRow(to: tableID, values: [item.id: "Master passphrase", secret.id: passphrase, remark.id: note])
        self = draft
        return tableID
    }

    /// `base`, or `base 2`, `base 3`… when a table already has that name, compared as the uniqueness rule does.
    public func availableTableName(_ base: String) -> String {
        let taken = Set(tables.map { ContentRules.normalized($0.name) })
        guard taken.contains(ContentRules.normalized(base)) else { return base }
        var number = 2
        while taken.contains(ContentRules.normalized("\(base) \(number)")) { number += 1 }
        return "\(base) \(number)"
    }
}
