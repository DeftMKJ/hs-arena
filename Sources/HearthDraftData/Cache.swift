import Foundation

public struct CachePolicy: Sendable {
    public let timeToLive: TimeInterval?

    public init(timeToLive: TimeInterval? = nil) {
        self.timeToLive = timeToLive
    }

    public static let alwaysRefresh = CachePolicy(timeToLive: 0)
    public static let oneDay = CachePolicy(timeToLive: 24 * 60 * 60)
    public static let versioned = CachePolicy(timeToLive: nil)
}

public struct CachedPayload: Sendable {
    public let data: Data
    public let version: String?
    public let storedAt: Date
}

public protocol PayloadCache: Sendable {
    func read(key: String) async throws -> CachedPayload?
    func write(key: String, data: Data, version: String?) async throws
}

public actor FilePayloadCache: PayloadCache {
    public struct StoredMetadata: Codable, Sendable, Equatable {
        public let version: String?
        public let storedAt: Date

        public init(version: String?, storedAt: Date) {
            self.version = version
            self.storedAt = storedAt
        }
    }

    public nonisolated let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootURL: URL = FilePayloadCache.defaultRootURL()) {
        self.rootURL = rootURL
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base
            .appendingPathComponent("HearthStoneDraftAssistant", isDirectory: true)
            .appendingPathComponent("DataCache", isDirectory: true)
    }

    public func read(key: String) async throws -> CachedPayload? {
        let payloadURL = payloadURL(for: key)
        let metadataURL = metadataURL(for: key)
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: payloadURL)
        var version: String?
        var storedAt = Date.distantPast
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let metadata = try decoder.decode(StoredMetadata.self, from: Data(contentsOf: metadataURL))
            version = metadata.version
            storedAt = metadata.storedAt
        }
        return CachedPayload(data: data, version: version, storedAt: storedAt)
    }

    public func write(key: String, data: Data, version: String?) async throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try data.write(to: payloadURL(for: key), options: .atomic)
        let metadata = StoredMetadata(version: version, storedAt: Date())
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL(for: key), options: .atomic)
    }

    public nonisolated func payloadURL(for key: String) -> URL {
        rootURL.appendingPathComponent(Self.sanitized(key)).appendingPathExtension("json")
    }

    public nonisolated func metadataURL(for key: String) -> URL {
        rootURL.appendingPathComponent(Self.sanitized(key)).appendingPathExtension("meta")
    }

    public func readMetadata(key: String) async throws -> StoredMetadata? {
        let metadataURL = metadataURL(for: key)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        return try decoder.decode(StoredMetadata.self, from: Data(contentsOf: metadataURL))
    }

    private nonisolated static func sanitized(_ key: String) -> String {
        key.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}
