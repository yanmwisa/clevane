import SwiftUI
import VaultCore

enum VaultSheet: Identifiable {
    case newTable
    case columns(UUID)
    case renameTable(UUID)
    case addRow(UUID)
    case editRow(UUID, UUID)
    case changePassword
    case restore(URL)

    var id: String {
        switch self {
        case .newTable: "newTable"
        case .columns(let table): "columns-\(table)"
        case .renameTable(let table): "rename-\(table)"
        case .addRow(let table): "addRow-\(table)"
        case .editRow(let table, let row): "editRow-\(table)-\(row)"
        case .changePassword: "changePassword"
        case .restore(let url): "restore-\(url.path)"
        }
    }
}

/// Destructive confirmations, each stating what will be lost.
enum Confirmation: Identifiable {
    case deleteTable(VaultTable)
    case deleteRow(tableID: UUID, rowID: UUID, title: String)
    case trashImportedFile(URL)
    case trashPassphraseFile(URL, isKeptInVault: Bool)

    var id: String {
        switch self {
        case .deleteTable(let table): "table-\(table.id)"
        case .deleteRow(_, let rowID, _): "row-\(rowID)"
        case .trashImportedFile(let file), .trashPassphraseFile(let file, _): "trash-\(file.path)"
        }
    }

    var actionTitle: String {
        switch self {
        case .deleteTable, .deleteRow: "Delete"
        case .trashImportedFile, .trashPassphraseFile: "Move to Trash"
        }
    }

    var cancelTitle: String {
        switch self {
        case .deleteTable, .deleteRow: "Cancel"
        case .trashImportedFile, .trashPassphraseFile: "Keep the File"
        }
    }
}

struct VaultView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model, sheet: $model.sheet, confirmation: $model.confirmation)
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 300)
        } detail: {
            detail
                .background(Palette.window)
        }
        .sheet(item: $model.sheet) { sheet in
            VaultSheetView(model: model, sheet: sheet)
        }
        .confirmationDialog(confirmationTitle, isPresented: isConfirming, titleVisibility: .visible, presenting: model.confirmation) { pending in
            Button(pending.actionTitle, role: .destructive) { confirm(pending) }
            Button(pending.cancelTitle, role: .cancel) {}
        } message: { pending in
            Text(confirmationMessage(pending))
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .table:
            if let table = model.currentTable {
                TableScreen(model: model, table: table, sheet: $model.sheet, confirmation: $model.confirmation)
            }
        case .start:
            StartScreen(model: model, sheet: $model.sheet)
        case .backup:
            BackupScreen(model: model, sheet: $model.sheet)
        case .settings:
            SettingsScreen(model: model, sheet: $model.sheet)
        case nil:
            EmptyView()
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } })
    }

    private var confirmationTitle: String {
        switch model.confirmation {
        case .deleteTable(let table): "Delete “\(table.name)”?"
        case .deleteRow(_, _, let title): "Delete “\(title)”?"
        case .trashImportedFile(let file), .trashPassphraseFile(let file, _): "Move “\(file.lastPathComponent)” to the Trash?"
        case nil: ""
        }
    }

    private func confirmationMessage(_ pending: Confirmation) -> String {
        switch pending {
        case .deleteTable(let table):
            "Everything in this table will be permanently deleted: \(Self.contents(of: table)). This cannot be undone."
        case .deleteRow:
            "This row and its values will be permanently deleted. This cannot be undone."
        case .trashImportedFile:
            "Your passwords are now encrypted in Clevane. This export still holds them in plain text."
        case .trashPassphraseFile(_, true):
            "Your passphrase is now kept, encrypted, in the Recovery table. This file still holds it in plain text."
        case .trashPassphraseFile(_, false):
            "This file holds an earlier passphrase in plain text, not the one this vault uses."
        }
    }

    /// What a table holds, in words: "3 rows", or "3 rows and 2 files".
    private static func contents(of table: VaultTable) -> String {
        let rows = "\(table.rows.count) \(table.rows.count == 1 ? "row" : "rows")"
        let files = table.attachmentCount
        return files == 0 ? rows : "\(rows) and \(files) \(files == 1 ? "file" : "files")"
    }

    private func confirm(_ pending: Confirmation) {
        switch pending {
        case .deleteTable(let table): model.deleteTable(table.id)
        case .deleteRow(let tableID, let rowID, _): model.deleteRow(rowID, in: tableID)
        case .trashImportedFile(let file), .trashPassphraseFile(let file, _): model.moveToTrash(file)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    let model: AppModel
    @Binding var sheet: VaultSheet?
    @Binding var confirmation: Confirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clevane").font(.serif(28)).padding(.horizontal, 10)
            Text(model.content.name).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.horizontal, 10).padding(.top, 4)
            Caps("Tables").padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 7)
                .guideStop(.tables, model: model)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.content.tables) { table in
                        SidebarItem(isSelected: model.section == .table(table.id), title: table.name, count: table.rows.count) {
                            MonogramTile(name: table.name)
                        } action: {
                            model.open(.table(table.id))
                        }
                        .contextMenu { TableActions(table: table, sheet: $sheet, confirmation: $confirmation) }
                    }
                    if model.content.tables.isEmpty {
                        Text("No tables yet.").font(.serifItalic(14)).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity, alignment: .top)
            Caps("Your vault").padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 7)
            if model.content.tables.isEmpty {
                SidebarItem(isSelected: model.section == .start, title: "Get started") {
                    SymbolTile(systemName: "flag")
                } action: { model.open(.start) }
            }
            SidebarItem(isSelected: model.section == .backup, title: "Backup & Restore") {
                SymbolTile(systemName: "archivebox")
            } action: { model.open(.backup) }
                .guideStop(.backup, model: model)
            SidebarItem(isSelected: model.section == .settings, title: "Settings") {
                SymbolTile(systemName: "gearshape")
            } action: { model.open(.settings) }
                .guideStop(.settings, model: model)
            Text("On this Mac.\nLocks automatically.")
                .font(.serifItalic(14)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 10)
            Divider()
            HStack {
                Button { sheet = .newTable } label: { Label("New Table", systemImage: "plus") }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text2)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .guideStop(.newTable, model: model)
                Spacer()
                Button { model.showGuide() } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(IconButtonStyle())
                    .help("Guide")
                    .accessibilityLabel("Open the guide")
                    .guideStop(.guide, model: model)
                Button { model.lock() } label: { Image(systemName: "lock") }
                    .buttonStyle(IconButtonStyle())
                    .help("Lock vault (⌘L)")
                    .accessibilityLabel("Lock vault")
                    .keyboardShortcut("l", modifiers: [.command])
                    .guideStop(.lock, model: model)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// Rename, edit columns, delete: the same actions from the sidebar's context menu and the table's toolbar menu.
