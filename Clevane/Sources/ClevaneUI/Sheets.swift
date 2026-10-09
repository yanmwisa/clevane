import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VaultCore

struct RestoreRequest: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct VaultSheetView: View {
    let model: AppModel
    let sheet: VaultSheet

    var body: some View {
        content.modelAlert(model)
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .newTable:
            TableEditorSheet(model: model, tableID: nil)
        case .columns(let tableID):
            TableEditorSheet(model: model, tableID: tableID)
        case .renameTable(let tableID):
            RenameTableSheet(model: model, tableID: tableID)
        case .addRow(let tableID):
            RowEditorSheet(model: model, tableID: tableID, rowID: nil)
        case .editRow(let tableID, let rowID):
            RowEditorSheet(model: model, tableID: tableID, rowID: rowID)
        case .changePassword:
            ChangePasswordSheet(model: model)
        case .restore(let url):
            RestoreSheet(model: model, backupURL: url)
        }
    }
}

/// Shared frame of every sheet: serif title, short explanation, body, error line, actions.
struct SheetFrame<Content: View, Actions: View>: View {
    let title: String
    let message: String
    var error: String?
    var width: CGFloat = 480
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.serif(32)).lineLimit(2)
            Text(message).font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            content.padding(.top, 18)
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Palette.danger)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isStaticText)
            }
            Divider().padding(.top, 16)
            HStack(spacing: 8) {
                Spacer()
                actions
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(width: width)
        .background(Palette.sheet)
        .foregroundStyle(Palette.text)
    }
}

// MARK: - Tables and columns

struct TableEditorSheet: View {
    let model: AppModel
    let tableID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var columns: [Column] = [Column(name: "", type: .text)]
    @State private var error: String?
    @State private var pendingDelete: Column?
    @State private var didLoad = false

    private var table: VaultTable? { tableID.flatMap { model.content.table($0) } }

