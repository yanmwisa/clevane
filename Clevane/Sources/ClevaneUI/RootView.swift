import SwiftUI
import VaultCore

/// Window content: one of the four moments (Welcome, Create, Unlock, Vault), plus alerts and the toast.
public struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            Palette.window.ignoresSafeArea()
            switch model.screen {
            case .welcome: WelcomeView(model: model)
            case .create: CreateVaultView(model: model)
            case .unlock: UnlockView(model: model)
            case .vault: VaultView(model: model)
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: model.screen)
        .frame(minWidth: 1000, minHeight: 640)
        .foregroundStyle(Palette.text)
        .tint(Palette.text)
        .overlay(alignment: .bottom) { ToastView(message: model.toast) }
        .modelAlert(model)
    }
}

/// Errors the model reports. A sheet hides the window's alerts, so every sheet host carries this too:
/// otherwise an error raised in a sheet only showed once the sheet was closed.
struct ModelAlert: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .alert(item: $model.alert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .alert("Clevane \(model.updateOffer?.version.description ?? "") is available", isPresented: isOfferingUpdate, presenting: model.updateOffer) { release in
                Button("Download") { NSWorkspace.shared.open(release.page) }
                Button("Later", role: .cancel) {}
            } message: { _ in
                Text("You have version \(model.installedVersion). The download page opens in your browser.")
            }
    }

    private var isOfferingUpdate: Binding<Bool> {
        Binding(get: { model.updateOffer != nil }, set: { if !$0 { model.updateOffer = nil } })
    }
}

extension View {
    func modelAlert(_ model: AppModel) -> some View {
        modifier(ModelAlert(model: model))
    }
}

extension Appearance {
    /// nil follows the Mac's own setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct ToastView: View {
    let message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let message {
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Palette.ink))
                    .padding(.bottom, 22)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: message)
    }
}

// MARK: - Onboarding

/// Left glass panel of Welcome and Create Vault.
struct IntroPanel: View {
    let title: String
    let accent: String
    let paragraph: String
    var footer: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clevane").font(.serif(28))
            AppIconTile().padding(.top, 44)
            (Text(title) + Text("\n") + Text(accent).italic().foregroundStyle(Palette.muted))
                .font(.serif(56))
                .lineSpacing(-4)
                .padding(.top, 28)
            Text(paragraph)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Palette.muted)
                .padding(.top, 16)
            Spacer(minLength: 20)
            footer
        }
        .padding(.top, 58)
        .padding(.horizontal, 36)
        .padding(.bottom, 30)
        .frame(width: 412, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line2, lineWidth: 0.5))
        .padding(8)
        .staggeredEntrance(order: 0)
    }
}

struct WelcomeView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            IntroPanel(
                title: "Your secrets.",
                accent: "Your space.",
                paragraph: "A private home for your passwords,\nbuilt to stay with you, on your Mac.",
                footer: AnyView(Label("Your Mac. Your control.".uppercased(), systemImage: "internaldrive")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.muted))
            )
            VStack(alignment: .leading, spacing: 0) {
                Caps("Welcome to Clevane").staggeredEntrance(order: 1)
                Text("A little more\npeace of mind.")
                    .font(.serif(46))
                    .padding(.top, 14)
                    .staggeredEntrance(order: 2)
                Text("Keep your logins and private notes together,\ninside your own encrypted vault.")
                    .font(.system(size: 14)).lineSpacing(4).foregroundStyle(Palette.muted)
                    .padding(.top, 14)
                    .staggeredEntrance(order: 3)
                VStack(spacing: 10) {
                    if model.isQuickUnlockAvailable {
                        Button { Task { await model.startQuickCreate() } } label: {
                            Label("Create with \(model.quickUnlockKind.name)", systemImage: model.quickUnlockKind.symbol).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(InkButtonStyle(isWide: true))
                        .keyboardShortcut(.defaultAction)
                        Button { model.startPasswordCreate() } label: {
                            Label("Create with a password", systemImage: "key").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(CapsuleButtonStyle(isWide: true))
                    } else {
                        Button { model.startPasswordCreate() } label: {
                            Label("Create a vault", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(InkButtonStyle(isWide: true))
                        .keyboardShortcut(.defaultAction)
                    }
                    Button { chooseBackupToRestore() } label: {
                        Label("Restore a backup", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CapsuleButtonStyle(isWide: true))
                }
                .controlSize(.large)
                .frame(width: 360)
                .padding(.top, 30)
                .staggeredEntrance(order: 4)
                Divider().frame(maxWidth: 440).padding(.top, 30)
                VStack(alignment: .leading, spacing: 14) {
                    Hint(symbol: "checkmark.shield", text: model.isQuickUnlockAvailable
                        ? "Protected by your master password.\nOpen it with \(model.quickUnlockKind.name) on this Mac."
                        : "Protected by your master password.\nA generated passphrase makes it easy.")
                    Hint(symbol: "wifi.slash", text: "No account to create. No cloud required.\nYour vault works offline.")
                }
                .padding(.top, 22)
                .staggeredEntrance(order: 5)
                Spacer()
                Text("Made for macOS. Built to be understood.")
                    .font(.serifItalic(15)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 64)
            .padding(.top, 76)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(item: $restoreRequest) { request in
            RestoreSheet(model: model, backupURL: request.url).modelAlert(model)
        }
    }

    @State private var restoreRequest: RestoreRequest?

    private func chooseBackupToRestore() {
        guard let url = FilePanels.chooseBackupFile() else { return }
        restoreRequest = RestoreRequest(url: url)
    }
}

struct Hint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Palette.text2).frame(width: 16).accessibilityHidden(true)
            Text(text).font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Palette.muted)
        }
    }
}