/// Delete asks first, saying what the table holds.
struct TableActions: View {
    let table: VaultTable
    @Binding var sheet: VaultSheet?
    @Binding var confirmation: Confirmation?

    var body: some View {
        Button("Rename Table…") { sheet = .renameTable(table.id) }
        Button("Edit Columns…") { sheet = .columns(table.id) }
        Divider()
        Button("Delete Table…", role: .destructive) { confirmation = .deleteTable(table) }
    }
}

struct SidebarItem<Icon: View>: View {
    let isSelected: Bool
    let title: String
    var count: Int?
    @ViewBuilder let icon: Icon
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(title).lineLimit(1).truncationMode(.tail)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Palette.text : Palette.text2)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)").font(.serifItalic(15)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected || isHovered ? Palette.select : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(count.map { "\($0) rows" } ?? "")
    }
}

// MARK: - Table screen

struct TableScreen: View {
    let model: AppModel
    let table: VaultTable
    @Binding var sheet: VaultSheet?
    @Binding var confirmation: Confirmation?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleRows: [Row] {
        table.rows(matching: model.searchText)
    }

    private var otherTableHits: [SearchHit] {
        model.content.search(model.searchText, excluding: table.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            tablePane
            if let row = model.selectedRow {
                RowDetail(model: model, table: table, row: row, sheet: $sheet, confirmation: $confirmation)
                    .guideStop(.rowDetail, model: model)
                    .id("\(row.id)-\(model.detailEntrance)")
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                EmptyDetail(table: table)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.12), value: model.detailEntrance)
    }

