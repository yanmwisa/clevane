import SwiftUI

/// The places the guide points at, in reading order. Stops whose place is not on screen are skipped.
enum GuideStop: CaseIterable {
    case tables, newTable, columns, addRow, rowDetail, lock, backup, settings, guide

    var title: String {
        switch self {
        case .tables: "Your tables"
        case .newTable: "New Table"
        case .columns: "Columns"
        case .addRow: "Add Row"
        case .rowDetail: "Details"
        case .lock: "Lock"
        case .backup: "Backup & Restore"
        case .settings: "Settings"
        case .guide: "This guide"
        }
    }

    var message: String {
        switch self {
        case .tables: "Each table holds one kind of secret: bank accounts, API keys, private notes. Pick one here."
        case .newTable: "Create a table and choose its columns: Text, Secret or Note."
        case .columns: "Add, rename or reorder columns at any time. Secret columns stay hidden until you show them."
        case .addRow: "Add an entry to this table. ⌘N works too."
        case .rowDetail: "The selected row opens here. Show reveals a secret; Copy puts it on the clipboard and clears it after a few seconds."
        case .lock: "Lock the vault in one click (⌘L). It also locks by itself when you step away or your Mac sleeps."
        case .backup: "Save an encrypted copy of your vault. Only your master password opens it."
        case .settings: "Auto-lock delay, appearance, quick unlock and your master password."
        case .guide: "Open this guide again any time from here, or from the Help menu."
        }
    }

    /// Where the bubble sits relative to the place it points at.
    var arrowEdge: Edge {
        switch self {
        case .columns, .addRow: .bottom
        case .rowDetail: .leading
        default: .trailing
        }
    }
}

extension View {
    /// Shows the guide's bubble on this view while the guide is at `stop`. Clicking elsewhere closes the guide.
    func guideStop(_ stop: GuideStop, model: AppModel) -> some View {
        let isShown = Binding(
            get: { model.guideStop == stop },
            set: { if !$0 && model.guideStop == stop { model.closeGuide() } }
        )
        return popover(isPresented: isShown, arrowEdge: stop.arrowEdge) {
            GuideCard(model: model, stop: stop)
                .presentationBackground(Palette.sheet)
        }
    }
}

struct GuideCard: View {
    let model: AppModel
    let stop: GuideStop

    private var stops: [GuideStop] { model.guideStops }
    private var position: Int { (stops.firstIndex(of: stop) ?? 0) + 1 }
    private var isLast: Bool { position == stops.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps("Guide · \(position) of \(stops.count)")
            Text(stop.title).font(.serif(22)).padding(.top, 8)
            Text(stop.message)
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 8) {
                Button("Skip") { model.closeGuide() }
                    .buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.muted)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if position > 1 {
                    Button("Back") { model.moveGuide(by: -1) }.buttonStyle(CapsuleButtonStyle())
                }
                Button(isLast ? "Done" : "Next") { model.moveGuide(by: 1) }
                    .buttonStyle(InkButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(18)
        .frame(width: 300)
        .foregroundStyle(Palette.text)
    }
}
