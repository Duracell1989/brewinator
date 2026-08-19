import Foundation

/// The HTTP primitive every forge and vendor note source fetches through.
protocol HTTPFetching: Sendable {
    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int)
}

final class URLSessionHTTPFetcher: HTTPFetching {
    private let session: URLSession

    /// 5s connect, 15s overall: enough for a slow CDN, not enough for one hung
    /// fetch to stall the run.
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
