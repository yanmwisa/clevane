import Foundation

/// One login read from a browser's password export.
public struct ImportedLogin: Equatable, Sendable {
    public let website: String
    public let username: String
    public let password: String
    public let url: String
    public let note: String
}

/// Password exports of Chrome and Google Password Manager (name, url, username, password, note), Safari
/// (Title, URL, Username, Password, Notes, OTPAuth) and Firefox (url, username, password, …). Headers are
/// matched by name, so column order and extra columns do not matter.
public enum BrowserImport {
    /// Exports past this size are refused before parsing: a browser export of 10,000 logins is under 2 MB.
    public static let maximumBytes = 20 * 1024 * 1024

    private static let headerNames: [String: [String]] = [
        "website": ["name", "title"],
        "url": ["url", "login_uri", "origin"],
        "username": ["username", "login_username", "user name"],
        "password": ["password", "login_password"],
        "note": ["note", "notes", "extra"],
    ]

    public static func logins(fromCSV text: String) throws -> [ImportedLogin] {
        let records = CSV.records(in: text)
        guard let header = records.first else { throw VaultError.unrecognizedImport }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func index(of field: String) -> Int? {
            headerNames[field]?.lazy.compactMap { names.firstIndex(of: $0) }.first
        }
        guard let passwordIndex = index(of: "password"), index(of: "url") != nil || index(of: "website") != nil else {
            throw VaultError.unrecognizedImport
        }
        let fields = (website: index(of: "website"), url: index(of: "url"), username: index(of: "username"), note: index(of: "note"))
        return records.dropFirst().compactMap { record in
            func value(_ position: Int?) -> String {
                guard let position, record.indices.contains(position) else { return "" }
                return record[position].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let password = value(passwordIndex), username = value(fields.username), url = value(fields.url)
            guard !password.isEmpty || !username.isEmpty else { return nil }
            let website = value(fields.website).isEmpty ? (URL(string: url)?.host() ?? url) : value(fields.website)
            return ImportedLogin(website: website, username: username, password: password, url: url, note: value(fields.note))
        }
    }
}

extension VaultContent {
    /// Adds a Logins table holding every imported login, in one edit: all or nothing.
    public mutating func importLogins(_ logins: [ImportedLogin], tableName: String) throws -> UUID {
        guard !logins.isEmpty else { throw VaultError.unrecognizedImport }
        let columns = TableTemplate.logins.makeColumns()
        var draft = self
        let tableID = try draft.addTable(name: tableName, columns: columns)
        for login in logins {
            let values = [login.website, login.username, login.password, login.url, login.note]
            _ = try draft.addRow(to: tableID, values: Dictionary(uniqueKeysWithValues: zip(columns.map(\.id), values)))
        }
        self = draft
        return tableID
    }
}

/// RFC 4180 reader: quoted fields may hold commas, line breaks and doubled quotes; CRLF or LF line ends;
/// a leading byte order mark is ignored. Blank lines are skipped.
enum CSV {
    static func records(in text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var isQuoted = false
        var characters = text.drop { $0 == "\u{FEFF}" }.makeIterator()
        var pending = characters.next()

        func endRecord() {
            record.append(field)
            field = ""
            if record != [""] { records.append(record) }
            record = []
        }

        while let character = pending {
            pending = characters.next()
            if isQuoted {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = characters.next()
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": isQuoted = true
            case ",":
                record.append(field)
                field = ""
            case "\n", "\r\n", "\r": endRecord()
            default: field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return records
    }
}
