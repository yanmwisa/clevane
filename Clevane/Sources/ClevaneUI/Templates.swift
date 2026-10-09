import SwiftUI
import VaultCore

extension TableTemplate {
    var symbol: String {
        switch self {
        case .logins: "person.badge.key"
        case .bankAccounts: "building.columns"
        case .apiKeys: "key"
        case .wifi: "wifi"
        case .privateNotes: "note.text"
        case .documents: "doc.on.doc"
        }
    }

    var summary: String {
        makeColumns().map(\.name).joined(separator: " · ")
    }
}

/// The templates as capsules; used by Get started and by New Table.
struct TemplatePicker: View {
    let onPick: (TableTemplate) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(TableTemplate.allCases, id: \.self) { template in
                Button { onPick(template) } label: { Label(template.name, systemImage: template.symbol) }
                    .buttonStyle(CapsuleButtonStyle())
                    .help(template.summary)
            }
        }
    }
}

/// Lays children out in rows, wrapping to the next row when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width = rows[last].indices.isEmpty ? size.width : rows[last].width + spacing + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(index)
        }
        return rows
    }
}
