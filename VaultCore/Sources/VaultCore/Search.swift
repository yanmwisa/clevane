import Foundation

/// A row found by search, with the table it lives in.
public struct SearchHit: Equatable, Sendable {
    public let tableID: UUID
    public let rowID: UUID
}

extension VaultTable {
    /// Rows whose Text or Note values, or file names, contain `term`, ignoring case. Secret values are never
    /// searched, so typing a password into search reveals nothing about which row holds it.
    public func rows(matching term: String) -> [Row] {
        let wanted = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return rows }
        let searchable = columns.filter { $0.type != .secret }
        return rows.filter { row in
            searchable.contains { column in
                let text = row.values[column.id] ?? row.attachments[column.id]?.name ?? ""
                return text.lowercased().contains(wanted)
            }
        }
    }
}

extension VaultContent {
    /// Matches in every table except `excluded` (the one already on screen), in sidebar order.
    public func search(_ term: String, excluding excluded: UUID? = nil) -> [SearchHit] {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return tables.filter { $0.id != excluded }.flatMap { table in
            table.rows(matching: term).map { SearchHit(tableID: table.id, rowID: $0.id) }
        }
    }
}