    private var tablePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            VStack(alignment: .leading, spacing: 6) {
                Caps("\(table.columns.count) \(table.columns.count == 1 ? "column" : "columns") · \(table.rows.count) \(table.rows.count == 1 ? "row" : "rows")")
                Text(table.name).font(.serif(56)).lineLimit(1).truncationMode(.tail)
            }
            .padding(.top, 12)
            .padding(.bottom, 14)
            .id("heading-\(table.id)")
            .staggeredEntrance(order: 0)
            Rectangle().fill(Palette.text).frame(height: 1)
            columnHeader
            rows
            if !otherTableHits.isEmpty {
                OtherTableResults(model: model, hits: otherTableHits)
            }
            footer
        }
        .padding(.leading, 28)
        .padding(.trailing, 22)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            Menu {
                TableActions(table: table, sheet: $sheet, confirmation: $confirmation)
            } label: {
                Label("Table options", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rename, edit columns or delete this table")
            .accessibilityLabel("Table options")
            Button { sheet = .columns(table.id) } label: { Label("Columns", systemImage: "rectangle.split.3x1") }
                .buttonStyle(CapsuleButtonStyle())
                .fixedSize()
                .guideStop(.columns, model: model)
            FieldBox(isFocused: isSearchFocused, isPill: true) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
                    TextField("Search", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                        .focused($isSearchFocused)
                        .accessibilityLabel("Search \(table.name)")
                    Text("⌘K").font(.system(size: 11)).foregroundStyle(Palette.quiet)
                }
            }
            .frame(minWidth: 120, maxWidth: 200)
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            Button { sheet = .addRow(table.id) } label: { Label("Add Row", systemImage: "plus") }
                .buttonStyle(InkButtonStyle())
                .fixedSize()
                .keyboardShortcut("n", modifiers: .command)
                .guideStop(.addRow, model: model)
        }
        .frame(height: 40)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            ForEach(table.columns) { column in
                Caps(column.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(column.name), \(column.type.label)")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    @ViewBuilder private var rows: some View {
        if table.rows.isEmpty {
            EmptyRows(message: "No rows yet in \(table.name).") {
                Button { sheet = .addRow(table.id) } label: { Label("Add Row", systemImage: "plus") }
                    .buttonStyle(CapsuleButtonStyle())
            }
        } else if visibleRows.isEmpty {
            EmptyRows(message: "No rows match your search.") { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                        TableRowView(table: table, row: row, isSelected: row.id == model.selectedRow?.id, hidesDivider: index == 0) {
                            model.select(row.id)
                        }
                        .id("\(table.id)-\(row.id)")
                        .staggeredEntrance(order: min(index, 10) + 1)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
        }
    }

    private var footer: some View {
        HStack {
            Text("Secrets stay folded in the table.")
            Spacer()
            Text("\(visibleRows.count) \(visibleRows.count == 1 ? "row" : "rows")")
        }
        .font(.serifItalic(15))
        .foregroundStyle(Palette.muted)
        .frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line2).frame(height: 0.5) }
    }

    private func moveSelection(by step: Int) -> KeyPress.Result {
        let rows = visibleRows
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == model.selectedRow?.id } ?? 0
        model.select(rows[max(0, min(rows.count - 1, current + step))].id)
        return .handled
    }
}

