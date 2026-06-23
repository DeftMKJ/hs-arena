import Foundation

public protocol CardMetadataProviding: Sendable {
    func loadCards() async throws -> [CardMetadata]
}

public protocol CardMetricsProviding: Sendable {
    var source: MetricSource { get }
    func loadMetrics() async throws -> [CardMetric]
}

public protocol ArenaRotationProviding: Sendable {
    func loadRotation() async throws -> ArenaRotation
}

public struct RemoteJSONResource: Sendable {
    public let cacheKey: String
    public let versionURL: URL?
    public let payloadURL: URL
    public let cachePolicy: CachePolicy
    public let versionField: String?

    public init(
        cacheKey: String,
        versionURL: URL? = nil,
        payloadURL: URL,
        cachePolicy: CachePolicy,
        versionField: String? = nil
    ) {
        self.cacheKey = cacheKey
        self.versionURL = versionURL
        self.payloadURL = payloadURL
        self.cachePolicy = cachePolicy
        self.versionField = versionField
    }
}

public struct RemoteJSONLoader: Sendable {
    public enum Mode: Sendable {
        case normal
        case cacheOnly
    }

    private let httpClient: HTTPClient
    private let cache: PayloadCache
    private let mode: Mode
    private let decoder = JSONDecoder()

    public init(httpClient: HTTPClient, cache: PayloadCache, mode: Mode = .normal) {
        self.httpClient = httpClient
        self.cache = cache
        self.mode = mode
    }

    public func load(_ resource: RemoteJSONResource) async throws -> Data {
        let cached = try await cache.read(key: resource.cacheKey)
        if mode == .cacheOnly {
            guard let cached else {
                throw DataLayerError.missingCachedPayload(resource.cacheKey)
            }
            return cached.data
        }

        if let ttl = resource.cachePolicy.timeToLive {
            if ttl > 0, let cached, Date().timeIntervalSince(cached.storedAt) < ttl {
                return cached.data
            }
        } else if let versionURL = resource.versionURL, let versionField = resource.versionField {
            let versionData = try await httpClient.data(from: versionURL)
            let remoteVersion = try decodeVersion(from: versionData, field: versionField)
            if cached?.version == remoteVersion, let cached {
                return cached.data
            }
            let data = try await httpClient.data(from: resource.payloadURL)
            try await cache.write(key: resource.cacheKey, data: data, version: remoteVersion)
            return data
        } else if let cached {
            return cached.data
        }

        let data = try await httpClient.data(from: resource.payloadURL)
        try await cache.write(key: resource.cacheKey, data: data, version: nil)
        return data
    }

    private func decodeVersion(from data: Data, field: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any], let value = dictionary[field] else {
            throw DataLayerError.decodingFailed("Missing version field \(field)")
        }
        return String(describing: value)
    }
}

public struct HearthArenaProvider: CardMetricsProviding {
    public let source: MetricSource = .hearthArena
    private let loader: RemoteJSONLoader
    private let resource: RemoteJSONResource
    private let officialHTMLResource: RemoteJSONResource

    public init(
        loader: RemoteJSONLoader,
        resource: RemoteJSONResource = DataSourceEndpoints.hearthArena,
        officialHTMLResource: RemoteJSONResource = DataSourceEndpoints.hearthArenaOfficialHTML
    ) {
        self.loader = loader
        self.resource = resource
        self.officialHTMLResource = officialHTMLResource
    }

    public func loadMetrics() async throws -> [CardMetric] {
        let data = try await loader.load(resource)
        let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        let now = Date()
        var metrics = decoded.flatMap { className, cards in
            guard let arenaClass = ArenaClass(externalName: className) else {
                return [CardMetric]()
            }
            return cards.map { cardId, score in
                CardMetric(cardId: cardId, classContext: arenaClass, source: .hearthArena, score: score, updatedAt: now)
            }
        }

        if let officialData = try? await loader.load(officialHTMLResource),
           let html = String(data: officialData, encoding: .utf8) {
            metrics.append(contentsOf: HearthArenaHTMLParser.parse(html: html, updatedAt: now))
        }

        return Dictionary(
            metrics.map { ("\($0.classContext.rawValue)|\($0.cardId)", $0) },
            uniquingKeysWith: { _, official in official }
        )
        .values
        .map { $0 }
    }
}

