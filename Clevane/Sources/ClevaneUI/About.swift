import AppKit

/// What Clevane says about itself, in one place: the About panel, Settings and the update check read it.
enum AppInfo {
    static let name = "Clevane"
    static let author = "Yannick Kibale"
    static let license = "Apache License 2.0"
    static let summary = "A private vault for your passwords, notes and files. Everything is encrypted and stays on your Mac: no account, no cloud."
    static let credits = "libsodium and swift-sodium (ISC). Passphrase words: EFF large wordlist (CC BY 3.0)."
    static let releasesPage = URL(string: "https://github.com/yanmwisa/clevane/releases")!

    /// The version built into the app; a build run from source without a bundle has none.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

/// The standard macOS About panel, with what Clevane is and who made it.
@MainActor
public enum AboutPanel {
    public static func show() {
        let body = NSMutableParagraphStyle()
        body.alignment = .center
        body.paragraphSpacing = 8
        let text = [AppInfo.summary, "Created by \(AppInfo.author). Licensed under the \(AppInfo.license).", AppInfo.credits].joined(separator: "\n")
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: body,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: "",
            .credits: credits,
        ])
        NSApp.activate()
    }
}
