import Foundation

public struct DataSourceStatus: Sendable, Equatable {
    public let name: String
    public let detail: String
    public let metricSource: MetricSource?
    public let cacheKey: String
    public let payloadURL: URL
    public let versionURL: URL?
    public let cachePolicy: String
    public let payloadPath: String
    public let metadataPath: String
    public let isCached: Bool
    public let cachedVersion: String?
    public let cachedAt: Date?
    public let cachedBytes: Int?

    public init(
        name: String,
        detail: String,
        metricSource: MetricSource?,
        cacheKey: String,
        payloadURL: URL,
        versionURL: URL?,
        cachePolicy: String,
        payloadPath: String,
        metadataPath: String,
        isCached: Bool,
        cachedVersion: String?,
        cachedAt: Date?,
        cachedBytes: Int?
    ) {
        self.name = name
        self.detail = detail
        self.metricSource = metricSource
        self.cacheKey = cacheKey
        self.payloadURL = payloadURL
        self.versionURL = versionURL
        self.cachePolicy = cachePolicy
        self.payloadPath = payloadPath
        self.metadataPath = metadataPath
        self.isCached = isCached
        self.cachedVersion = cachedVersion
        self.cachedAt = cachedAt
        self.cachedBytes = cachedBytes
    }
}

public actor DataSourceInspector {
    private let cache: FilePayloadCache
    private let definitions: [DataSourceDefinition]

    public init(
        cache: FilePayloadCache,
        definitions: [DataSourceDefinition] = DataSourceEndpoints.catalog
    ) {
        self.cache = cache
        self.definitions = definitions
    }

    public func statuses() async -> [DataSourceStatus] {
        var values: [DataSourceStatus] = []
        values.reserveCapacity(definitions.count)

        for definition in definitions {
            let resource = definition.resource
            let payloadFileURL = cache.payloadURL(for: resource.cacheKey)
            let metadataFileURL = cache.metadataURL(for: resource.cacheKey)
            let cachedPayload = try? await cache.read(key: resource.cacheKey)

            values.append(DataSourceStatus(
                name: definition.name,
                detail: definition.detail,
                metricSource: definition.metricSource,
                cacheKey: resource.cacheKey,
                payloadURL: resource.payloadURL,
                versionURL: resource.versionURL,
                cachePolicy: describe(resource.cachePolicy),
                payloadPath: payloadFileURL.path,
                metadataPath: metadataFileURL.path,
                isCached: cachedPayload != nil,
                cachedVersion: cachedPayload?.version,
                cachedAt: cachedPayload?.storedAt,
                cachedBytes: cachedPayload?.data.count
            ))
        }

        return values
    }

    private nonisolated func describe(_ cachePolicy: CachePolicy) -> String {
        if cachePolicy.timeToLive == nil {
            return "versioned"
        }
        if cachePolicy.timeToLive == 0 {
            return "always refresh"
        }
        let hours = Int((cachePolicy.timeToLive ?? 0) / 3600)
        return "\(hours)h ttl"
    }
}
