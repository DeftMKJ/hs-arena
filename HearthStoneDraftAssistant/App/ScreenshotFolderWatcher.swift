import Foundation

struct ScreenshotWatcherStatus: Sendable, Equatable {
    let watchedPaths: [URL]
    let isRunning: Bool
    let lastDetectedFile: URL?
    let message: String

    init(watchedPaths: [URL], isRunning: Bool, lastDetectedFile: URL?, message: String) {
        self.watchedPaths = watchedPaths
        self.isRunning = isRunning
        self.lastDetectedFile = lastDetectedFile
        self.message = message
    }
}

actor ScreenshotFolderWatcher {
    typealias FileHandler = @Sendable (URL) async -> Void

    private let pollInterval: TimeInterval
    private var watchedPaths: [URL]
    private var seenFiles: Set<String> = []
    private var task: Task<Void, Never>?
    private var fileHandler: FileHandler?
    private var lastDetectedFile: URL?
    private var lastStatus = ScreenshotWatcherStatus(
        watchedPaths: [],
        isRunning: false,
        lastDetectedFile: nil,
        message: "截图监听未启动"
    )

    init(watchedPaths: [URL] = [], pollInterval: TimeInterval = 1) {
        self.watchedPaths = watchedPaths.isEmpty ? Self.defaultPaths() : watchedPaths
        self.pollInterval = pollInterval
    }

    deinit {
        task?.cancel()
    }

    static func defaultPaths() -> [URL] {
        var paths: [URL] = []

        // 系统截图默认落到桌面
        let desktop = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        paths.append(desktop)

        // 炉石截图目录
        let hearthstonePaths = [
            URL(fileURLWithPath: "/Applications/Hearthstone/Screenshots"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/Hearthstone/Screenshots")
        ]
        for path in hearthstonePaths where FileManager.default.fileExists(atPath: path.path) {
            paths.append(path)
        }

        return paths
    }

    func start(fileHandler: @escaping FileHandler) {
        self.fileHandler = fileHandler
        // 把当前已存在的文件标记为已见，避免启动时误触发
        seedSeenFiles()
        task?.cancel()
        task = Task { [weak self] in
            await self?.runLoop()
        }
        updateStatus(isRunning: true, message: "截图监听已启动")
    }

    func stop() {
        task?.cancel()
        task = nil
        updateStatus(isRunning: false, message: "截图监听已停止")
    }

    func status() -> ScreenshotWatcherStatus {
        lastStatus
    }

    func setWatchedPaths(_ paths: [URL]) {
        watchedPaths = paths
        seenFiles.removeAll()
        seedSeenFiles()
        updateStatus(isRunning: lastStatus.isRunning, message: "监听路径已更新")
    }

    func currentWatchedPaths() -> [URL] {
        watchedPaths
    }

    private func seedSeenFiles() {
        for directory in watchedPaths {
            let files = imageFiles(in: directory)
            for file in files {
                seenFiles.insert(file.path)
            }
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            pollOnce()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func pollOnce() {
        var newFiles: [URL] = []
        for directory in watchedPaths {
            let files = imageFiles(in: directory)
            for file in files {
                guard !seenFiles.contains(file.path) else { continue }
                seenFiles.insert(file.path)
                newFiles.append(file)
            }
        }

        // 按修改时间排序，最新的最先处理
        let sorted = newFiles.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }

        for file in sorted {
            lastDetectedFile = file
            updateStatus(isRunning: true, message: "检测到新截图：\(file.lastPathComponent)")
            Task { [weak self] in
                await self?.fileHandler?(file)
            }
        }
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.filter { url in
            let ext = url.pathExtension.lowercased()
            let isImage = ext == "png" || ext == "jpg" || ext == "jpeg"
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            return isImage && isRegular
        }
    }

    private func updateStatus(isRunning: Bool, message: String) {
        lastStatus = ScreenshotWatcherStatus(
            watchedPaths: watchedPaths,
            isRunning: isRunning,
            lastDetectedFile: lastDetectedFile,
            message: message
        )
    }
}
