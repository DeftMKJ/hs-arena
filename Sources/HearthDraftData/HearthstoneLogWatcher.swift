import Foundation

public protocol HearthstoneLogLocating: Sendable {
    func locate() -> HearthstoneLogLocation?
}

public struct DefaultHearthstoneLogLocator: HearthstoneLogLocating {
    private let explicitLogsDirectory: URL?

    public init(explicitLogsDirectory: URL? = nil) {
        self.explicitLogsDirectory = explicitLogsDirectory
    }

    public func locate() -> HearthstoneLogLocation? {
        if let explicitLogsDirectory, isDirectory(explicitLogsDirectory) {
            return HearthstoneLogLocation(
                hearthstoneDirectory: explicitLogsDirectory.deletingLastPathComponent(),
                logsDirectory: explicitLogsDirectory,
                configFile: defaultLogConfigURL(),
                wasAutoDiscovered: false
            )
        }

        let candidateDirectories = [
            URL(fileURLWithPath: "/Applications/Hearthstone", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Applications/Hearthstone", isDirectory: true)
        ]

        for directory in candidateDirectories {
            let logs = directory.appendingPathComponent("Logs", isDirectory: true)
            if isDirectory(logs) {
                return HearthstoneLogLocation(
                    hearthstoneDirectory: directory,
                    logsDirectory: logs,
                    configFile: defaultLogConfigURL(),
                    wasAutoDiscovered: true
                )
            }
        }

        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func defaultLogConfigURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Preferences/Blizzard/Hearthstone/log.config")
    }
}

public actor HearthstoneLogWatcher {
    public typealias EventHandler = @Sendable (DraftInputEvent) async -> Void

    private let locator: HearthstoneLogLocating
    private let pollInterval: TimeInterval
    private let components = ["LoadingScreen", "Arena", "Power", "Zone", "Asset"]
    private var eventHandler: EventHandler?
    private var task: Task<Void, Never>?
    private var offsets: [String: UInt64] = [:]
    private var lineNumbers: [String: Int] = [:]
    private var lastStatus = HearthstoneLogStatus(
        location: nil,
        activeLogDirectory: nil,
        watchedFiles: [],
        isRunning: false,
        lastEvent: nil,
        message: "日志监听尚未启动"
    )

    public init(
        locator: HearthstoneLogLocating = DefaultHearthstoneLogLocator(),
        pollInterval: TimeInterval = 1
    ) {
        self.locator = locator
        self.pollInterval = pollInterval
    }

    deinit {
        task?.cancel()
    }

    public func start(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
        task?.cancel()
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        lastStatus = HearthstoneLogStatus(
            location: lastStatus.location,
            activeLogDirectory: lastStatus.activeLogDirectory,
            watchedFiles: lastStatus.watchedFiles,
            isRunning: false,
            lastEvent: lastStatus.lastEvent,
            message: "日志监听已停止"
        )
    }

    public func status() -> HearthstoneLogStatus {
        lastStatus
    }

    public func ensureLogConfig() throws {
        guard let location = locator.locate(), let configFile = location.configFile else {
            return
        }

        try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        var content = (try? String(contentsOf: configFile, encoding: .utf8)) ?? ""
        var changed = false

        for component in components {
            let section = "[\(component)]"
            guard !content.contains(section) else {
                continue
            }

            if !content.hasSuffix("\n"), !content.isEmpty {
                content.append("\n")
            }
            content.append("\n\(section)\nLogLevel=1\nFilePrinting=true\n")
            if component == "Power" {
                content.append("Verbose=1\n")
            }
            changed = true
        }

        if changed || !FileManager.default.fileExists(atPath: configFile.path) {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func pollOnce() async {
        guard let location = locator.locate() else {
            lastStatus = HearthstoneLogStatus(
                location: nil,
                activeLogDirectory: nil,
                watchedFiles: [],
                isRunning: true,
                lastEvent: lastStatus.lastEvent,
                message: "未找到 Hearthstone 日志目录。默认会查找 /Applications/Hearthstone/Logs。"
            )
            return
        }

        guard let activeDirectory = latestLogDirectory(in: location.logsDirectory) else {
            lastStatus = HearthstoneLogStatus(
                location: location,
                activeLogDirectory: nil,
                watchedFiles: [],
                isRunning: true,
                lastEvent: lastStatus.lastEvent,
                message: "已找到日志目录，但还没有最近的日志子目录。启动炉石后会自动继续监听。"
            )
            return
        }

        let files = components.map { activeDirectory.appendingPathComponent("\($0).log") }
        lastStatus = HearthstoneLogStatus(
            location: location,
            activeLogDirectory: activeDirectory,
            watchedFiles: files,
            isRunning: true,
            lastEvent: lastStatus.lastEvent,
            message: "正在监听炉石日志"
        )

        for file in files {
            await readNewLines(from: file)
        }
    }

    private func latestLogDirectory(in logsDirectory: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .max { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
    }

    private func readNewLines(from fileURL: URL) async {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return
        }
        defer {
            try? handle.close()
        }

        let key = fileURL.path
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        let offset = min(offsets[key] ?? fileSize, fileSize)
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            offsets[key] = offset + UInt64(data.count)
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for rawLine in text.components(separatedBy: .newlines) where !rawLine.isEmpty {
                lineNumbers[key, default: 0] += 1
                if let event = parse(rawLine, sourcePath: key, lineNumber: lineNumbers[key] ?? 0) {
                    lastStatus = HearthstoneLogStatus(
                        location: lastStatus.location,
                        activeLogDirectory: lastStatus.activeLogDirectory,
                        watchedFiles: lastStatus.watchedFiles,
                        isRunning: true,
                        lastEvent: event,
                        message: "捕获到炉石日志事件：\(event.kind.rawValue)"
                    )
                    await eventHandler?(event)
                }
            }
        } catch {
            offsets[key] = fileSize
        }
    }

    private func parse(_ line: String, sourcePath: String, lineNumber: Int) -> DraftInputEvent? {
        if let hero = firstCapture(in: line, pattern: #"DraftManager\.OnChosen\(\): hero=HERO_(\d+)"#) {
            return DraftInputEvent(kind: .arenaStarted, heroNumber: hero, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        if let cardId = firstCapture(in: line, pattern: #"Client chooses: .* \(([\w_]+)\)"#) {
            return DraftInputEvent(kind: .cardPicked, cardId: cardId, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        if let hero = firstCapture(in: line, pattern: #"DraftManager\.OnChoicesAndContents - Draft Deck ID: \d+, Hero Card = HERO_(\d+)"#) {
            return DraftInputEvent(kind: .draftStarted, heroNumber: hero, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        if let cardId = firstCapture(in: line, pattern: #"DraftManager\.OnChoicesAndContents - Draft deck contains card ([\w_]+)"#) {
            return DraftInputEvent(kind: .deckCardRead, cardId: cardId, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        if line.contains("SetDraftMode - DRAFTING") {
            return DraftInputEvent(kind: .draftContinued, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        if line.contains("SetDraftMode - ACTIVE_DRAFT_DECK") {
            return DraftInputEvent(kind: .activeDeck, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        if line.contains("SetDraftMode - IN_REWARDS") {
            return DraftInputEvent(kind: .rewards, rawLine: line, sourcePath: sourcePath, lineNumber: lineNumber)
        }
        return nil
    }

    private func firstCapture(in line: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[captureRange])
    }
}
