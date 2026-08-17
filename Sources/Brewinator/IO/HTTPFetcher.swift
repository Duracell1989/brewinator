import Foundation

/// Generic HTTP primitive for Phase 3's forge/vendor sources — not consumed
/// by anything yet in Phase 2.
protocol HTTPFetching: Sendable {
    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int)
}

final class URLSessionHTTPFetcher: HTTPFetching {
    private let session: URLSession

    /// A 5s connect timeout and a 15s overall resource timeout — generous
    /// enough for slow forges/CDNs without letting one hung fetch stall a
    /// whole sync run.
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http.statusCode)
    }
}
