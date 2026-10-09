import Foundation

public enum ColumnType: String, Codable, CaseIterable, Sendable {
    case text, secret, note, file

    public var label: String {
        switch self {
        case .text: "Text"
        case .secret: "Secret"
        case .note: "Note"
        case .file: "File"
        }
    }
}

public struct Column: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: ColumnType

    public init(id: UUID = UUID(), name: String, type: ColumnType) {
        self.id = id
        self.name = name
        self.type = type
    }
}

/// Values are keyed by column identifier, so renaming or reordering a column never touches them.
/// Text, Secret and Note columns hold `values`; File columns hold `attachments`.
public struct Row: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var values: [UUID: String]
    public var attachments: [UUID: Attachment]

    public init(id: UUID = UUID(), values: [UUID: String], attachments: [UUID: Attachment] = [:]) {
        self.id = id
        self.values = values
        self.attachments = attachments
    }

    /// Vaults written before File columns existed have no attachments key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        values = try container.decode([UUID: String].self, forKey: .values)
        attachments = try container.decodeIfPresent([UUID: Attachment].self, forKey: .attachments) ?? [:]
    }
}

public struct VaultTable: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var columns: [Column]
    public var rows: [Row]

    public init(id: UUID = UUID(), name: String, columns: [Column], rows: [Row] = []) {
        self.id = id
        self.name = name
        self.columns = columns
        self.rows = rows
    }

    /// Title of a row: its first Text column, otherwise "Row N".
    public func title(of row: Row) -> String {
        let titleColumn = columns.first { $0.type == .text }
        let title = titleColumn.flatMap { row.values[$0.id] }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard title.isEmpty else { return title }
        let position = (rows.firstIndex { $0.id == row.id } ?? rows.count) + 1
        return "Row \(position)"
    }

    /// Files kept in this table's File columns; deleting the table deletes them too.
    public var attachmentCount: Int {
        rows.reduce(0) { $0 + $1.attachments.count }
    }

    public func filledValueCount(in columnID: UUID) -> Int {
        rows.filter { $0.attachments[columnID] != nil || !($0.values[columnID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

public enum AutoLockDelay: Int, Codable, CaseIterable, Sendable {
    case oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900

    public var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

public enum ClipboardClearDelay: Int, Codable, CaseIterable, Sendable {
    case thirtySeconds = 30, sixtySeconds = 60

    public var label: String { "\(rawValue) seconds" }
}

/// Settings live inside the encrypted vault, so nobody can relax locking without unlocking first.
/// Defaults: lock after 5 minutes, clear copied secrets after 30 seconds.
public struct VaultSettings: Codable, Equatable, Sendable {
    public var autoLockDelay: AutoLockDelay
    public var clipboardClearDelay: ClipboardClearDelay

    public init(autoLockDelay: AutoLockDelay = .fiveMinutes, clipboardClearDelay: ClipboardClearDelay = .thirtySeconds) {
        self.autoLockDelay = autoLockDelay
        self.clipboardClearDelay = clipboardClearDelay
    }
}

public struct VaultContent: Codable, Equatable, Sendable {
    public static let defaultName = "Personal Vault"

    /// Encrypted like everything else: the file name on disk never reveals it.
    public var name: String
    public var tables: [VaultTable]
    public var settings: VaultSettings

    public init(name: String = VaultContent.defaultName, tables: [VaultTable] = [], settings: VaultSettings = VaultSettings()) {
        self.name = name
        self.tables = tables
        self.settings = settings
    }

    public func table(_ id: UUID) -> VaultTable? {
        tables.first { $0.id == id }
    }
}

// MARK: - Rules (pure decisions, tested alone)

public enum ContentRules {
    public static func columnsProblem(_ columns: [Column]) -> ContentProblem? {
        guard !columns.isEmpty else { return .noColumns }
        let names = columns.map { normalized($0.name) }
        if names.contains(where: \.isEmpty) { return .emptyColumnName }
        return Set(names).count == names.count ? nil : .duplicateColumnName
    }

    public static func tableProblem(name: String, columns: [Column], among tables: [VaultTable], excluding tableID: UUID? = nil) -> ContentProblem? {
        let wanted = normalized(name)
        guard !wanted.isEmpty else { return .emptyTableName }
        let isTaken = tables.contains { $0.id != tableID && normalized($0.name) == wanted }
        return isTaken ? .duplicateTableName : columnsProblem(columns)
    }

    public static func rowProblem(_ values: [UUID: String], attachments: [UUID: Attachment] = [:]) -> ContentProblem? {
        let hasValue = values.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasValue || !attachments.isEmpty ? nil : .emptyRow
    }

    /// A column cannot become a File column or stop being one: its text values or its files would be lost.
    public static func retypeProblem(from current: [Column], to proposed: [Column]) -> ContentProblem? {
        let currentTypes = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.type) })
        let changesFileType = proposed.contains { column in
            guard let before = currentTypes[column.id] else { return false }
            return (before == .file) != (column.type == .file)
        }
        return changesFileType ? .fileTypeChange : nil
    }

    /// Names compare without case or surrounding spaces, so "Bank" and " bank " are the same table.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Structural check run on every load: a file that decrypts but breaks these rules is treated as damaged.
    static func isConsistent(_ content: VaultContent) -> Bool {
        let tableIDs = content.tables.map(\.id)
        guard Set(tableIDs).count == tableIDs.count else { return false }
        return content.tables.allSatisfy { table in
            let columnIDs = Set(table.columns.map(\.id))
            let rowIDs = table.rows.map(\.id)
            return columnIDs.count == table.columns.count
                && Set(rowIDs).count == rowIDs.count
                && table.rows.allSatisfy { Set($0.values.keys).isSubset(of: columnIDs) && Set($0.attachments.keys).isSubset(of: columnIDs) }
        }
    }
}

// MARK: - Edits (each one validates before it changes anything)

public extension VaultContent {
    @discardableResult
    mutating func addTable(name: String, columns: [Column]) throws -> UUID {
        if let problem = ContentRules.tableProblem(name: name, columns: columns, among: tables) {
            throw VaultError.invalidContent(problem)
        }
        let cleanColumns = columns.map { Column(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), type: $0.type) }
        let table = VaultTable(name: name.trimmingCharacters(in: .whitespacesAndNewlines), columns: cleanColumns)
        tables.append(table)
        return table.id
    }

    mutating func renameVault(to name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleanName.isEmpty ? VaultContent.defaultName : cleanName
    }

    mutating func renameTable(_ tableID: UUID, to name: String) throws {
        let index = try tableIndex(tableID)
        if let problem = ContentRules.tableProblem(name: name, columns: tables[index].columns, among: tables, excluding: tableID) {
            throw VaultError.invalidContent(problem)
        }
        tables[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func deleteTable(_ tableID: UUID) throws {
        tables.remove(at: try tableIndex(tableID))
    }

    /// Replaces the column list. Values of columns that disappear are deleted with them;
    /// the interface asks for confirmation first when such a column holds values.
    mutating func setColumns(_ columns: [Column], of tableID: UUID) throws {
        let index = try tableIndex(tableID)
        if let problem = ContentRules.columnsProblem(columns) ?? ContentRules.retypeProblem(from: tables[index].columns, to: columns) {
            throw VaultError.invalidContent(problem)
        }
        let kept = Set(columns.map(\.id))
        tables[index].columns = columns.map { Column(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), type: $0.type) }
        for rowIndex in tables[index].rows.indices {
            tables[index].rows[rowIndex].values = tables[index].rows[rowIndex].values.filter { kept.contains($0.key) }
            tables[index].rows[rowIndex].attachments = tables[index].rows[rowIndex].attachments.filter { kept.contains($0.key) }
        }
    }

    @discardableResult
    mutating func addRow(to tableID: UUID, values: [UUID: String], attachments: [UUID: Attachment] = [:]) throws -> UUID {
        let index = try tableIndex(tableID)
        let cell = try cleanCells(values, attachments, for: tables[index])
        let row = Row(values: cell.values, attachments: cell.attachments)
        tables[index].rows.append(row)
        return row.id
    }

    /// Replaces the whole row: values and files not passed are removed.
    mutating func updateRow(_ rowID: UUID, in tableID: UUID, values: [UUID: String], attachments: [UUID: Attachment]) throws {
        let index = try tableIndex(tableID)
        guard let rowIndex = tables[index].rows.firstIndex(where: { $0.id == rowID }) else {
            throw VaultError.invalidContent(.unknownRow)
        }
        let cell = try cleanCells(values, attachments, for: tables[index])
        tables[index].rows[rowIndex].values = cell.values
        tables[index].rows[rowIndex].attachments = cell.attachments
    }

    mutating func deleteRow(_ rowID: UUID, in tableID: UUID) throws {
        let index = try tableIndex(tableID)
        guard let rowIndex = tables[index].rows.firstIndex(where: { $0.id == rowID }) else {
            throw VaultError.invalidContent(.unknownRow)
        }
        tables[index].rows.remove(at: rowIndex)
    }

    private func tableIndex(_ tableID: UUID) throws -> Int {
        guard let index = tables.firstIndex(where: { $0.id == tableID }) else {
            throw VaultError.invalidContent(.unknownTable)
        }
        return index
    }

    /// Keeps text only in Text, Secret and Note columns and files only in File columns, and drops empty
    /// values, so the file never stores blanks or a value in a column that cannot show it.
    private func cleanCells(_ values: [UUID: String], _ attachments: [UUID: Attachment], for table: VaultTable) throws -> (values: [UUID: String], attachments: [UUID: Attachment]) {
        let textColumns = Set(table.columns.filter { $0.type != .file }.map(\.id))
        let fileColumns = Set(table.columns.filter { $0.type == .file }.map(\.id))
        let keptValues = values.filter { textColumns.contains($0.key) && !$0.value.isEmpty }
        let keptAttachments = attachments.filter { fileColumns.contains($0.key) }
        if let problem = ContentRules.rowProblem(keptValues, attachments: keptAttachments) { throw VaultError.invalidContent(problem) }
        return (keptValues, keptAttachments)
    }
}