    var body: some View {
        SheetFrame(
            title: table.map { "Columns of \($0.name)" } ?? "New Table",
            message: table == nil
                ? "Name the table, then choose its columns. Each column is Text, Secret or Note."
                : "Rename, retype or reorder columns. Secret values stay hidden in the table.",
            error: error
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if table == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Caps("Start from a template")
                        TemplatePicker { template in
                            name = model.content.availableTableName(template.name)
                            columns = template.makeColumns()
                        }
                    }
                    LabeledField(label: "Table name") {
                        FieldBox { TextField("e.g. Bank Accounts", text: $name).accessibilityLabel("Table name") }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Caps("Columns")
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        columnRow(index: index, column: column)
                    }
                    Button { columns.append(Column(name: "", type: .text)) } label: { Label("Add Column", systemImage: "plus") }
                        .buttonStyle(CapsuleButtonStyle())
                        .padding(.top, 4)
                }
            }
        } actions: {
            if table == nil {
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(CapsuleButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Create Table", action: save).buttonStyle(InkButtonStyle()).keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(CapsuleButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Done", action: save).buttonStyle(InkButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: load)
        .onChange(of: name) { error = nil }
        .onChange(of: columns) { error = nil }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { column in
            Button("Delete", role: .destructive) { columns.removeAll { $0.id == column.id } }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            let count = table?.filledValueCount(in: column.id) ?? 0
            Text("\(count) \(count == 1 ? "value" : "values") will be permanently deleted when you click Done. This cannot be undone.")
        }
    }

    private func columnRow(index: Int, column: Column) -> some View {
        let label = column.name.isEmpty ? "column \(index + 1)" : column.name
        return HStack(spacing: 6) {
            FieldBox {
                TextField("Column name", text: $columns[index].name).accessibilityLabel("Column \(index + 1) name")
            }
            Picker("Type", selection: $columns[index].type) {
                ForEach(allowedTypes(for: column), id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            .disabled(allowedTypes(for: column).count == 1)
            .accessibilityLabel("Column \(index + 1) type")
            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(IconButtonStyle()).disabled(index == 0).accessibilityLabel("Move \(label) up")
            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                .buttonStyle(IconButtonStyle()).disabled(index == columns.count - 1).accessibilityLabel("Move \(label) down")
            Button { requestDelete(column) } label: { Image(systemName: "trash") }
                .buttonStyle(IconButtonStyle()).disabled(columns.count == 1).accessibilityLabel("Delete \(label)")
        }
    }

    /// A saved column cannot switch to or from File (its text or its files would be lost); new columns can be anything.
    private func allowedTypes(for column: Column) -> [ColumnType] {
        switch table?.columns.first(where: { $0.id == column.id })?.type {
        case .file?: [.file]
        case nil: ColumnType.allCases
        default: ColumnType.allCases.filter { $0 != .file }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let table { columns = table.columns }
    }

    private func move(_ index: Int, by step: Int) {
        let target = index + step
        guard columns.indices.contains(target) else { return }
        columns.swapAt(index, target)
    }

    /// A column that holds values asks first: its values go when the change is saved.
    private func requestDelete(_ column: Column) {
        guard columns.count > 1 else { return }
        if (table?.filledValueCount(in: column.id) ?? 0) > 0 {
            pendingDelete = column
        } else {
            columns.removeAll { $0.id == column.id }
        }
    }

    private func save() {
        if let problem = table == nil
            ? ContentRules.tableProblem(name: name, columns: columns, among: model.content.tables)
            : ContentRules.columnsProblem(columns) ?? ContentRules.retypeProblem(from: table?.columns ?? [], to: columns) {
            error = problem.message
            return
        }
        let saved = if let tableID {
            model.saveColumns(columns, of: tableID)
        } else {
            model.createTable(name: name, columns: columns)
        }
        if saved { dismiss() }
    }
}

struct RenameTableSheet: View {
    let model: AppModel
    let tableID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        SheetFrame(title: "Rename Table", message: "Table names are encrypted with the rest of your vault.", error: error, width: 400) {
            LabeledField(label: "Table name") {
                FieldBox { TextField("Table name", text: $name).accessibilityLabel("Table name") }
            }
        } actions: {
            Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(CapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            Button("Rename", action: save).buttonStyle(InkButtonStyle()).keyboardShortcut(.defaultAction)
        }
        .onAppear { name = model.content.table(tableID)?.name ?? "" }
        .onChange(of: name) { error = nil }
    }

    private func save() {
        guard let table = model.content.table(tableID) else { return dismiss() }
        if let problem = ContentRules.tableProblem(name: name, columns: table.columns, among: model.content.tables, excluding: tableID) {
            error = problem.message
            return
        }
        if model.perform({ try $0.renameTable(tableID, to: name) }) != nil { dismiss() }
    }
}

// MARK: - Rows

struct RowEditorSheet: View {
    let model: AppModel
    let tableID: UUID
    let rowID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var values: [UUID: String] = [:]
    @State private var attachments: [UUID: Attachment] = [:]
    @State private var revealedSecrets: Set<UUID> = []
    @State private var error: String?

    private var table: VaultTable? { model.content.table(tableID) }

    var body: some View {
        SheetFrame(
            title: rowID.flatMap { id in table?.rows.first { $0.id == id } }.map { "Edit \(table?.title(of: $0) ?? "Row")" } ?? "Add Row to \(table?.name ?? "Table")",
            message: "Paste or type each value. Secrets are hidden while you type.",
            error: error
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(table?.columns ?? []) { column in
                        LabeledField(label: column.name) { field(for: column) }
                    }
                }
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(CapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            Button(rowID == nil ? "Add Row" : "Save", action: save).buttonStyle(InkButtonStyle()).keyboardShortcut(.defaultAction)
        }
        .onAppear {
            guard let rowID, let row = table?.rows.first(where: { $0.id == rowID }) else { return }
            values = row.values
            attachments = row.attachments
        }
        .onChange(of: values) { error = nil }
        .onChange(of: attachments) { error = nil }
    }

    @ViewBuilder private func field(for column: Column) -> some View {
        let binding = Binding(get: { values[column.id] ?? "" }, set: { values[column.id] = $0 })
        switch column.type {
        case .text:
            FieldBox { TextField(column.name, text: binding).accessibilityLabel(column.name) }
        case .secret:
            HStack(spacing: 6) {
                SecretField(label: column.name, placeholder: column.name, text: binding, reveal: revealBinding(for: column.id))
                Button { suggestPassword(for: column.id) } label: { Image(systemName: "dice") }
                    .buttonStyle(IconButtonStyle())
                    .help("Suggest a strong password")
                    .accessibilityLabel("Suggest a password for \(column.name)")
            }
        case .file:
            FilePicker(model: model, column: column, attachment: Binding(get: { attachments[column.id] }, set: { attachments[column.id] = $0 }))
        case .note:
            TextEditor(text: binding)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 80)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.controlLine, lineWidth: 1))
                .accessibilityLabel(column.name)
        }
    }

    private func revealBinding(for columnID: UUID) -> Binding<Bool> {
        Binding(
            get: { revealedSecrets.contains(columnID) },
            set: { isShown in if isShown { revealedSecrets.insert(columnID) } else { revealedSecrets.remove(columnID) } }
        )
    }

    /// Fills the field and shows it, so the new password can be read before it is saved.
    private func suggestPassword(for columnID: UUID) {
        values[columnID] = StrongPassword.generate()
        revealedSecrets.insert(columnID)
    }

    private func save() {
        if let problem = ContentRules.rowProblem(values, attachments: attachments) {
            error = problem.message
            return
        }
        if model.saveRow(values, attachments: attachments, editing: rowID, in: tableID) { dismiss() }
    }
}

