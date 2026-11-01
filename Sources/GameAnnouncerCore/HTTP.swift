import Foundation

public enum FetchError: Error, CustomStringConvertible {
    case rateLimited
    case http(status: Int, url: URL)

    public var description: String {
        switch self {
        case .rateLimited: "HTTP 429 Too Many Requests"
        case let .http(status, url): "HTTP \(status) from \(url)"
        }
    }
}

/// Result of a GET that may send If-None-Match.
public enum ConditionalResponse: Sendable {
    case notModified
    case fetched(Data, etag: String?)
}

/// Thin URLSession wrapper with no local caching: we always want what the server has now,
/// and do conditional requests ourselves via ETag.
struct HTTP: Sendable {
    let session: URLSession
    let userAgent: String

    init(userAgent: String) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        self.userAgent = userAgent
    }

    func get(_ url: URL, etag: String? = nil) async throws -> ConditionalResponse {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        switch http.statusCode {
        case 200: return .fetched(data, etag: http.value(forHTTPHeaderField: "ETag"))
        case 304: return .notModified
        case 429: throw FetchError.rateLimited
        default: throw FetchError.http(status: http.statusCode, url: url)
        }
    }

    func get(_ url: URL) async throws -> Data {
        guard case let .fetched(data, _) = try await get(url, etag: nil) else {
            preconditionFailure("304 without If-None-Match")
        }
        return data
    }
}
