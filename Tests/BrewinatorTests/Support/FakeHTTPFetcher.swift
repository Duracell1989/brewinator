import Foundation

@testable import Brewinator

/// Hand-written protocol fake for `HTTPFetching` — no Moq equivalent in
/// Swift. Canned per-URL `(data, statusCode)` responses; URLs not registered
/// throw, matching a real network failure rather than silently succeeding.
struct FakeHTTPFetcher: HTTPFetching {
    struct UnregisteredURLError: Error {}

    private var responses: [URL: (data: Data, statusCode: Int)] = [:]
    private var throwingURLs: Set<URL> = []

    mutating func respond(to url: URL, data: Data, statusCode: Int) {
        responses[url] = (data, statusCode)
    }

    mutating func respond(to url: URL, string: String, statusCode: Int) {
        respond(to: url, data: Data(string.utf8), statusCode: statusCode)
    }

    mutating func fail(_ url: URL) {
        throwingURLs.insert(url)
    }

    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        if throwingURLs.contains(url) {
            throw URLError(.notConnectedToInternet)
        }
        guard let response = responses[url] else {
            throw UnregisteredURLError()
        }
        return response
    }
}

enum Fixture {
    struct NotFoundError: Error {}

    static func data(_ name: String, extension ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw NotFoundError()
        }
        return try Data(contentsOf: url)
    }

    static func string(_ name: String, extension ext: String) throws -> String {
        guard let text = String(data: try data(name, extension: ext), encoding: .utf8) else {
            throw NotFoundError()
        }
        return text
    }
}