// MARK: - Password and restore

struct ChangePasswordSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirmation = ""

    /// After a Touch ID or Mac password unlock, the current password is not asked: it may be lost.
    private var needsCurrent: Bool { !model.canSetPasswordWithoutCurrent }

    var body: some View {
        SheetFrame(
            title: "Change Master Password",
            message: needsCurrent
                ? "Your vault key stays the same; it is sealed again under the new password. Keep the new one safe: Clevane cannot reset it."
                : "You opened this vault with \(model.quickUnlockKind.name), so the current password is not needed. Clevane asks for \(model.quickUnlockKind.name) once more, then seals your vault under the new password. Keep it safe.",
            width: 440
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if needsCurrent {
                    LabeledField(label: "Current password") {
                        SecretField(label: "Current password", placeholder: "Current master password", text: $current)
                    }
                }
                LabeledField(label: "New password") {
                    SecretField(label: "New password", placeholder: "Choose a long, unique password", text: $newPassword)
                }
                PasswordMeter(password: newPassword)
                LabeledField(label: "Confirm new password") {
                    SecretField(label: "Confirm new password", placeholder: "Enter it again", text: $confirmation)
                }
            }
        } actions: {
            Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(CapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            Button {
                Task { if await save() { dismiss() } }
            } label: {
                if model.isWorking { ProgressView().controlSize(.small) } else { Text("Change Password") }
            }
            .buttonStyle(InkButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(model.isWorking || (needsCurrent && current.isEmpty) || newPassword.isEmpty)
        }
    }

    private func save() async -> Bool {
        needsCurrent
            ? await model.changePassword(current: current, new: newPassword, confirmation: confirmation)
            : await model.setNewPassword(newPassword, confirmation: confirmation)
    }
}

struct RestoreSheet: View {
    let model: AppModel
    let backupURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        SheetFrame(
            title: "Restore a Backup",
            message: "\(backupURL.lastPathComponent) opens as a separate vault, next to your current one. Nothing is replaced. Enter the master password the backup was made with.",
            width: 440
        ) {
            LabeledField(label: "Backup password") {
                SecretField(label: "Backup password", placeholder: "Master password of this backup", text: $password)
            }
        } actions: {
            Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(CapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            Button {
                Task { if await model.restore(backupURL, password: password) { dismiss() } }
            } label: {
                if model.isWorking { ProgressView().controlSize(.small) } else { Text("Restore") }
            }
            .buttonStyle(InkButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(model.isWorking || password.isEmpty)
        }
    }
}

// MARK: - File panels

@MainActor
enum FilePanels {
    static let vaultType = UTType(filenameExtension: "clevane") ?? .data
    static let backupType = UTType(filenameExtension: BackupService.fileExtension) ?? .data

    static func chooseBackupFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Clevane backup"
        panel.message = "Choose a file ending in .\(BackupService.fileExtension), made by Create Backup. Vaults (.clevane) and their .files folders are not backups."
        panel.allowedContentTypes = [backupType]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseBrowserExport() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a password export (CSV) from Chrome, Google, Safari or Firefox"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseAttachment() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a photo or a file to keep in the vault"
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Where an exported file goes, in clear: always the person's choice.
    static func chooseExportDestination(for name: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export a decrypted copy"
        panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The passphrase leaves in clear only to a place the person chose, with the risk stated.
    static func choosePassphraseDestination() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save your passphrase to a file"
        panel.message = "This file holds your passphrase in plain text. Keep it where only you can reach it, such as a USB key. Once your vault exists, Clevane keeps the passphrase inside it and offers to move this file to the Trash."
        panel.nameFieldStringValue = "Clevane passphrase.txt"
        panel.allowedContentTypes = [.plainText]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseVaultFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open a Clevane vault"
        panel.allowedContentTypes = [vaultType]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(startingAt folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose where to keep backups"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        return panel.runModal() == .OK ? panel.url : nil
    }
}
