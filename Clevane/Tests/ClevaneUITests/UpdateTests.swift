import Foundation
import Testing
@testable import ClevaneUI

struct AppVersionTests {
    @Test func comparesNumbersNotText() throws {
        let older = try #require(AppVersion("0.9.0"))
        let newer = try #require(AppVersion("v0.10.0"))
        #expect(older < newer)
        #expect(AppVersion("1.0") == AppVersion("1.0.0"))
        #expect(AppVersion("2.1.3")?.description == "2.1.3")
    }

    @Test func rejectsTagsThatAreNotVersions() {
        #expect(AppVersion("beta") == nil)
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test func decidesFromTheLatestRelease() throws {
        let current = try #require(AppVersion("0.1.0"))
        let page = try #require(URL(string: "https://github.com/yanmwisa/clevane/releases/tag/v0.2.0"))
        let newer = Release(version: try #require(AppVersion("0.2.0")), page: page)
        let same = Release(version: current, page: page)
        #expect(UpdateResult(current: current, latest: newer) == .available(newer))
        #expect(UpdateResult(current: current, latest: same) == .upToDate)
        #expect(UpdateResult(current: current, latest: nil) == .nothingPublished)
    }
}

/// Fictional releases, no network.
private struct FakeReleaseSource: ReleaseSource {
    var release: Release?
    var failure: URLError?

    func latestRelease() async throws -> Release? {
        if let failure { throw failure }
        return release
    }
}

@MainActor
struct UpdateCheckTests {
    private func model(release: Release? = nil, failure: URLError? = nil) throws -> (AppFixture, AppModel) {
        let fixture = try AppFixture()
        fixture.model.installedVersion = "0.1.0"
        fixture.model.releaseSource = FakeReleaseSource(release: release, failure: failure)
        return (fixture, fixture.model)
    }

    private func release(_ version: String) throws -> Release {
        Release(version: try #require(AppVersion(version)), page: try #require(URL(string: "https://github.com/yanmwisa/clevane/releases/tag/v\(version)")))
    }

    @Test func aNewerVersionIsOffered() async throws {
        let newer = try release("0.2.0")
        let (fixture, model) = try model(release: newer)
        await model.checkForUpdates()
        #expect(model.updateOffer == newer)
        _ = fixture
    }

    @Test func aRequestedCheckAlwaysAnswers() async throws {
        let (fixture, model) = try model(release: try release("0.1.0"))
        await model.checkForUpdates()
        #expect(model.updateOffer == nil)
        #expect(model.toast == "Clevane 0.1.0 is up to date.")

        model.releaseSource = FakeReleaseSource(failure: URLError(.notConnectedToInternet))
        await model.checkForUpdates()
        #expect(model.alert?.message.contains("could not reach GitHub") == true)
        _ = fixture
    }

    /// At launch, nothing is said unless a newer version exists: no toast, no error.
    @Test func aQuietCheckSpeaksOnlyForANewerVersion() async throws {
        let (fixture, model) = try model(failure: URLError(.notConnectedToInternet))
        await model.checkForUpdates(quietly: true)
        #expect(model.alert == nil)
        model.releaseSource = FakeReleaseSource()
        await model.checkForUpdates(quietly: true)
        #expect(model.toast == nil)
        _ = fixture
    }

    @Test func launchCheckIsOffByDefault() throws {
        let (fixture, model) = try model()
        #expect(!model.checksUpdatesAtLaunch)
        _ = fixture
    }
}