enum HearthArenaHTMLParser {
    private static let classSections: [(String, ArenaClass)] = [
        ("death-knight", .deathKnight),
        ("demon-hunter", .demonHunter),
        ("druid", .druid),
        ("hunter", .hunter),
        ("mage", .mage),
        ("paladin", .paladin),
        ("priest", .priest),
        ("rogue", .rogue),
        ("shaman", .shaman),
        ("warlock", .warlock),
        ("warrior", .warrior),
        ("any", .neutral)
    ]

    static func parse(html: String, updatedAt: Date = Date()) -> [CardMetric] {
        classSections.flatMap { sectionId, arenaClass in
            parseSection(sectionId: sectionId, arenaClass: arenaClass, html: html, updatedAt: updatedAt)
        }
    }

    private static func parseSection(sectionId: String, arenaClass: ArenaClass, html: String, updatedAt: Date) -> [CardMetric] {
        guard let section = sectionHTML(sectionId: sectionId, html: html) else {
            return []
        }

        let pattern = #"<dt class="[^"]*"[^>]*data-card-image="[^"]*/([^/"']+)\.webp"[^>]*>\s*([^<]+?)\s*</dt>\s*<dd class="score[^"]*">\s*([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(section.startIndex..<section.endIndex, in: section)
        return regex.matches(in: section, range: range).compactMap { match in
            guard let cardIdRange = Range(match.range(at: 1), in: section),
                  let scoreRange = Range(match.range(at: 3), in: section),
                  let score = Double(section[scoreRange]) else {
                return nil
            }
            return CardMetric(
                cardId: String(section[cardIdRange]),
                classContext: arenaClass,
                source: .hearthArena,
                score: score,
                updatedAt: updatedAt
            )
        }
    }

    private static func sectionHTML(sectionId: String, html: String) -> String? {
        let marker = #"class="tab tierlist \#(sectionId)"#
        guard let start = html.range(of: marker)?.lowerBound else {
            return nil
        }

        let searchStart = html.index(after: start)
        let next = html[searchStart...].range(of: #"class="tab tierlist "#)?.lowerBound ?? html.endIndex
        return String(html[start..<next])
    }
}

public struct CardsJSONProvider: CardMetadataProviding {
    private struct RawCard: Decodable {
        let id: String
        let dbfId: Int?
        let name: LocalizedCardText?
        let cardClass: String?
        let classes: [String]?
        let rarity: String?
        let type: String?
        let cost: Int?
        let collectible: Bool?
        let set: String?
    }

    private let loader: RemoteJSONLoader
    private let resource: RemoteJSONResource

    public init(loader: RemoteJSONLoader, resource: RemoteJSONResource = DataSourceEndpoints.cardsJSON) {
        self.loader = loader
        self.resource = resource
    }

    public func loadCards() async throws -> [CardMetadata] {
        let data = try await loader.load(resource)
        let rawCards = try JSONDecoder().decode([RawCard].self, from: data)
        return rawCards.compactMap { raw in
            guard let name = raw.name?.displayName else {
                return nil
            }
            return CardMetadata(
                id: raw.id,
                dbfId: raw.dbfId,
                name: name,
                localizedNames: raw.name?.localizedNames ?? [:],
                cardClass: raw.cardClass.flatMap(ArenaClass.init(externalName:)),
                multiClass: raw.classes?.compactMap(ArenaClass.init(externalName:)) ?? [],
                rarity: raw.rarity,
                type: raw.type,
                cost: raw.cost,
                collectible: raw.collectible ?? false,
                set: raw.set
            )
        }
    }
}

private struct LocalizedCardText: Decodable, Equatable {
    let localizedNames: [String: String]

    var displayName: String? {
        localizedNames["zhCN"]
            ?? localizedNames["enUS"]
            ?? localizedNames.values.first
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            localizedNames = ["enUS": value]
            return
        }
        localizedNames = try container.decode([String: String].self)
    }
}

public struct ArenaRotationProvider: ArenaRotationProviding {
    private struct RawRotation: Decodable {
        let arenaVersion: Int
        let seasonId: Int?
        let arenaSets: [String]?
        let multiclassArena: Bool?
        let trustHA: Bool?
    }

