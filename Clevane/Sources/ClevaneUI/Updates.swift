import Foundation

/// "1.2.3" or "v1.2.3"; missing parts count as 0.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let numbers = trimmed.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let length = max(lhs.parts.count, rhs.parts.count)
        let left = lhs.parts + Array(repeating: 0, count: length - lhs.parts.count)
        let right = rhs.parts + Array(repeating: 0, count: length - rhs.parts.count)
        return left.lexicographicallyPrecedes(right)
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// A published version and the page where it can be downloaded.
struct Release: Equatable {
    let version: AppVersion
    let page: URL
}

/// Where published versions are read from. nil means nothing has been published yet.
protocol ReleaseSource: Sendable {
    func latestRelease() async throws -> Release?
}

/// The repository's latest GitHub release. Sends only an ordinary web request: nothing from the vault.
struct GitHubReleaseSource: ReleaseSource {
    private static let endpoint = URL(string: "https://api.github.com/repos/yanmwisa/clevane/releases/latest")!

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
    }

    func latestRelease() async throws -> Release? {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return AppVersion(payload.tag_name).map { Release(version: $0, page: payload.html_url) }
    }
}

/// What a check found, decided from the installed version and the latest published one.
enum UpdateResult: Equatable {
    case available(Release)
    case upToDate
    case nothingPublished

    init(current: AppVersion, latest: Release?) {
        guard let latest else { self = .nothingPublished; return }
        self = latest.version > current ? .available(latest) : .upToDate
    }
}
