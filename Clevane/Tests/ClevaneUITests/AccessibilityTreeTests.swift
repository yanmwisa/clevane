import AppKit
import ApplicationServices
import Foundation
import Testing
import VaultCore
@testable import ClevaneUI

/// Launches the built Clevane.app on a temporary vault with fictional data and reads its tree
/// through the system accessibility API, the way VoiceOver does. Needs the Accessibility
/// permission for the test runner, `scripts/build-app.sh release` and an unlocked screen
/// (macOS shows no window while the session is locked); skipped otherwise.
@MainActor
@Suite(.enabled(if: AppUnderTest.canRun, "Needs the Accessibility permission, a release build and an unlocked screen"))
struct AccessibilityTreeTests {
    private static let password = AppFixture.password

    @Test func everyButtonAndFieldHasANameOnUnlockAndVault() async throws {
        let fixture = try await makeDemoVault()
        let app = try await AppUnderTest(vaultURL: fixture.vaultURL)
        defer { app.quit() }

        let unlockButtons = try await app.waitForButtons { $0.contains { $0.hasPrefix("Unlock") } }
        #expect(unlockButtons.allSatisfy { !$0.isEmpty }, "Unnamed buttons on Unlock: \(unlockButtons)")
        let unlockFields = app.fieldNames()
        #expect(!unlockFields.isEmpty && unlockFields.allSatisfy { !$0.isEmpty }, "Unnamed fields on Unlock: \(unlockFields)")

        try #require(app.typePassword(Self.password), "No password field found on Unlock")
        try #require(app.press(button: "Unlock"), "No Unlock button")
        let vaultButtons = try await app.waitForButtons { $0.contains("Lock vault") }
        #expect(vaultButtons.allSatisfy { !$0.isEmpty }, "Unnamed buttons on Vault: \(vaultButtons)")
        let vaultFields = app.fieldNames()
        #expect(vaultFields.contains("Search Trading"), "Unnamed fields on Vault: \(vaultFields)")
        #expect(vaultFields.allSatisfy { !$0.isEmpty }, "Unnamed fields on Vault: \(vaultFields)")

        try #require(app.press(button: "ACC-1042"), "Row not found: \(vaultButtons)")
        let detailButtons = try await app.waitForButtons { $0.contains("Copy Password") }
        #expect(detailButtons.allSatisfy { !$0.isEmpty }, "Unnamed buttons on row detail: \(detailButtons)")
        #expect(detailButtons.contains("Show Password"))
        #expect(detailButtons.contains("Row options"), "Menu buttons are not scanned: \(detailButtons)")
        #expect(detailButtons.contains("Table options"), "Table menu misnamed: \(detailButtons)")

        try #require(app.press(button: "Columns"), "No Columns button")
        _ = try await app.waitForButtons { $0.contains("Add Column") }
        try #require(app.press(button: "Cancel"), "No Cancel in Columns")
        let afterSheet = try await app.waitForButtons { !$0.contains("Add Column") }
        #expect(!afterSheet.contains("More"), "A menu lost its name after a sheet: \(afterSheet)")
        #expect(afterSheet.contains("Table options") && afterSheet.contains("Row options"), "Menus misnamed after a sheet: \(afterSheet)")
    }

    private func makeDemoVault() async throws -> AppFixture {
        let fixture = try await AppFixture.openVault()
        let model = fixture.model
        let account = Column(name: "Account ID", type: .text)
        let secret = Column(name: "Password", type: .secret)
        _ = model.createTable(name: "Trading", columns: [account, secret])
        let tableID = try #require(model.currentTable?.id)
        _ = model.saveRow([account.id: "ACC-1042", secret.id: "Sample-Trade-01"], attachments: [:], editing: nil, in: tableID)
        model.lock()
        return fixture
    }
}

/// The real app process, driven only through the accessibility API.
@MainActor
private final class AppUnderTest {
    nonisolated static let bundle = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/release/Clevane.app")
    nonisolated static let binary = bundle.appendingPathComponent("Contents/MacOS/Clevane")

    nonisolated static var canRun: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let screenIsLocked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
        return AXIsProcessTrusted() && FileManager.default.isExecutableFile(atPath: binary.path) && !screenIsLocked
    }

    private let app: NSRunningApplication
    private let root: AXUIElement

    /// Opened through Launch Services so it gets a window like a normal launch.
    /// `-vaultPath` lands in the arguments domain: nothing is written to the app's preferences.
    init(vaultURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["-vaultPath", vaultURL.path]
        configuration.createsNewApplicationInstance = true
        app = try await NSWorkspace.shared.openApplication(at: Self.bundle, configuration: configuration)
        root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 5)
    }

    func quit() {
        app.forceTerminate()
    }

    func waitForButtons(until isReady: ([String]) -> Bool) async throws -> [String] {
        var names: [String] = []
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            names = buttons().map(\.name)
            if isReady(names) { return names }
        }
        Issue.record("Screen not reached in 10 s; buttons seen: \(names)")
        return names
    }

    func typePassword(_ password: String) -> Bool {
        guard let field = elements(in: root).first(where: { string($0, kAXSubroleAttribute) == kAXSecureTextFieldSubrole }) else { return false }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, password as CFString) == .success
    }

    func press(button name: String) -> Bool {
        guard let button = buttons().first(where: { $0.name.hasPrefix(name) }) else { return false }
        return AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
    }

    /// The name VoiceOver reads for each text field: its title, else its description, else its placeholder.
    func fieldNames() -> [String] {
        elements(in: root).filter { Self.fieldRoles.contains(string($0, kAXRoleAttribute) ?? "") }.map { field in
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute].compactMap { string(field, $0) }.first { !$0.isEmpty } ?? ""
        }
    }

    private func buttons() -> [(element: AXUIElement, name: String)] {
        elements(in: root).filter { Self.buttonRoles.contains(string($0, kAXRoleAttribute) ?? "") }.map { ($0, spokenName(of: $0)) }
    }

    private static let fieldRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// Everything VoiceOver announces as a button, menu buttons included ("Row options").
    private static let buttonRoles: Set<String> = [kAXButtonRole, kAXMenuButtonRole, kAXPopUpButtonRole]

    /// Window buttons drawn by macOS, named by their role description ("close button").
    private static let systemWindowButtons: Set<String> = [kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, kAXFullScreenButtonSubrole]

    /// What VoiceOver reads for a button: its title, else its description (`accessibilityLabel`), else its text.
    private func spokenName(of button: AXUIElement) -> String {
        if let subrole = string(button, kAXSubroleAttribute), Self.systemWindowButtons.contains(subrole) {
            return string(button, kAXRoleDescriptionAttribute) ?? ""
        }
        let own = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { string(button, $0) }.first { !$0.isEmpty }
        let text = elements(in: button).dropFirst().compactMap { string($0, kAXValueAttribute) }.first { !$0.isEmpty }
        return own ?? text ?? ""
    }

    private func elements(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 80 else { return [] }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        let found = (children as? [AXUIElement] ?? []).flatMap { elements(in: $0, depth: depth + 1) }
        return [element] + found
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