struct CreateVaultView: View {
    let model: AppModel
    @State private var vaultName = VaultContent.defaultName
    @State private var password = ""
    @State private var confirmation = ""
    /// The passphrase Clevane last filled in. While the field still holds it, Copy and a fresh draw are offered.
    @State private var suggested: String?
    @State private var isPasswordRevealed = false
    @State private var hasSavedPassphrase = false
    @State private var enableQuickUnlock = true

    private var isQuick: Bool { model.createsWithQuickUnlock }
    private var showsSuggestion: Bool { suggested != nil && suggested == password }

    var body: some View {
        HStack(spacing: 0) {
            IntroPanel(
                title: "Make it",
                accent: "yours.",
                paragraph: "One strong master password.\nA personal vault you control.",
                footer: AnyView(StepLine())
            )
            form.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if isQuick && password.isEmpty { suggest() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps(isQuick ? "\(model.quickUnlockKind.name) is ready" : "Set up your personal vault").staggeredEntrance(order: 1)
            Text(isQuick ? "One last thing." : "A secure beginning.").font(.serif(40)).padding(.top, 12).staggeredEntrance(order: 2)
            Text(isQuick
                 ? "Here is your backup passphrase. Keep it somewhere safe: it opens your vault and its backups on any Mac."
                 : "Your master password unlocks your vault and its backups. Let Clevane suggest one, or choose your own.")
                .font(.system(size: 13.5)).lineSpacing(4).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .staggeredEntrance(order: 3)
            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: "Vault name") {
                    FieldBox { TextField("Personal Vault", text: $vaultName).accessibilityLabel("Vault name") }
                }
                LabeledField(label: "Master password") {
                    SecretField(label: "Master password", placeholder: "Choose a long, unique password", text: $password, reveal: $isPasswordRevealed)
                }
                HStack(alignment: .top) {
                    if showsSuggestion {
                        Text("6 random words · write them down").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: suggest) { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(IconButtonStyle())
                            .help("Suggest another")
                            .accessibilityLabel("Suggest another passphrase")
                        CopyButton(accessibilityName: "Copy passphrase") { model.copyNewPassphrase(password) }
                        Button(action: savePassphraseFile) { Image(systemName: "square.and.arrow.down") }
                            .buttonStyle(IconButtonStyle())
                            .help("Save to a file")
                            .accessibilityLabel("Save passphrase to a file")
                    } else {
                        PasswordMeter(password: password)
                        Button(action: suggest) { Label("Suggest one", systemImage: "dice") }
                            .buttonStyle(CapsuleButtonStyle())
                            .fixedSize()
                    }
                }
                LabeledField(label: "Confirm master password") {
                    SecretField(label: "Confirm master password", placeholder: "Enter it again", text: $confirmation, reveal: $isPasswordRevealed)
                }
                if showsSuggestion {
                    Toggle("I saved my passphrase somewhere safe", isOn: $hasSavedPassphrase)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12.5, weight: .medium))
                }
            }
            .padding(.top, 18)
            .staggeredEntrance(order: 4)
            quickUnlockRow.padding(.top, 16).staggeredEntrance(order: 5)
            Divider().padding(.top, 18)
            HStack {
                Button(action: goBack) { Label("Back", systemImage: "arrow.left") }
                    .buttonStyle(.plain).foregroundStyle(Palette.text2)
                Spacer()
                Button(action: create) {
                    if model.isWorking { ProgressView().controlSize(.small) } else { Label(isQuick ? "Start" : "Create vault", systemImage: "arrow.right") }
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking || (showsSuggestion && !hasSavedPassphrase))
            }
            .padding(.top, 16)
            .staggeredEntrance(order: 6)
            Label("Keep your master password safe. Clevane cannot reset it for you.", systemImage: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .padding(.top, 12)
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, 56)
    }

    /// Quick creation already confirmed Touch ID or the Mac password: say so instead of asking again.
    @ViewBuilder private var quickUnlockRow: some View {
        let kind = model.quickUnlockKind
        if isQuick {
            Label("\(kind.name) will open this vault on this Mac.", systemImage: "checkmark.circle")
                .font(.system(size: 12.5)).foregroundStyle(Palette.text2)
        } else {
            HStack(spacing: 12) {
                SymbolTile(systemName: kind.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock with \(kind.name)").font(.system(size: 13, weight: .semibold))
                    Text(model.isQuickUnlockAvailable ? "Open this vault quickly on this Mac." : "Not available in this build. Use your master password.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Toggle("Unlock with \(kind.name)", isOn: Binding(get: { enableQuickUnlock && model.isQuickUnlockAvailable }, set: { enableQuickUnlock = $0 }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!model.isQuickUnlockAvailable)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.sheet))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line2, lineWidth: 0.5))
        }
    }

    /// Fills both fields and shows them: the passphrase is meant to be read and written down.
    private func suggest() {
        let passphrase = Passphrase.generate()
        suggested = passphrase
        password = passphrase
        confirmation = passphrase
        isPasswordRevealed = true
        hasSavedPassphrase = false
    }

    private func savePassphraseFile() {
        guard let file = FilePanels.choosePassphraseDestination() else { return }
        model.savePassphrase(password, to: file)
    }

    private func goBack() {
        model.createsWithQuickUnlock = false
        model.screen = .welcome
    }

    private func create() {
        let withQuickUnlock = model.isQuickUnlockAvailable && (isQuick || enableQuickUnlock)
        Task { await model.createVault(name: vaultName, password: password, confirmation: confirmation, enableTouchID: withQuickUnlock) }
    }
}

/// Length-only hint, not a strength promise: four bars at 8, 12, 16 and 20 characters.
struct PasswordMeter: View {
    let password: String

    private var filledBars: Int {
        [8, 12, 16, 20].filter { password.count >= $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(index < filledBars ? Palette.text : Palette.line2).frame(height: 3)
                }
            }
            Text("A long passphrase is a good place to start.").font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(filledBars) of 4")
    }
}

struct StepLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(Palette.text).frame(width: 26, height: 3)
            Capsule().fill(Palette.line2).frame(width: 26, height: 3)
            Capsule().fill(Palette.line2).frame(width: 26, height: 3)
            Caps("Your first vault").padding(.leading, 4)
        }
    }
}

