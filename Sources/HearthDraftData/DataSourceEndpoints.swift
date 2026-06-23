import Foundation

public enum DataSourceEndpoints {
    private static let arenaTrackerRaw = "https://raw.githubusercontent.com/supertriodo/Arena-Tracker/master"

    public static let hearthArena = RemoteJSONResource(
        cacheKey: "hearthArena",
        versionURL: url("\(arenaTrackerRaw)/HearthArena/haVersion.json"),
        payloadURL: url("\(arenaTrackerRaw)/HearthArena/hearthArena.json"),
        cachePolicy: .versioned,
        versionField: "haVersion"
    )

    public static let hearthArenaOfficialHTML = RemoteJSONResource(
        cacheKey: "hearthArenaOfficialHTML",
        payloadURL: url("https://www.heartharena.com/zh-cn/tierlist"),
        cachePolicy: .oneDay
    )

    public static let cardsJSON = RemoteJSONResource(
        cacheKey: "hearthstoneJSONCards",
        payloadURL: url("https://api.hearthstonejson.com/v1/latest/all/cards.json"),
        cachePolicy: .oneDay
    )

    public static let arenaRotation = RemoteJSONResource(
        cacheKey: "arenaRotation",
        versionURL: url("\(arenaTrackerRaw)/Arena/arenaVersion.json"),
        payloadURL: url("\(arenaTrackerRaw)/Arena/arenaVersion.json"),
        cachePolicy: .versioned,
        versionField: "arenaVersion"
    )

    public static let hsReplayCardStats = RemoteJSONResource(
        cacheKey: "hsReplayCardStats",
        payloadURL: url("https://hsreplay.net/api/v1/arena/card_stats/free/?format=json"),
        cachePolicy: .oneDay
    )

    public static let hsReplayBundles = RemoteJSONResource(
        cacheKey: "hsReplayBundles",
        payloadURL: url("https://hsreplay.net/api/v1/arena/card_packages/free/?format=json"),
        cachePolicy: .oneDay
    )

    public static let firestoneCardStats: [ArenaClass: RemoteJSONResource] = Dictionary(
        uniqueKeysWithValues: ArenaClass.allCases
            .filter { $0 != .neutral }
            .map { arenaClass in
                let key = arenaClass.firestoneKey
                return (
                    arenaClass,
                    RemoteJSONResource(
                        cacheKey: "firestone-\(key)",
                        payloadURL: url("https://static.zerotoheroes.com/api/arena/stats/cards/arena-underground/last-patch/\(key).gz.json"),
                        cachePolicy: .oneDay
                    )
                )
            }
    )

    public static var catalog: [DataSourceDefinition] {
        [
            DataSourceDefinition(
                name: "HearthArena tier score",
                detail: "Arena-Tracker mirrors HearthArena scores, keyed by class and card id.",
                metricSource: .hearthArena,
                resource: hearthArena
            ),
            DataSourceDefinition(
                name: "HearthArena official tier page",
                detail: "Official localized HearthArena tier page, used as a fallback when the mirror misses card ids.",
                metricSource: .hearthArena,
                resource: hearthArenaOfficialHTML
            ),
            DataSourceDefinition(
                name: "HearthstoneJSON cards",
                detail: "Official HearthstoneJSON card metadata used to map ids to names, class, cost, rarity and type.",
                metricSource: nil,
                resource: cardsJSON
            ),
            DataSourceDefinition(
                name: "Arena rotation",
                detail: "Current Arena season and active card sets from Arena-Tracker.",
                metricSource: nil,
                resource: arenaRotation
            ),
            DataSourceDefinition(
                name: "HSReplay card stats",
                detail: "Free Arena card statistics, including pick rate and win-rate fields when available.",
                metricSource: .hsReplay,
                resource: hsReplayCardStats
            ),
            DataSourceDefinition(
                name: "HSReplay bundle stats",
                detail: "Free Arena package statistics. Kept for future bucket or offering analysis.",
                metricSource: .hsReplay,
                resource: hsReplayBundles
            )
        ] + firestoneCardStats
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { arenaClass, resource in
                DataSourceDefinition(
                    name: "Firestone \(arenaClass.rawValue)",
                    detail: "Per-class Arena card statistics from ZeroToHeroes static exports.",
                    metricSource: .firestone,
                    resource: resource
                )
            }
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid endpoint URL: \(string)")
        }
        return url
    }
}

public struct DataSourceDefinition: Sendable {
    public let name: String
    public let detail: String
    public let metricSource: MetricSource?
    public let resource: RemoteJSONResource

    public init(name: String, detail: String, metricSource: MetricSource?, resource: RemoteJSONResource) {
        self.name = name
        self.detail = detail
        self.metricSource = metricSource
        self.resource = resource
    }
}
