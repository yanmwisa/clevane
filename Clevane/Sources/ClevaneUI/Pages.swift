import AppKit
import SwiftUI
import VaultCore

/// Serif page heading shared by Backup & Restore and Settings.
struct PageHeading: View {
    let kicker: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caps(kicker)
            Text(title).font(.serif(46))
            Text(subtitle).font(.serifItalic(16)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.text).frame(height: 1) }
        .staggeredEntrance(order: 0)
    }
}

/// Flat white card with a hairline: grouped settings, backups list.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DetailCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CardRow<Trailing: View>: View {
    let title: String
    let detail: String
    var isFirst = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { if !isFirst { Rectangle().fill(Palette.line).frame(height: 1) } }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Get started

/// First screen of an empty vault: a table in one click, then what keeps it safe.
struct StartScreen: View {
    let model: AppModel
    @Binding var sheet: VaultSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeading(kicker: "Get started", title: "Let’s fill your vault.", subtitle: "Three steps. A minute or two.")
                step(1, title: "Create your first table", detail: "Pick a ready-made table, or design your own columns.", order: 1) {
                    VStack(alignment: .leading, spacing: 10) {
                        TemplatePicker { model.createTable(from: $0) }
                        Button { sheet = .newTable } label: { Label("Custom table…", systemImage: "plus") }
                            .buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.text2)
                    }
                }
                step(2, title: "Add what you keep", detail: "Add a row for each login, account or note, or bring the passwords saved in your browser.", order: 2) {
                    ImportButton(model: model)
                }
                step(3, title: "Keep it safe", detail: "Lock any time with ⌘L. Turn on quick unlock and make a backup in a few clicks.", order: 3) {
                    HStack(spacing: 8) {
                        Button { model.open(.settings) } label: { Label("Quick unlock", systemImage: model.quickUnlockKind.symbol) }
                            .buttonStyle(CapsuleButtonStyle())
                        Button { model.open(.backup) } label: { Label("Backup", systemImage: "archivebox") }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }
                Hint(symbol: "questionmark.circle", text: "Once your first table is ready, a short guide shows you around.\nOpen it again any time from the ? button or the Help menu.")
                    .padding(.top, 24)
                    .staggeredEntrance(order: 4)
            }
            .padding(.horizontal, 34)
            .padding(.top, 30)
            .padding(.bottom, 26)
        }
    }

    private func step<Actions: View>(_ number: Int, title: String, detail: String, order: Int, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.serif(22))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Palette.sheet))
                .overlay(Circle().strokeBorder(Palette.line2, lineWidth: 0.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.serif(22))
                Text(detail).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                actions().padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number), \(title)")
        .staggeredEntrance(order: order)
    }
}

/// Opens a browser's CSV export and imports it; shared by Get started and Backup & Restore.
struct ImportButton: View {
    let model: AppModel

    var body: some View {
        Button {
            if let file = FilePanels.chooseBrowserExport() { model.importBrowserExport(from: file) }
        } label: { Label("Import from a Browser…", systemImage: "square.and.arrow.down") }
            .buttonStyle(CapsuleButtonStyle())
    }
}

// MARK: - Backup & Restore

