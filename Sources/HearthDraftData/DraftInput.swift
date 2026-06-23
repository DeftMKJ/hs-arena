import Foundation

public enum DraftInputEventKind: String, Codable, Sendable, Equatable {
    case arenaStarted
    case draftStarted
    case draftContinued
    case cardPicked
    case deckCardRead
    case activeDeck
    case rewards
}

public struct DraftInputEvent: Codable, Sendable, Equatable {
    public let kind: DraftInputEventKind
    public let cardId: String?
    public let heroNumber: String?
    public let rawLine: String
    public let sourcePath: String
    public let lineNumber: Int
    public let emittedAt: Date

    public init(
        kind: DraftInputEventKind,
        cardId: String? = nil,
        heroNumber: String? = nil,
        rawLine: String,
        sourcePath: String,
        lineNumber: Int,
        emittedAt: Date = Date()
    ) {
        self.kind = kind
        self.cardId = cardId
        self.heroNumber = heroNumber
        self.rawLine = rawLine
        self.sourcePath = sourcePath
        self.lineNumber = lineNumber
        self.emittedAt = emittedAt
    }
}

public struct HearthstoneLogLocation: Sendable, Equatable {
    public let hearthstoneDirectory: URL?
    public let logsDirectory: URL
    public let configFile: URL?
    public let wasAutoDiscovered: Bool

    public init(
        hearthstoneDirectory: URL?,
        logsDirectory: URL,
        configFile: URL?,
        wasAutoDiscovered: Bool
    ) {
        self.hearthstoneDirectory = hearthstoneDirectory
        self.logsDirectory = logsDirectory
        self.configFile = configFile
        self.wasAutoDiscovered = wasAutoDiscovered
    }
}

public struct HearthstoneLogStatus: Sendable, Equatable {
    public let location: HearthstoneLogLocation?
    public let activeLogDirectory: URL?
    public let watchedFiles: [URL]
    public let isRunning: Bool
    public let lastEvent: DraftInputEvent?
    public let message: String

    public init(
        location: HearthstoneLogLocation?,
        activeLogDirectory: URL?,
        watchedFiles: [URL],
        isRunning: Bool,
        lastEvent: DraftInputEvent?,
        message: String
    ) {
        self.location = location
        self.activeLogDirectory = activeLogDirectory
        self.watchedFiles = watchedFiles
        self.isRunning = isRunning
        self.lastEvent = lastEvent
        self.message = message
    }
}

public struct DraftScreenshotRecognitionResult: Sendable, Equatable {
    public let imageURL: URL
    public let recognizedCardIds: [String]
    public let recognizedCardIdSlots: [String?]
    public let confidence: Double?
    public let notes: [String]

    public init(
        imageURL: URL,
        recognizedCardIds: [String],
        recognizedCardIdSlots: [String?]? = nil,
        confidence: Double? = nil,
        notes: [String] = []
    ) {
        self.imageURL = imageURL
        self.recognizedCardIds = recognizedCardIds
        self.recognizedCardIdSlots = recognizedCardIdSlots ?? recognizedCardIds.map(Optional.some)
        self.confidence = confidence
        self.notes = notes
    }
}

public struct CardRecognitionCandidate: Sendable, Equatable {
    public let cardId: String
    public let displayName: String
    public let searchNames: [String]

    public init(cardId: String, displayName: String, searchNames: [String] = []) {
        self.cardId = cardId
        self.displayName = displayName
        self.searchNames = searchNames.isEmpty ? [displayName] : searchNames
    }
}
