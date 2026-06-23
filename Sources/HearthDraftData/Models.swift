import Foundation

public enum ArenaClass: String, CaseIterable, Codable, Hashable, Sendable {
    case deathKnight = "Death Knight"
    case demonHunter = "Demon Hunter"
    case druid = "Druid"
    case hunter = "Hunter"
    case mage = "Mage"
    case paladin = "Paladin"
    case priest = "Priest"
    case rogue = "Rogue"
    case shaman = "Shaman"
    case warlock = "Warlock"
    case warrior = "Warrior"
    case neutral = "Neutral"

    public var hsReplayKey: String {
        switch self {
        case .deathKnight: "DEATHKNIGHT"
        case .demonHunter: "DEMONHUNTER"
        case .neutral: "NEUTRAL"
        default: rawValue.uppercased()
        }
    }

    public var firestoneKey: String {
        switch self {
        case .deathKnight: "deathknight"
        case .demonHunter: "demonhunter"
        default: rawValue.lowercased()
        }
    }

    public init?(externalName: String) {
        let normalized = externalName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        switch normalized {
        case "death knight", "deathknight": self = .deathKnight
        case "demon hunter", "demonhunter": self = .demonHunter
        case "druid": self = .druid
        case "hunter": self = .hunter
        case "mage": self = .mage
        case "paladin": self = .paladin
        case "priest": self = .priest
        case "rogue": self = .rogue
        case "shaman": self = .shaman
        case "warlock": self = .warlock
        case "warrior": self = .warrior
        case "neutral": self = .neutral
        default: return nil
        }
    }
}

public enum MetricSource: String, CaseIterable, Codable, Hashable, Sendable {
    case hearthArena
    case hsReplay
    case firestone

    public var minimumReliableSampleSize: Int? {
        switch self {
        case .hearthArena:
            nil
        case .hsReplay, .firestone:
            100
        }
    }
}

public struct CardMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let dbfId: Int?
    public let name: String
    public let localizedNames: [String: String]
    public let cardClass: ArenaClass?
    public let multiClass: [ArenaClass]
    public let rarity: String?
    public let type: String?
    public let cost: Int?
    public let collectible: Bool
    public let set: String?

    public init(
        id: String,
        dbfId: Int? = nil,
        name: String,
        localizedNames: [String: String] = [:],
        cardClass: ArenaClass? = nil,
        multiClass: [ArenaClass] = [],
        rarity: String? = nil,
        type: String? = nil,
        cost: Int? = nil,
        collectible: Bool = true,
        set: String? = nil
    ) {
        self.id = id
        self.dbfId = dbfId
        self.name = name
        self.localizedNames = localizedNames
        self.cardClass = cardClass
        self.multiClass = multiClass
        self.rarity = rarity
        self.type = type
        self.cost = cost
        self.collectible = collectible
        self.set = set
    }
}

public struct CardMetric: Codable, Equatable, Sendable {
    public let cardId: String
    public let classContext: ArenaClass
    public let source: MetricSource
    public let score: Double?
    public let pickRate: Double?
    public let includedWinRate: Double?
    public let drawnWinRate: Double?
    public let playedWinRate: Double?
    public let sampleSize: Int?
    public let updatedAt: Date

    public var hasReliableSample: Bool {
        guard let minimum = source.minimumReliableSampleSize else {
            return true
        }
        return (sampleSize ?? 0) >= minimum
    }

    public init(
        cardId: String,
        classContext: ArenaClass,
        source: MetricSource,
        score: Double? = nil,
        pickRate: Double? = nil,
        includedWinRate: Double? = nil,
        drawnWinRate: Double? = nil,
        playedWinRate: Double? = nil,
        sampleSize: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.cardId = cardId
        self.classContext = classContext
        self.source = source
        self.score = score
        self.pickRate = pickRate
        self.includedWinRate = includedWinRate
        self.drawnWinRate = drawnWinRate
        self.playedWinRate = playedWinRate
        self.sampleSize = sampleSize
        self.updatedAt = updatedAt
    }
}

public struct ArenaRotation: Codable, Equatable, Sendable {
    public let version: Int
    public let seasonId: Int?
    public let sets: [String]
    public let multiclassArena: Bool
    public let trustHearthArena: Bool

    public init(
        version: Int,
        seasonId: Int? = nil,
        sets: [String],
        multiclassArena: Bool = false,
        trustHearthArena: Bool = false
    ) {
        self.version = version
        self.seasonId = seasonId
        self.sets = sets
        self.multiclassArena = multiclassArena
        self.trustHearthArena = trustHearthArena
    }
}

public struct CardAggregate: Equatable, Sendable {
    public let cardId: String
    public let metadata: CardMetadata?
    public let hearthArena: CardMetric?
    public let hsReplay: CardMetric?
    public let firestone: CardMetric?
}

public struct CardInputResolution: Equatable, Sendable {
    public let input: String
    public let cardId: String?
    public let matchedName: String?
    public let isAmbiguous: Bool

    public init(input: String, cardId: String?, matchedName: String? = nil, isAmbiguous: Bool = false) {
        self.input = input
        self.cardId = cardId
        self.matchedName = matchedName
        self.isAmbiguous = isAmbiguous
    }
}

public struct DraftChoiceEvaluation: Equatable, Sendable {
    public let classContext: ArenaClass
    public let inputResolutions: [CardInputResolution]
    public let choices: [CardAggregate]
    public let recommendedCardId: String?
    public let recommendationsBySource: [MetricSource: String]
}
