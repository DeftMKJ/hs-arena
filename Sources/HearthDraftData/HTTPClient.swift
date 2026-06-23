import Foundation

public protocol HTTPClient: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DataLayerError.httpStatus(httpResponse.statusCode, url)
        }
        return data
    }
}

public enum DataLayerError: Error, Equatable, LocalizedError {
    case invalidURL(String)
    case httpStatus(Int, URL)
    case missingCachedPayload(String)
    case unsupportedPayload(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            "Invalid URL: \(value)"
        case .httpStatus(let status, let url):
            "HTTP \(status): \(url.absoluteString)"
        case .missingCachedPayload(let key):
            "Missing cached payload: \(key)"
        case .unsupportedPayload(let reason):
            "Unsupported payload: \(reason)"
        case .decodingFailed(let reason):
            "Decoding failed: \(reason)"
        }
    }
}
