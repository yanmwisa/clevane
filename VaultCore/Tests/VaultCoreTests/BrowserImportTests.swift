import Testing
@testable import VaultCore

/// Fictional exports in each browser's real header layout.
struct BrowserImportTests {
    @Test func csvReaderFollowsRFC4180() {
        let text = "\u{FEFF}a,\"b, with comma\",\"say \"\"hi\"\"\"\r\n\"multi\nline\",,last\n\n"
        #expect(CSV.records(in: text) == [["a", "b, with comma", "say \"hi\""], ["multi\nline", "", "last"]])
        #expect(CSV.records(in: "x,y") == [["x", "y"]])
        #expect(CSV.records(in: "").isEmpty)
    }

    @Test func chromeAndGoogleExport() throws {
        let text = """
        name,url,username,password,note
        example.com,https://example.com/login,alex.sample,Sample-Pass-01,"Work, shared"
        ,https://mail.example.org/,alex.mail,Sample-Pass-02,
        """
        let logins = try BrowserImport.logins(fromCSV: text)
        #expect(logins.count == 2)
        #expect(logins[0] == ImportedLogin(website: "example.com", username: "alex.sample", password: "Sample-Pass-01", url: "https://example.com/login", note: "Work, shared"))
        #expect(logins[1].website == "mail.example.org")
    }

    @Test func safariExport() throws {
        let text = "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://example.com,alex.sample,Sample-Pass-03,,\n"
        #expect(try BrowserImport.logins(fromCSV: text).first?.password == "Sample-Pass-03")
    }

    @Test func firefoxExport() throws {
        let text = """
        "url","username","password","httpRealm","formActionOrigin","guid","timeCreated","timeLastUsed","timePasswordChanged"
        "https://shop.example.net","alex.shop","Sample-Pass-04",,"https://shop.example.net","{0000}","1","1","1"
        """
        let login = try #require(try BrowserImport.logins(fromCSV: text).first)
        #expect(login.website == "shop.example.net")
        #expect(login.username == "alex.shop")
    }

    @Test func unrelatedFilesAreRefused() {
        #expect(throws: VaultError.unrecognizedImport) { try BrowserImport.logins(fromCSV: "date,amount\n2026-10-08,12\n") }
        #expect(throws: VaultError.unrecognizedImport) { try BrowserImport.logins(fromCSV: "") }
    }

    /// One edit, all or nothing: a table named like an existing one fails without leaving half a table behind.
    @Test func importIsAllOrNothing() throws {
        var content = VaultContent()
        let logins = [ImportedLogin(website: "example.com", username: "alex.sample", password: "Sample-Pass-01", url: "", note: "")]
        let tableID = try content.importLogins(logins, tableName: "Imported Logins")
        #expect(content.table(tableID)?.rows.count == 1)
        #expect(throws: VaultError.invalidContent(.duplicateTableName)) { try content.importLogins(logins, tableName: "Imported Logins") }
        #expect(content.tables.count == 1)
        #expect(throws: VaultError.unrecognizedImport) { try content.importLogins([], tableName: "Other") }
    }
}
