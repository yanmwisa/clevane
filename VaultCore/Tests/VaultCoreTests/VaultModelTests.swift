import Foundation
import Testing
@testable import VaultCore

struct VaultModelTests {
    @Test func rowTitleIsTheFirstTextColumnOrRowN() {
        var table = Fixture.tradingTable()
        #expect(table.title(of: table.rows[0]) == "ACC-1042")
        table.rows[1].values[table.columns[0].id] = "   "
        #expect(table.title(of: table.rows[1]) == "Row 2")
        let secretsOnly = VaultTable(name: "Keys", columns: [Column(name: "Key", type: .secret)], rows: [Row(values: [:])])
        #expect(secretsOnly.title(of: secretsOnly.rows[0]) == "Row 1")
    }

    @Test func columnRules() {
        #expect(ContentRules.columnsProblem([]) == .noColumns)
        #expect(ContentRules.columnsProblem([Column(name: " ", type: .text)]) == .emptyColumnName)
        #expect(ContentRules.columnsProblem([Column(name: "Login", type: .text), Column(name: "login ", type: .secret)]) == .duplicateColumnName)
        #expect(ContentRules.columnsProblem([Column(name: "Login", type: .text)]) == nil)
    }

    @Test func tableNamesAreUniqueIgnoringCaseAndSpaces() throws {
        var content = VaultContent()
        try content.addTable(name: "Bank Accounts", columns: [Column(name: "Username", type: .text)])
        #expect(throws: VaultError.invalidContent(.duplicateTableName)) {
            try content.addTable(name: " bank accounts ", columns: [Column(name: "Username", type: .text)])
        }
        #expect(throws: VaultError.invalidContent(.emptyTableName)) {
            try content.addTable(name: "  ", columns: [Column(name: "Username", type: .text)])
        }
    }

    @Test func removingAColumnDeletesItsValuesOnly() throws {
        var content = VaultContent(tables: [Fixture.tradingTable()])
        let table = content.tables[0]
        #expect(table.filledValueCount(in: table.columns[2].id) == 1)
        try content.setColumns(Array(table.columns.prefix(2)), of: table.id)
        let updated = content.tables[0]
        #expect(updated.columns.count == 2)
        #expect(updated.rows.allSatisfy { $0.values[table.columns[2].id] == nil })
        #expect(updated.rows[0].values[table.columns[1].id] == "Sample-Trade-01")
    }

    @Test func renamingAColumnKeepsItsValues() throws {
        var content = VaultContent(tables: [Fixture.tradingTable()])
        var columns = content.tables[0].columns
        columns[0].name = "Account"
        try content.setColumns(columns, of: content.tables[0].id)
        #expect(content.tables[0].rows[0].values[columns[0].id] == "ACC-1042")
    }

    @Test func rowsNeedOneValueAndDropBlanks() throws {
        var content = VaultContent(tables: [Fixture.tradingTable()])
        let table = content.tables[0]
        #expect(throws: VaultError.invalidContent(.emptyRow)) {
            try content.addRow(to: table.id, values: [table.columns[0].id: "  "])
        }
        let rowID = try content.addRow(to: table.id, values: [table.columns[0].id: "ACC-3315", table.columns[1].id: ""])
        let row = try #require(content.tables[0].rows.first { $0.id == rowID })
        #expect(row.values == [table.columns[0].id: "ACC-3315"])
    }

    @Test func editsOnMissingTableOrRowFail() {
        var content = VaultContent()
        #expect(throws: VaultError.invalidContent(.unknownTable)) { try content.deleteTable(UUID()) }
        content.tables = [Fixture.tradingTable()]
        #expect(throws: VaultError.invalidContent(.unknownRow)) { try content.deleteRow(UUID(), in: content.tables[0].id) }
    }

    @Test func consistencyCheckRejectsValuesOfUnknownColumns() {
        var table = Fixture.tradingTable()
        #expect(ContentRules.isConsistent(VaultContent(tables: [table])))
        table.rows[0].values[UUID()] = "orphan"
        #expect(!ContentRules.isConsistent(VaultContent(tables: [table])))
    }

    @Test func errorCodesAreStableAndUnique() {
        let errors: [VaultError] = [.wrongPassword, .corruptedFile, .unsupportedVersion(2), .vaultAlreadyOpen, .vaultExists, .vaultLocked,
                                    .writeFailed, .biometryUnavailable, .biometryInvalidated, .biometryCancelled, .unrecognizedImport,
                                    .fileTooLarge, .backupFolderNotAllowed, .wrongBackupPassword, .quickUnlockRequired]
            + ContentProblem.allCases.map { .invalidContent($0) }
        let codes = errors.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(VaultError.wrongPassword.code == "WRONG_PASSWORD")
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}

struct TableTemplateTests {
    /// The passphrase goes in a Secret column, so it stays folded and out of search; a taken name is numbered.
    @Test func recoveryPassphraseIsASecret() throws {
        var content = VaultContent()
        _ = try content.addTable(name: "Recovery", columns: [Column(name: "Title", type: .text)])
        let tableID = try content.keepRecoveryPassphrase("sample demo passphrase", note: "Fictional note.")
        let table = try #require(content.table(tableID))
        #expect(table.name == "Recovery 2")
        let secret = try #require(table.columns.first { $0.type == .secret })
        #expect(table.rows.first?.values[secret.id] == "sample demo passphrase")
        #expect(content.search("sample demo passphrase", excluding: nil).isEmpty)
    }

    /// Every template passes the table rules and starts with a Text column, which titles its rows.
    @Test(arguments: TableTemplate.allCases)
    func templatesAreValidTables(template: TableTemplate) throws {
        var content = VaultContent()
        let tableID = try content.addTable(name: template.name, columns: template.makeColumns())
        let table = try #require(content.table(tableID))
        #expect(table.columns.first?.type == .text)
        #expect(template.makeColumns().map(\.id) != template.makeColumns().map(\.id))
    }

    @Test func secondCopyGetsANumber() throws {
        var content = VaultContent()
        _ = try content.addTable(name: "Logins", columns: TableTemplate.logins.makeColumns())
        #expect(content.availableTableName("logins") == "logins 2")
        _ = try content.addTable(name: "Logins 2", columns: TableTemplate.logins.makeColumns())
        #expect(content.availableTableName("Logins") == "Logins 3")
        #expect(content.availableTableName("Wi-Fi") == "Wi-Fi")
    }
}

struct SearchTests {
    @Test func searchesTextAndNotesButNeverSecrets() throws {
        var content = VaultContent()
        let site = Column(name: "Website", type: .text), secret = Column(name: "Password", type: .secret), note = Column(name: "Note", type: .note)
        let logins = try content.addTable(name: "Logins", columns: [site, secret, note])
        try content.addRow(to: logins, values: [site.id: "Example Mail", secret.id: "Sample-Trade-01", note.id: "Work account"])
        let other = Column(name: "Network", type: .text)
        let wifi = try content.addTable(name: "Wi-Fi", columns: [other])
        try content.addRow(to: wifi, values: [other.id: "Home WORK network"])

        #expect(content.search("sample-trade").isEmpty)
        #expect(content.search("work").map(\.tableID) == [logins, wifi])
        #expect(content.search("work", excluding: logins).map(\.tableID) == [wifi])
        #expect(content.search("   ").isEmpty)
        #expect(content.table(logins)?.rows(matching: "MAIL").count == 1)
        #expect(content.table(logins)?.rows(matching: "").count == 1)
    }
}