    private let loader: RemoteJSONLoader
    private let resource: RemoteJSONResource

    public init(loader: RemoteJSONLoader, resource: RemoteJSONResource = DataSourceEndpoints.arenaRotation) {
        self.loader = loader
        self.resource = resource
    }

    public func loadRotation() async throws -> ArenaRotation {
        let data = try await loader.load(resource)
        let raw = try JSONDecoder().decode(RawRotation.self, from: data)
        return ArenaRotation(
            version: raw.arenaVersion,
            seasonId: raw.seasonId,
            sets: raw.arenaSets ?? [],
            multiclassArena: raw.multiclassArena ?? false,
            trustHearthArena: raw.trustHA ?? false
        )
    }
}

public struct HSReplayCardStatsProvider: CardMetricsProviding {
    private struct Response: Decodable {
        let data: [String: [RawCardStats]]
    }

    private struct RawCardStats: Decodable {
        let cardId: String
        let popularity: Double?
        let winRate: Double?
        let drawnWinRate: Double?
        let playedWinRate: Double?
        let numGames: Int?

        enum CodingKeys: String, CodingKey {
            case cardId = "card_id"
            case popularity
            case winRate = "win_rate"
            case drawnWinRate = "drawn_win_rate"
            case playedWinRate = "played_win_rate"
            case numGames = "num_games"
        }
    }

    public let source: MetricSource = .hsReplay
    private let loader: RemoteJSONLoader
    private let resource: RemoteJSONResource

    public init(loader: RemoteJSONLoader, resource: RemoteJSONResource = DataSourceEndpoints.hsReplayCardStats) {
        self.loader = loader
        self.resource = resource
    }

    public func loadMetrics() async throws -> [CardMetric] {
        let data = try await loader.load(resource)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let now = Date()
        return decoded.data.flatMap { className, cards in
            guard let arenaClass = ArenaClass(externalName: className) else {
                return [CardMetric]()
            }
            return cards.map {
                CardMetric(
                    cardId: $0.cardId,
                    classContext: arenaClass,
                    source: .hsReplay,
                    pickRate: $0.popularity,
                    includedWinRate: $0.winRate.map { round($0 * 10) / 10 },
                    drawnWinRate: $0.drawnWinRate.map { round($0 * 10) / 10 },
                    playedWinRate: $0.playedWinRate.map { round($0 * 10) / 10 },
                    sampleSize: $0.numGames,
                    updatedAt: now
                )
            }
        }
    }
}

public struct FirestoneCardStatsProvider: CardMetricsProviding {
    private struct Response: Decodable {
        let stats: [RawCardStats]
    }

    private struct RawCardStats: Decodable {
        let cardId: String
        let stats: RawStats
    }

    private struct RawStats: Decodable {
        let decksWithCard: Int
        let decksWithCardThenWin: Int
    }

    public let source: MetricSource = .firestone
    private let loader: RemoteJSONLoader
    private let resourcesByClass: [ArenaClass: RemoteJSONResource]

    public init(loader: RemoteJSONLoader, resourcesByClass: [ArenaClass: RemoteJSONResource] = DataSourceEndpoints.firestoneCardStats) {
        self.loader = loader
        self.resourcesByClass = resourcesByClass
    }

    public func loadMetrics() async throws -> [CardMetric] {
        var metrics: [CardMetric] = []
        let now = Date()
        for arenaClass in ArenaClass.allCases where arenaClass != .neutral {
            guard let resource = resourcesByClass[arenaClass] else {
                continue
            }
            let data = try await loader.load(resource)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            metrics.append(contentsOf: decoded.stats.map { item in
                let samples = item.stats.decksWithCard
                let winRate = samples > 0
                    ? round((Double(item.stats.decksWithCardThenWin) / Double(samples)) * 1000) / 10
                    : nil
                return CardMetric(
                    cardId: item.cardId,
                    classContext: arenaClass,
                    source: .firestone,
                    includedWinRate: winRate,
                    sampleSize: samples,
                    updatedAt: now
                )
            })
        }
        return metrics
    }
}
