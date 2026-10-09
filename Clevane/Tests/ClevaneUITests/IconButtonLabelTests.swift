import Foundation
import Testing

/// Source vigil, runnable even while the Mac is locked: a button or menu whose label is only an
/// image has no name for VoiceOver unless its modifier chain sets `.accessibilityLabel`.
/// Buttons labelled with text get their name from SwiftUI. The live check is `AccessibilityTreeTests`.
struct IconButtonLabelTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/ClevaneUI")

    @Test func everyIconOnlyButtonHasAName() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var iconButtons = 0
        var unnamed: [String] = []
        for file in files {
            let found = iconOnlyLabels(in: try String(contentsOf: file, encoding: .utf8))
            iconButtons += found.count
            unnamed += found.filter { !$0.isNamed }.map { "\(file.lastPathComponent): \($0.label)" }
        }
        #expect(iconButtons >= 7, "Only \(iconButtons) icon buttons found: the scan no longer matches the code")
        #expect(unnamed.isEmpty, "Icon-only buttons without accessibilityLabel: \(unnamed)")
    }

    /// Control test: the scan must catch a missing name and accept a present one.
    @Test func scanCatchesAMissingName() {
        let source = """
        Button { lock() } label: { Image(systemName: "lock") }
            .buttonStyle(.plain)
        Button(action: copy) {
            Image(systemName: "doc.on.doc")
        }
        .accessibilityLabel("Copy")
        Button { save() } label: { Text("Save") }
        """
        let found = iconOnlyLabels(in: source)
        #expect(found.map(\.isNamed) == [false, true])
    }
}

/// Finds labels made only of images (`label: { … }` or `Button(action:) { … }`) and whether the
/// modifier lines right after them set `.accessibilityLabel`.
private func iconOnlyLabels(in source: String) -> [(label: String, isNamed: Bool)] {
    let opening = /label:\s*\{|Button\(action:[^)]*\)\s*\{/
    var results: [(String, Bool)] = []
    for match in source.matches(of: opening) {
        guard let body = closure(in: source, openingBraceBefore: match.range.upperBound) else { continue }
        let label = String(source[body])
        guard label.contains("Image("), !label.contains("Text("), !label.contains("Label(") else { continue }
        let chain = modifierChain(in: source, after: body.upperBound)
        results.append((label.trimmingCharacters(in: .whitespacesAndNewlines), chain.contains(".accessibilityLabel(")))
    }
    return results
}

/// The text between the brace that ends at `index` and its matching closing brace.
private func closure(in source: String, openingBraceBefore index: String.Index) -> Range<String.Index>? {
    var depth = 1
    var cursor = index
    while cursor < source.endIndex {
        switch source[cursor] {
        case "{": depth += 1
        case "}": depth -= 1
        default: break
        }
        if depth == 0 { return index..<cursor }
        cursor = source.index(after: cursor)
    }
    return nil
}

/// The rest of the closing line plus every following line that starts with a modifier dot.
private func modifierChain(in source: String, after closingBrace: String.Index) -> String {
    let rest = source[closingBrace...].split(separator: "\n", omittingEmptySubsequences: false)
    guard let first = rest.first else { return "" }
    let modifiers = rest.dropFirst().prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".") }
    return ([first] + modifiers).joined(separator: "\n")
}
