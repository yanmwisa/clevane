import Foundation
import Testing
@testable import VaultCore

/// Vigil (Constitution 15.4, success criterion): a known fictional value never appears in clear on disk,
/// in any file Clevane writes, through the whole life of a vault. If this fails, a secret leaked.
@MainActor
struct VigilTests {
    @Test func sentinelNeverReachesTheDisk() async throws {
        let folder = try TemporaryFolder()
        let session = try await makeOpenVault(in: folder)
        let sentinel = Fixture.sentinel
        let columns = [Column(name: "Name \(sentinel)", type: .text), Column(name: "Secret", type: .secret), Column(name: "Note", type: .note)]
        let tableID = try session.edit { try $0.addTable(name: "Table \(sentinel)", columns: columns) }
        try session.edit {
            try $0.addRow(to: tableID, values: [columns[0].id: sentinel, columns[1].id: "pw-\(sentinel)", columns[2].id: "line one\n\(sentinel)"])
        }
        try await session.changePassword(current: Fixture.password, new: "pass-\(sentinel)")
        try BackupService.createBackup(of: session.file, in: folder.url)
        session.lock()
        try await session.unlock(password: "pass-\(sentinel)")
        session.lock()

        let needles = [Data(sentinel.utf8), sentinel.data(using: .utf16LittleEndian)!, sentinel.data(using: .utf16BigEndian)!]
        let files = try folder.allFileContents()
        #expect(files.count >= 3)
        for (url, data) in files {
            for needle in needles {
                #expect(data.range(of: needle) == nil, "Sentinel found in clear in \(url.lastPathComponent)")
            }
        }
    }

    /// Control: the scan does find a value planted in clear, so a passing vigil means something.
    @Test func scanFindsAPlantedSentinel() throws {
        let folder = try TemporaryFolder()
        try Data("prefix \(Fixture.sentinel) suffix".utf8).write(to: folder.file("planted.txt"))
        let found = try folder.allFileContents().contains { $0.1.range(of: Data(Fixture.sentinel.utf8)) != nil }
        #expect(found)
    }

    /// T6: no error message repeats a value, even when the value caused the error.
    @Test func errorMessagesNeverContainValues() async throws {
        var content = VaultContent()
        try content.addTable(name: Fixture.sentinel, columns: [Column(name: "A", type: .text)])
        do {
            try content.addTable(name: Fixture.sentinel, columns: [Column(name: "A", type: .text)])
            Issue.record("Duplicate table accepted")
        } catch {
            #expect(!error.localizedDescription.contains(Fixture.sentinel))
            #expect(!String(describing: error).contains(Fixture.sentinel))
        }
    }
}
