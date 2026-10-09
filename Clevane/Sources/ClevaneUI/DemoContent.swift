#if CLEVANE_SNAPSHOTS
import AppKit
import VaultCore

/// Debug builds only. Fictional content that shows every feature: logins, bank accounts, API keys, Wi-Fi,
/// private notes, a custom table, and documents with photos and PDFs drawn on the spot. Sites use example.*
/// domains and banks are invented; nothing here is real.
@MainActor
enum DemoContent {
    static let password = "sample demo passphrase"

    static func fill(_ model: AppModel, scratch folder: URL) {
        addRows(.logins, to: model, [
            ["Mail", "alex.sample@example.com", "Sample-Mail-2026", "https://mail.example.com", "Personal mailbox."],
            ["Online shop", "alex.sample", "Sample-Shop-0042", "https://shop.example.net", ""],
            ["Streaming", "family.sample", "Sample-Stream-77", "https://tv.example.org", "Shared with the family."],
            ["Cloud drive", "alex.sample@example.com", "Sample-Drive-19", "https://drive.example.com", ""],
            ["Forum", "alex_s", "Sample-Forum-03", "https://forum.example.org", "Old account, rarely used."],
        ])
        addRows(.bankAccounts, to: model, [
            ["Northwind Bank", "NW 0000 1111 2222", "Sample-4821", "Everyday checking."],
            ["Harbor Savings", "HS 3333 4444 5555", "Sample-9930", "Emergency fund."],
            ["Atlas Credit Union", "AC 6666 7777 8888", "Sample-1207", "Car loan."],
        ])
        addTrading(to: model)
        addRows(.apiKeys, to: model, [
            ["Weather API", "sk-sample-0001", "Personal project. Rotate yearly."],
            ["Maps API", "sk-sample-0002", "Read-only test key."],
            ["Mail relay", "sk-sample-0003", ""],
        ])
        addRows(.wifi, to: model, [
            ["Home", "Sample-Home-WiFi"],
            ["Office guest", "Sample-Guest-2026"],
            ["Cabin", "Sample-Cabin-88"],
        ])
        addRows(.privateNotes, to: model, [
            ["Home network", "Router in the hallway cabinet.\nSample note only."],
            ["Locker", "Gym locker 42, combination in the Secret column of another table.\nSample note only."],
            ["Recovery plan", "Backup drive in the desk drawer. Master passphrase written on paper at home.\nSample note only."],
        ])
        addDocuments(to: model, scratch: folder)
    }

    /// One table from a template, one row per entry, values in the template's column order.
    private static func addRows(_ template: TableTemplate, to model: AppModel, _ entries: [[String]]) {
        guard model.createTable(from: template), let table = model.currentTable else { return }
        for entry in entries {
            let values = Dictionary(uniqueKeysWithValues: zip(table.columns.map(\.id), entry).filter { !$0.1.isEmpty })
            _ = model.saveRow(values, attachments: [:], editing: nil, in: table.id)
        }
    }

    /// A custom table, to show columns chosen by hand.
    private static func addTrading(to model: AppModel) {
        let account = Column(name: "Account ID", type: .text), password = Column(name: "Password", type: .secret), pin = Column(name: "Trading Password", type: .secret)
        guard model.createTable(name: "Trading", columns: [account, password, pin]), let table = model.currentTable else { return }
        for (index, number) in ["1042", "2087", "3315", "4460", "5128", "6093"].enumerated() {
            let values = [account.id: "ACC-\(number)", password.id: "Sample-Trade-0\(index + 1)", pin.id: "Sample-PIN-0\(index + 1)"]
            _ = model.saveRow(values, attachments: [:], editing: nil, in: table.id)
        }
    }

    private static func addDocuments(to model: AppModel, scratch folder: URL) {
        guard model.createTable(from: .documents), let table = model.currentTable,
              let fileColumn = table.columns.first(where: { $0.type == .file }) else { return }
        let documents: [(title: String, file: URL?, note: String)] = [
            ("Sample ID card", photo("SAMPLE ID", named: "sample-id-card.png", in: folder), "Fictional scan for the demo."),
            ("Sample passport", photo("SAMPLE PASSPORT", named: "sample-passport.png", in: folder), "Expires 2031 (fictional)."),
            ("Lease contract", pdf("Lease contract", body: "Fictional lease between Alex Sample and Example Homes.\nSigned 1 March 2026.", named: "lease-contract.pdf", in: folder), "Original in the blue folder."),
            ("Car insurance", pdf("Car insurance", body: "Fictional policy SAMPLE-0042 with Example Insurance.\nRenewal every September.", named: "car-insurance.pdf", in: folder), ""),
        ]
        for document in documents {
            guard let file = document.file, let attachment = model.attachFile(at: file) else { continue }
            var values = [table.columns[0].id: document.title]
            if !document.note.isEmpty { values[table.columns[2].id] = document.note }
            _ = model.saveRow(values, attachments: [fileColumn.id: attachment], editing: nil, in: table.id)
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// A drawn card standing in for a scan: a gradient and a label, saved as PNG in the scratch folder.
    private static func photo(_ label: String, named name: String, in folder: URL) -> URL? {
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0.34, alpha: 1), NSColor(white: 0.12, alpha: 1)])?.draw(in: rect, angle: -60)
            NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 50, weight: .semibold), .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: 48, y: 48))
            return true
        }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return write(png, named: name, in: folder)
    }

    /// A one-page PDF with a title and a few lines of fictional text.
    private static func pdf(_ title: String, body: String, named name: String, in folder: URL) -> URL? {
        let page = NSTextView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        page.textContainerInset = NSSize(width: 56, height: 64)
        page.textStorage?.setAttributedString(NSAttributedString(string: "\(title)\n\n\(body)", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        return write(page.dataWithPDF(inside: page.bounds), named: name, in: folder)
    }

    private static func write(_ bytes: Data, named name: String, in folder: URL) -> URL? {
        let file = folder.appendingPathComponent(name)
        return (try? bytes.write(to: file)) == nil ? nil : file
    }
}

/// Debug builds only. With CLEVANE_DEMO_VAULT set to a path, the app opens that separate vault, created and
/// filled with `DemoContent` on first launch. Preferences stay in memory: the real vault and settings are untouched.
@MainActor
enum DemoVault {
    static let requestedURL = ProcessInfo.processInfo.environment["CLEVANE_DEMO_VAULT"].map { URL(fileURLWithPath: $0) }

    static func makeModel(at url: URL) -> AppModel {
        AppModel(vaultURL: url, preferences: MemoryPreferences())
    }

    /// First launch: create the vault with the demo password, fill it, leave it open on its first table.
    static func prepare(_ model: AppModel, at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        Task {
            await model.createVault(name: "Demo Vault", password: DemoContent.password, confirmation: DemoContent.password, enableTouchID: false)
            DemoContent.fill(model, scratch: FileManager.default.temporaryDirectory)
            if let first = model.content.tables.first { model.open(.table(first.id)) }
        }
    }
}
#endif