struct BackupScreen: View {
    let model: AppModel
    @Binding var sheet: VaultSheet?
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeading(kicker: "A way back", title: "Your vault. Safely kept.", subtitle: "Keep an encrypted copy somewhere you trust.")
                hero.padding(.top, 20).staggeredEntrance(order: 1)
                HStack {
                    Text("Recent backups").font(.serif(24))
                    Spacer()
                    Text(model.backupFolder.lastPathComponent).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                .padding(.top, 24)
                .padding(.bottom, 10)
                .staggeredEntrance(order: 2)
                backups.staggeredEntrance(order: 3)
                restore.padding(.top, 22).staggeredEntrance(order: 4)
                importFromBrowser.padding(.top, 22).staggeredEntrance(order: 5)
                Divider().padding(.vertical, 16)
                Hint(symbol: "info.circle", text: "A folder synced by another app may upload your backup.\nChoose a local folder or an external drive to keep it offline.")
            }
            .padding(.horizontal, 34)
            .padding(.top, 30)
            .padding(.bottom, 26)
            .id(refresh)
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolTile(systemName: "archivebox", size: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text("A backup you control.").font(.serif(26))
                Text("Save an encrypted copy of \(model.content.name).\nYour master password opens it on another Mac.")
                    .font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Palette.muted)
                HStack {
                    Text(abbreviated(model.backupFolder)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.text2).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Change Folder…") {
                        if let folder = FilePanels.chooseFolder(startingAt: model.backupFolder) {
                            model.chooseBackupFolder(folder)
                            refresh += 1
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                }
                .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.select))
                .padding(.top, 8)
            }
            Spacer(minLength: 12)
            Button {
                model.createBackup()
                refresh += 1
            } label: { Label("Create Backup", systemImage: "square.and.arrow.down") }
                .buttonStyle(InkButtonStyle())
                .padding(.top, 30)
        }
        .padding(18)
        .background(DetailCardBackground())
    }

    @ViewBuilder private var backups: some View {
        let files = Array(model.recentBackups().prefix(5))
        if files.isEmpty {
            Text("No backups in this folder yet.").font(.serifItalic(15)).foregroundStyle(Palette.muted)
        } else {
            Card {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack(spacing: 12) {
                        SymbolTile(systemName: "doc", size: 28, isSoft: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent).font(.system(size: 13, design: .monospaced))
                            Text(details(of: file)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if index == 0 { Caps("Latest").padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(Palette.select)) }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: { Label("Show", systemImage: "arrow.up.right") }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
                        Button { sheet = .restore(file) } label: { Label("Restore", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) } }
                }
            }
        }
    }

    private var importFromBrowser: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import from a browser").font(.serif(24))
                Text("Chrome, Google Password Manager, Safari or Firefox:\nexport your passwords as CSV, then choose the file.").font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Palette.muted)
            }
            Spacer()
            ImportButton(model: model)
        }
    }

    private var restore: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Restore from a backup").font(.serif(24))
                Text("Choose a file named like \(BackupService.backupFileName(on: .now)), made by Create Backup,\nnot a .clevane vault or its .files folder. It opens as a separate vault; yours stays as it is.").font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                if let file = FilePanels.chooseBackupFile() { sheet = .restore(file) }
            } label: { Label("Choose Backup…", systemImage: "arrow.counterclockwise") }
                .buttonStyle(CapsuleButtonStyle())
        }
    }

    private func details(of backup: URL) -> String {
        let date = (try? backup.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount(of: backup)), countStyle: .file)
        return "\(date) · \(size) · Encrypted"
    }

    /// A backup is a package (vault and files) or, for older ones, a single file.
    private func byteCount(of backup: URL) -> Int {
        let files = FileManager.default.enumerator(at: backup, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? [backup]
        return files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
    }

    private func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @Bindable var model: AppModel
    @Binding var sheet: VaultSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeading(kicker: "Make it yours", title: "Settings", subtitle: "A little flexibility. The same protection.")
                group("Unlocking", order: 1) {
                    CardRow(title: "\(model.quickUnlockKind.name) on this Mac", detail: quickUnlockDetail, isFirst: true) {
                        Toggle("\(model.quickUnlockKind.name) on this Mac", isOn: Binding(get: { model.isTouchIDEnabled }, set: { model.setTouchID(enabled: $0) }))
                            .toggleStyle(.switch).labelsHidden()
                            .disabled(!model.isQuickUnlockAvailable)
                    }
                    CardRow(title: "Master password", detail: model.canSetPasswordWithoutCurrent
                        ? "Opened with \(model.quickUnlockKind.name): you can set a new one without the current password."
                        : "Always available, on every Mac. Clevane cannot reset it.") {
                        Button("Change…") { sheet = .changePassword }.buttonStyle(CapsuleButtonStyle())
                    }
                }
                group("Automatic locking", order: 2) {
                    CardRow(title: "After inactivity", detail: "A timeout is always required.", isFirst: true) {
                        Picker("After inactivity", selection: Binding(get: { model.content.settings.autoLockDelay }, set: { model.setAutoLockDelay($0) })) {
                            ForEach(AutoLockDelay.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    CardRow(title: "When your Mac sleeps or locks", detail: "Close access to the vault right away.") { AlwaysOn() }
                    CardRow(title: "When Clevane starts", detail: "Always require authentication before showing your vault.") { AlwaysOn() }
                }
                group("Appearance & clipboard", order: 3) {
                    CardRow(title: "Appearance", detail: "Match the way you like to work.", isFirst: true) {
                        Picker("Appearance", selection: $model.appearance) {
                            ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    CardRow(title: "Clear copied secrets after", detail: "Only if the clipboard still holds what Clevane copied.") {
                        Picker("Clear copied secrets after", selection: Binding(get: { model.content.settings.clipboardClearDelay }, set: { model.setClipboardDelay($0) })) {
                            ForEach(ClipboardClearDelay.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                group("About", order: 4) {
                    CardRow(title: "\(AppInfo.name) \(model.installedVersion)", detail: "Created by \(AppInfo.author). \(AppInfo.license).", isFirst: true) {
                        Button("About…") { AboutPanel.show() }.buttonStyle(CapsuleButtonStyle())
                    }
                    CardRow(title: "Updates", detail: "Looks for a newer version on GitHub. Nothing from your vault is sent.") {
                        Button("Check Now") { Task { await model.checkForUpdates() } }.buttonStyle(CapsuleButtonStyle())
                    }
                    CardRow(title: "Check at launch", detail: "Off by default, so Clevane stays offline.") {
                        Toggle("Check for updates at launch", isOn: $model.checksUpdatesAtLaunch).toggleStyle(.switch).labelsHidden()
                    }
                }
                Text(AppInfo.credits).font(.system(size: 11)).foregroundStyle(Palette.quiet)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 34)
            .padding(.top, 30)
            .padding(.bottom, 26)
        }
    }

    private var quickUnlockDetail: String {
        model.isQuickUnlockAvailable ? "Open the vault without typing. The master password stays the way in on any Mac." : "Not available in this build. Use your master password."
    }

    private func group<Content: View>(_ title: String, order: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Caps(title).padding(.leading, 2)
            Card { content() }
        }
        .padding(.top, 14)
        .staggeredEntrance(order: order)
    }
}

struct AlwaysOn: View {
    var body: some View {
        Label("Always on", systemImage: "lock").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
    }
}