/// Search results from the other tables, under the current table's rows. A click opens the row where it lives.
struct OtherTableResults: View {
    let model: AppModel
    let hits: [SearchHit]
    private static let shownLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Caps("In other tables · \(hits.count)").padding(.top, 12).padding(.bottom, 4)
            ForEach(hits.prefix(Self.shownLimit), id: \.rowID) { hit in
                if let table = model.content.table(hit.tableID), let row = table.rows.first(where: { $0.id == hit.rowID }) {
                    Button { model.openSearchResult(hit) } label: {
                        HStack(spacing: 10) {
                            MonogramTile(name: table.name, size: 22)
                            Text(table.title(of: row)).font(.system(size: 13, weight: .medium))
                            Text(table.name).font(.system(size: 12)).foregroundStyle(Palette.muted)
                            Spacer()
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Palette.quiet).accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(table.title(of: row)), in \(table.name)")
                }
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

struct TableRowView: View {
    let table: VaultTable
    let row: Row
    let isSelected: Bool
    let hidesDivider: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ForEach(Array(table.columns.enumerated()), id: \.element.id) { index, column in
                    cell(for: column, isFirst: index == 0).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Palette.sheet : (isHovered ? Palette.select : .clear))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line2, lineWidth: 0.5)
                        }
                    }
                    .shadow(color: .black.opacity(isSelected ? 0.04 : 0), radius: 1, y: 1)
            }
            .overlay(alignment: .top) {
                if !isSelected && !hidesDivider { Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityLabel(table.title(of: row))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func cell(for column: Column, isFirst: Bool) -> some View {
        if column.type == .file, !isFirst {
            fileCell(row.attachments[column.id])
        } else {
            textCell(for: column, isFirst: isFirst)
        }
    }

    @ViewBuilder private func fileCell(_ attachment: Attachment?) -> some View {
        if let attachment {
            Label(attachment.name, systemImage: attachment.symbol)
                .font(.system(size: 13)).foregroundStyle(Palette.text2).lineLimit(1)
        }
    }

    @ViewBuilder private func textCell(for column: Column, isFirst: Bool) -> some View {
        let value = column.type == .file ? row.attachments[column.id]?.name ?? "" : row.values[column.id] ?? ""
        let shown = column.type == .secret && !value.isEmpty ? "••••••••" : value.components(separatedBy: .newlines).first ?? ""
        if isFirst {
            HStack(spacing: 12) {
                MonogramTile(name: table.name, size: 28, isSoft: !isSelected)
                Text(shown).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            }
        } else {
            Text(shown)
                .font(.system(size: column.type == .secret ? 12 : 13.5))
                .tracking(column.type == .secret ? 2.6 : 0)
                .foregroundStyle(column.type == .text ? Palette.text : Palette.quiet)
                .lineLimit(1)
        }
    }
}

struct EmptyRows<Action: View>: View {
    let message: String
    @ViewBuilder let action: Action

    var body: some View {
        VStack(spacing: 16) {
            Text(message).font(.serifItalic(18)).foregroundStyle(Palette.muted)
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyDetail: View {
    let table: VaultTable

    var body: some View {
        Text(table.rows.isEmpty ? "Add a row to see\nits details here." : "Select a row.")
            .font(.serifItalic(18)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            .frame(width: 330)
            .frame(maxHeight: .infinity)
            .background(DetailCardBackground())
            .padding(8)
    }
}

struct DetailCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Palette.sheet)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line2, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}

// MARK: - Row detail

struct RowDetail: View {
    let model: AppModel
    let table: VaultTable
    let row: Row
    @Binding var sheet: VaultSheet?
    @Binding var confirmation: Confirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Caps(table.name)
                Spacer()
                Menu {
                    Button("Edit Row") { sheet = .editRow(table.id, row.id) }
                    Divider()
                    Button("Delete Row…", role: .destructive) {
                        confirmation = .deleteRow(tableID: table.id, rowID: row.id, title: table.title(of: row))
                    }
                } label: {
                    Label("Row options", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Row options")
            }
            MonogramTile(name: table.name, size: 52).padding(.top, 20)
            Text(table.title(of: row)).font(.serif(40)).lineLimit(2).minimumScaleFactor(0.6).padding(.top, 18)
            Text("Row \((table.rows.firstIndex { $0.id == row.id } ?? 0) + 1) of \(table.rows.count)")
                .font(.serifItalic(16)).foregroundStyle(Palette.muted).padding(.top, 2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(table.columns.enumerated()), id: \.element.id) { index, column in
                        Group {
                            if column.type == .file {
                                FileField(model: model, column: column, attachment: row.attachments[column.id])
                            } else {
                                DetailField(model: model, column: column, value: row.values[column.id] ?? "")
                            }
                        }
                        .staggeredEntrance(order: index + 2)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            }
            .padding(.top, 22)
            .scrollIndicators(.automatic)
            HStack {
                Label("Encrypted at rest.", systemImage: "lock").font(.serifItalic(15)).foregroundStyle(Palette.muted)
                Spacer()
                Button { sheet = .editRow(table.id, row.id) } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(CapsuleButtonStyle())
                    .keyboardShortcut("e", modifiers: .command)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DetailCardBackground())
        .padding(8)
    }
}

struct DetailField: View {
    let model: AppModel
    let column: Column
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRevealed: Bool { model.revealedColumns.contains(column.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Caps(column.name)
                Text("· \(column.type.label.uppercased())").font(.system(size: 10)).tracking(1.2).foregroundStyle(Palette.quiet)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                valueText.frame(maxWidth: .infinity, alignment: .leading)
                if column.type == .secret {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { model.toggleReveal(column.id) }
                    } label: { Image(systemName: isRevealed ? "eye.slash" : "eye") }
                        .buttonStyle(IconButtonStyle(isActive: isRevealed))
                        .disabled(value.isEmpty)
                        .accessibilityLabel(isRevealed ? "Hide \(column.name)" : "Show \(column.name)")
                }
                CopyButton(accessibilityName: "Copy \(column.name)") { model.copy(value, label: column.name) }
                    .disabled(value.isEmpty)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    @ViewBuilder private var valueText: some View {
        if value.isEmpty {
            Text("Empty").font(.serifItalic(14)).foregroundStyle(Palette.quiet)
        } else if column.type == .secret && !isRevealed {
            Text("••••••••••").font(.system(size: 13)).tracking(3).foregroundStyle(Palette.text2)
                .accessibilityLabel("Hidden")
                .transition(.opacity)
        } else if column.type == .note {
            Text(value).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.text2).textSelection(.enabled)
        } else {
            Text(value).font(.value).textSelection(.enabled)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
    }
}