// MARK: - Unlock

struct UnlockView: View {
    let model: AppModel
    @State private var password = ""
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [Palette.sheet, Palette.window], center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 460)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                AppIconTile().staggeredEntrance(order: 0)
                Text("Welcome back.").font(.serif(54)).padding(.top, 24).staggeredEntrance(order: 1)
                Text("Your personal space is locked.").font(.serifItalic(18)).foregroundStyle(Palette.muted).padding(.top, 4).staggeredEntrance(order: 2)
                Label("\(model.vaultFileName) · On this Mac", systemImage: "lock.fill")
                    .font(.system(size: 12)).foregroundStyle(Palette.text2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Palette.sheet))
                    .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 0.5))
                    .padding(.top, 16)
                    .staggeredEntrance(order: 3)
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "Master password") {
                        SecretField(label: "Master password", placeholder: "Enter your master password", text: $password)
                            .focused($isPasswordFocused)
                            .onSubmit(unlock)
                    }
                    Button(action: unlock) {
                        if model.isWorking { ProgressView().controlSize(.small) } else { Label("Unlock", systemImage: "arrow.right") }
                    }
                    .buttonStyle(InkButtonStyle(isWide: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking || password.isEmpty)
                    if model.isTouchIDEnabled && model.isQuickUnlockAvailable {
                        HStack(spacing: 12) {
                            Rectangle().fill(Palette.line2).frame(height: 1)
                            Text("or").font(.serifItalic(15)).foregroundStyle(Palette.muted)
                            Rectangle().fill(Palette.line2).frame(height: 1)
                        }
                        Button { Task { await model.quickUnlock() } } label: { Label("Use \(model.quickUnlockKind.name)", systemImage: model.quickUnlockKind.symbol) }
                            .buttonStyle(CapsuleButtonStyle(isWide: true))
                        Text("Your master password is always available.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 340)
                .padding(.top, 24)
                .staggeredEntrance(order: 4)
            }
            VStack {
                Spacer()
                HStack {
                    Button("Open another vault…") { openAnotherVault() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Label("Vault locked · Stored on this Mac · Protected at rest".uppercased(), systemImage: "lock")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.muted)
                    Spacer()
                    Color.clear.frame(width: 120, height: 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
        .onAppear { isPasswordFocused = true }
    }

    private func unlock() {
        guard !password.isEmpty, !model.isWorking else { return }
        let attempt = password
        Task {
            if await model.unlock(password: attempt) { password = "" }
        }
    }

    private func openAnotherVault() {
        guard let url = FilePanels.chooseVaultFile() else { return }
        model.useVault(at: url)
    }
}

// MARK: - Motion

/// Rises into place once, in order, when a screen appears. Off when Reduce Motion is on.
struct StaggeredEntrance: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.55).delay(0.04 + Double(order) * 0.05)) { isVisible = true }
            }
    }
}

extension View {
    func staggeredEntrance(order: Int) -> some View {
        modifier(StaggeredEntrance(order: order))
    }
}
