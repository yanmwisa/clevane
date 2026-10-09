import AppKit
import Testing
import VaultCore
@testable import ClevaneUI

/// Locking on system events and on inactivity at app level, on a temporary vault with fictional data.
@MainActor
struct SystemLockTests {
    /// Private centers stand in for NSWorkspace and the distributed center: nothing is broadcast to other apps.
    @Test(arguments: [
        (NSWorkspace.willSleepNotification, false),
        (NSWorkspace.screensDidSleepNotification, false),
        (NSWorkspace.sessionDidResignActiveNotification, false),
        (SystemLockObserver.screenIsLocked, true),
    ])
    func systemEventLocksTheVault(event: Notification.Name, isDistributed: Bool) async throws {
        let fixture = try await AppFixture.openVault()
        let model = fixture.model
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let observer = SystemLockObserver(model: model, workspace: workspace, distributed: distributed)
        defer { observer.stop() }

        (isDistributed ? distributed : workspace).post(name: event, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.screen == .unlock)
        #expect(!model.session.isOpen)
        #expect(model.content.tables.isEmpty)
    }

    /// Vigil for the defect fixed on October 8: after an inactivity lock the window must leave the vault.
    @Test func inactivityReturnsToUnlock() async throws {
        let fixture = try await AppFixture.openVault()
        let model = fixture.model
        model.checkInactivity(now: Date().addingTimeInterval(120))
        #expect(model.screen == .vault)
        model.checkInactivity(now: Date().addingTimeInterval(301))
        #expect(model.screen == .unlock)
        #expect(!model.session.isOpen)
    }
}
