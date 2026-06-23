import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision

protocol DraftScreenshotRecognizing: Sendable {
    func recognizeCards(
        from imageURL: URL,
        candidates: [CardRecognitionCandidate]
    ) async throws -> DraftScreenshotRecognitionResult
}

struct OpenCVDraftScreenshotRecognizer: DraftScreenshotRecognizing {
    private let imageCache = CardImageFeatureCache()
    private let reliableDistanceThreshold = 0.46
    private let reliableTextThreshold = 0.72

    func recognizeCards(
        from imageURL: URL,
        candidates: [CardRecognitionCandidate]
    ) async throws -> DraftScreenshotRecognitionResult {
        var trace = RecognitionTrace()
        trace.log("开始截图识别：\(imageURL.path)")
        let loadStart = DispatchTime.now()
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }
        let size = image.cgImage.map { "\($0.width)x\($0.height)" } ?? "unknown"
        trace.logStage("加载截图", since: loadStart, detail: "尺寸 \(size)")
        trace.log("候选卡数量：\(candidates.count)")
        guard !candidates.isEmpty else {
            return DraftScreenshotRecognitionResult(
                imageURL: imageURL,
                recognizedCardIds: [],
                confidence: nil,
                notes: ["当前确认职业下没有可用于图像匹配的 HearthArena 候选卡。请先刷新数据并确认职业。"] + trace.finishedRows()
            )
        }

        let textResult = recognizeByText(from: image, imageURL: imageURL, candidates: candidates, trace: &trace)
        if textResult.acceptedCardIds.count == 3 {
            let confidence = textResult.acceptedMatches.map(\.score).reduce(0, +) / Double(textResult.acceptedMatches.count)
            return DraftScreenshotRecognitionResult(
                imageURL: imageURL,
                recognizedCardIds: textResult.acceptedCardIds,
                recognizedCardIdSlots: textResult.acceptedCardIdSlots,
                confidence: confidence,
                notes: [
                    "识别方式：OpenCV 思路负责固定裁剪三张牌名区域，Apple Vision OCR 读取文字，再用 HearthstoneJSON 卡名模糊匹配。",
                    "截图布局：\(textResult.layout.name)。",
                    "候选范围：已确认职业可用的可收藏卡牌，共 \(candidates.count) 张；识别不再要求 HearthArena 有分。",
                    "OCR 结果：\(textResult.acceptedMatches.map { "第 \($0.index + 1) 张「\($0.rawText)」-> \($0.candidate.displayName)（\($0.candidate.cardId)，相似度 \(String(format: "%.1f", $0.score * 100))%）" }.joined(separator: "；"))",
                    textResult.debugDirectory.map { "调试目录：\($0.path)" } ?? "调试目录：写入失败"
                ] + textResult.debugRows + trace.finishedRows()
            )
        }
        if !textResult.acceptedCardIds.isEmpty {
            let confidence = textResult.acceptedMatches.map(\.score).reduce(0, +) / Double(textResult.acceptedMatches.count)
            let missingSlots = textResult.acceptedCardIdSlots.enumerated().compactMap { index, cardId in
                cardId == nil ? "第 \(index + 1) 张" : nil
            }
            return DraftScreenshotRecognitionResult(
                imageURL: imageURL,
                recognizedCardIds: textResult.acceptedCardIds,
                recognizedCardIdSlots: textResult.acceptedCardIdSlots,
                confidence: confidence,
                notes: [
                    "识别方式：Vision OCR 部分识别成功，已保留命中的槽位；未进入 OpenCV 兜底，避免错误结果覆盖。",
                    "截图布局：\(textResult.layout.name)。",
                    "候选范围：已确认职业可用的可收藏卡牌，共 \(candidates.count) 张；识别不再要求 HearthArena 有分。",
                    "OCR 命中：\(textResult.acceptedCardIds.count)/3。",
                    missingSlots.isEmpty ? "三张牌均已识别。" : "需要人工补充：\(missingSlots.joined(separator: "，"))。",
                    textResult.debugDirectory.map { "调试目录：\($0.path)" } ?? "调试目录：写入失败"
                ] + textResult.debugRows + trace.finishedRows()
            )
        }

        trace.log("OCR 未完整命中三张牌，进入 OpenCV 图像匹配兜底。OCR命中 \(textResult.acceptedCardIds.count)/3")
        let imageLoadStart = DispatchTime.now()
        let candidateImages = await imageCache.images(for: candidates)
        trace.logStage("加载候选卡图", since: imageLoadStart, detail: "成功 \(candidateImages.count)/\(candidates.count)")
        guard !candidateImages.isEmpty else {
            return DraftScreenshotRecognitionResult(
                imageURL: imageURL,
                recognizedCardIds: [],
                confidence: nil,
                notes: [
                    "没有成功加载候选卡图，无法做图像匹配。",
                    "请确认网络可访问 art.hearthstonejson.com，或稍后重试。"
                ] + trace.finishedRows()
            )
        }

        let imageMatchStart = DispatchTime.now()
        let layoutMatches = screenshotLayouts().compactMap { layout -> LayoutMatch? in
            let layoutStart = DispatchTime.now()
            var cardImages: [UIImage] = []
            var screenImages: [UIImage] = []
            for cardRegion in layout.cardRegions {
                guard let cardImage = try? image.cropped(normalizedCrop: cardRegion),
                      let artworkImage = try? cardImage.cropped(normalizedCrop: layout.artworkRegion) else {
                    return nil
                }
                cardImages.append(cardImage)
                screenImages.append(artworkImage)
            }
            guard !screenImages.isEmpty else {
                return nil
            }

            var matches: [CardImageMatch] = []
            var topMatchesByCard: [[CardImageMatch]] = []
            var debugRows: [String] = []
            for (index, screenImage) in screenImages.enumerated() {
                let cardMatchStart = DispatchTime.now()
                let rankedMatches = candidateImages.map { candidate in
                    CardImageMatch(
                        candidate: candidate.candidate,
                        candidateArtworkImage: candidate.artworkImage,
                        distance: OpenCVDraftImageMatcher.combinedDistanceBetweenImage(
                            screenImage,
                            secondImage: candidate.artworkImage
                        )
                    )
                }.sorted { left, right in
                    left.distance < right.distance
                }
                guard let best = rankedMatches.first else {
                    continue
                }
                matches.append(best)
                let topMatches = Array(rankedMatches.prefix(3))
                topMatchesByCard.append(topMatches)
                let top3 = topMatches.map {
                    "\($0.candidate.displayName) \($0.candidate.cardId) 距离 \(String(format: "%.4f", $0.distance))"
                }.joined(separator: "；")
                debugRows.append("第 \(index + 1) 张 Top3：\(top3)")
                debugRows.append("第 \(index + 1) 张图像匹配耗时：\(RecognitionTrace.formatElapsed(since: cardMatchStart))")
            }

            guard !matches.isEmpty else {
                return nil
            }
            let averageDistance = matches.map(\.distance).reduce(0, +) / Double(matches.count)
            return LayoutMatch(
                layout: layout,
                cardImages: cardImages,
                artworkImages: screenImages,
                matches: matches,
                topMatchesByCard: topMatchesByCard,
                averageDistance: averageDistance,
                debugRows: debugRows + ["布局 \(layout.name) 图像匹配耗时：\(RecognitionTrace.formatElapsed(since: layoutStart))"]
            )
        }
        trace.logStage("OpenCV 图像匹配", since: imageMatchStart, detail: "布局候选 \(layoutMatches.count)")

        guard let bestLayoutMatch = layoutMatches.min(by: { left, right in left.averageDistance < right.averageDistance }) else {
            return DraftScreenshotRecognitionResult(
                imageURL: imageURL,
                recognizedCardIds: [],
                confidence: nil,
                notes: ["没有成功从截图中裁出可匹配的三张卡牌区域。"] + trace.finishedRows()
            )
        }

        let matches = bestLayoutMatch.matches
        let reliableMatches = matches.filter { $0.distance <= reliableDistanceThreshold }

        let recognized = reliableMatches.map(\.candidate.cardId)
        let averageDistance = bestLayoutMatch.averageDistance
        let confidence = max(0, min(1, 1 - (averageDistance / reliableDistanceThreshold)))
        let detail = matches.map { match in
            "\(match.candidate.displayName)（\(match.candidate.cardId)，HSV距离 \(String(format: "%.4f", match.distance))）"
        }
        let unreliable = matches.enumerated().filter { _, match in
            match.distance > reliableDistanceThreshold
        }.map { index, match in
            "第 \(index + 1) 张 \(match.candidate.displayName) 距离 \(String(format: "%.4f", match.distance)) 超过阈值 \(String(format: "%.2f", reliableDistanceThreshold))"
        }
        let debugStart = DispatchTime.now()
        let debugDirectory = writeDebugArtifacts(imageURL: imageURL, originalImage: image, layoutMatch: bestLayoutMatch, traceRows: trace.rows)
        trace.logStage("写入图像调试文件", since: debugStart, detail: debugDirectory?.path ?? "失败")

        return DraftScreenshotRecognitionResult(
            imageURL: imageURL,
            recognizedCardIds: recognized,
            confidence: confidence,
            notes: [
                "识别方式：Vision OCR 未完整识别三张牌，已降级为 OpenCV HSV 直方图 + ORB 关键点综合匹配。",
                "OCR 初步结果：\(textResult.summary)",
                "截图布局：\(bestLayoutMatch.layout.name)。",
                "候选范围：已确认职业可用的可收藏卡牌，共 \(candidates.count) 张；识别不再要求 HearthArena 有分。",
                "匹配结果：\(detail.joined(separator: "；"))",
                "综合距离越小越像；超过 \(String(format: "%.2f", reliableDistanceThreshold)) 的结果不会自动填入，避免乱识别。",
                unreliable.isEmpty ? "所有自动填入结果均在当前可信阈值内。" : "未自动填入：\(unreliable.joined(separator: "；"))",
                debugDirectory.map { "调试目录：\($0.path)" } ?? "调试目录：写入失败",
                bestLayoutMatch.debugRows.joined(separator: "\n")
            ] + trace.finishedRows()
        )
    }

    private func screenshotLayouts() -> [ScreenshotLayout] {
        [
            ScreenshotLayout(
                name: "完整竞技场选牌界面",
                cardRegions: cardRegions(centers: [0.282, 0.500, 0.718], width: 0.17, topY: 0.23, height: 0.46),
                artworkRegion: CGRect(x: 0.30, y: 0.12, width: 0.42, height: 0.36),
                nameRegions: titleCandidateRegions()
            ),
            ScreenshotLayout(
                name: "三张卡牌近景截图",
                cardRegions: cardRegions(centers: [0.18, 0.50, 0.82], width: 0.28, topY: 0.02, height: 0.96),
                artworkRegion: CGRect(x: 0.27, y: 0.08, width: 0.44, height: 0.32),
                nameRegions: titleCandidateRegions()
            )
        ]
    }

    private func titleCandidateRegions() -> [CGRect] {
        [
            CGRect(x: 0.00, y: 0.28, width: 1.00, height: 0.30),
            CGRect(x: 0.02, y: 0.30, width: 0.96, height: 0.22),
            CGRect(x: 0.06, y: 0.34, width: 0.88, height: 0.20),
            CGRect(x: 0.10, y: 0.37, width: 0.80, height: 0.18)
        ]
    }

    private func cardRegions(centers: [CGFloat], width: CGFloat, topY: CGFloat, height: CGFloat) -> [CGRect] {
        centers.map { centerX in
            CGRect(x: centerX - width / 2, y: topY, width: width, height: height)
        }
    }

    private func writeDebugArtifacts(
        imageURL: URL,
        originalImage: UIImage,
        layoutMatch: LayoutMatch,
        traceRows: [String]
    ) -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = base
            .appendingPathComponent("HearthStoneDraftAssistant", isDirectory: true)
            .appendingPathComponent("ScreenshotDebug", isDirectory: true)
            .appendingPathComponent("\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try originalImage.writePNG(to: directory.appendingPathComponent("00-original.png"))
            for (index, image) in layoutMatch.cardImages.enumerated() {
                try image.writePNG(to: directory.appendingPathComponent("card-\(index + 1)-full.png"))
            }
            for (index, image) in layoutMatch.artworkImages.enumerated() {
                try image.writePNG(to: directory.appendingPathComponent("card-\(index + 1)-artwork.png"))
            }
            for (cardIndex, matches) in layoutMatch.topMatchesByCard.enumerated() {
                for (matchIndex, match) in matches.enumerated() {
                    let distance = String(format: "%.4f", match.distance)
                    let filename = "card-\(cardIndex + 1)-top-\(matchIndex + 1)-\(sanitized(match.candidate.cardId))-\(distance).png"
                    try match.candidateArtworkImage.writePNG(to: directory.appendingPathComponent(filename))
                }
            }
            let summary = ([
                "source: \(imageURL.path)",
                "layout: \(layoutMatch.layout.name)",
                "average distance: \(String(format: "%.4f", layoutMatch.averageDistance))"
            ] + layoutMatch.debugRows + ["", "trace:"] + traceRows).joined(separator: "\n")
            try summary.write(to: directory.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
            return directory
        } catch {
            return nil
        }
    }

    private func sanitized(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    private func recognizeByText(
        from image: UIImage,
        imageURL: URL,
        candidates: [CardRecognitionCandidate],
        trace: inout RecognitionTrace
    ) -> TextLayoutMatch {
        let ocrChainStart = DispatchTime.now()
        trace.log("进入 OCR 链路：布局 \(screenshotLayouts().count) 个，候选卡 \(candidates.count) 张")
        let indexStart = DispatchTime.now()
        let nameIndex = buildNameSearchIndex(candidates)
        trace.logStage("构建卡名索引", since: indexStart, detail: "名称 \(nameIndex.count)")
        var layoutResults: [TextLayoutMatch] = []
        for layout in screenshotLayouts() {
            let layoutStart = DispatchTime.now()
            var cardImages: [UIImage] = []
            var nameImages: [UIImage] = []
            var acceptedMatches: [CardTextMatch] = []
            var candidateRows: [String] = []

            for (index, cardRegion) in layout.cardRegions.enumerated() {
                let cardStart = DispatchTime.now()
                guard let cardImage = try? image.cropped(normalizedCrop: cardRegion) else {
                    trace.log("OCR布局 \(layout.name) 第 \(index + 1) 张裁剪失败")
                    continue
                }
                cardImages.append(cardImage)
                let cropStart = DispatchTime.now()
                let titleImages = layout.nameRegions.compactMap { try? cardImage.cropped(normalizedCrop: $0) }
                nameImages.append(contentsOf: titleImages)
                let cropElapsed = RecognitionTrace.formatElapsed(since: cropStart)

                let ocrStart = DispatchTime.now()
                let rawTexts = Array(NSOrderedSet(array: recognizeTextLines(in: cardImage) + titleImages.flatMap { recognizeTextLines(in: $0) })) as? [String] ?? []
                let ocrElapsed = RecognitionTrace.formatElapsed(since: ocrStart)
                let matchStart = DispatchTime.now()
                let topMatches = bestTextMatches(rawTexts: rawTexts, nameIndex: nameIndex, limit: 3)
                let matchElapsed = RecognitionTrace.formatElapsed(since: matchStart)
                let rawSummary = rawTexts.isEmpty ? "未读到文字" : rawTexts.joined(separator: " / ")
                if let best = topMatches.first, isReliableTextMatch(best) {
                    acceptedMatches.append(CardTextMatch(index: index, rawText: best.rawText, candidate: best.candidate, matchedName: best.matchedName, score: best.score))
                }
                let topSummary = topMatches.isEmpty ? "无候选" : topMatches.map {
                    "\($0.candidate.displayName) \($0.candidate.cardId) 相似度 \(String(format: "%.1f", $0.score * 100))%"
                }.joined(separator: "；")
                let accepted = topMatches.first.map(isReliableTextMatch) == true ? "接受" : "未接受"
                candidateRows.append("第 \(index + 1) 张 OCR：\(rawSummary)；Top3：\(topSummary)；\(accepted)")
                candidateRows.append("第 \(index + 1) 张耗时：标题裁剪 \(cropElapsed)，Vision OCR \(ocrElapsed)，名称匹配 \(matchElapsed)，单卡总计 \(RecognitionTrace.formatElapsed(since: cardStart))")
            }

            guard !cardImages.isEmpty else {
                continue
            }
            let score = acceptedMatches.map(\.score).reduce(0, +) + Double(acceptedMatches.count)
            let result = TextLayoutMatch(
                layout: layout,
                cardImages: cardImages,
                nameImages: nameImages,
                acceptedMatches: acceptedMatches,
                debugRows: candidateRows,
                rankingScore: score,
                debugDirectory: nil
            )
            layoutResults.append(result)
            trace.logStage("OCR布局 \(layout.name)", since: layoutStart, detail: "命中 \(acceptedMatches.count)/3，评分 \(String(format: "%.3f", score))")
        }
        trace.logStage("OCR完整链路", since: ocrChainStart, detail: "布局结果 \(layoutResults.count)")

        var best = layoutResults.max { left, right in
            left.rankingScore < right.rankingScore
        } ?? TextLayoutMatch(
            layout: screenshotLayouts()[0],
            cardImages: [],
            nameImages: [],
            acceptedMatches: [],
            debugRows: ["没有成功裁出可 OCR 的牌名区域。"],
            rankingScore: 0,
            debugDirectory: nil
        )
        trace.log("OCR最佳布局：\(best.layout.name)，命中 \(best.acceptedCardIds.count)/3")
        let debugStart = DispatchTime.now()
        best.debugDirectory = writeTextDebugArtifacts(imageURL: imageURL, originalImage: image, textMatch: best, traceRows: trace.rows)
        trace.logStage("写入OCR调试文件", since: debugStart, detail: best.debugDirectory?.path ?? "失败")
        return best
    }

    private func recognizeTextLines(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else {
            return []
        }

        var recognized: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            recognized = observations
                .flatMap { $0.topCandidates(3) }
                .map(\.string)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        do {
            try VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation, options: [:]).perform([request])
        } catch {
            return []
        }
        return Array(NSOrderedSet(array: recognized)) as? [String] ?? recognized
    }

    private func bestTextMatches(
        rawTexts: [String],
        nameIndex: [CardNameIndexEntry],
        limit: Int
    ) -> [CardTextCandidateMatch] {
        var matches: [CardTextCandidateMatch] = []
        for rawText in rawTexts {
            let normalizedRaw = normalizeOCRText(rawText)
            guard isLikelyCardNameText(normalizedRaw) else {
                continue
            }
            let rawCharacters = Set(normalizedRaw)
            for entry in nameIndex {
                let lengthGap = abs(entry.normalizedName.count - normalizedRaw.count)
                guard lengthGap <= 3 else {
                    continue
                }
                let sharedCharacters = rawCharacters.intersection(entry.characters).count
                guard sharedCharacters > 0 else {
                    continue
                }
                if normalizedRaw.count >= 4, sharedCharacters < 2 {
                    continue
                }

                let score = textSimilarity(normalizedRaw, entry.normalizedName)
                if score >= 0.50 {
                    matches.append(CardTextCandidateMatch(rawText: rawText, candidate: entry.candidate, matchedName: entry.name, score: score))
                }
            }
        }

        var bestByCard: [String: CardTextCandidateMatch] = [:]
        for match in matches {
            if (bestByCard[match.candidate.cardId]?.score ?? -1) < match.score {
                bestByCard[match.candidate.cardId] = match
            }
        }
        return bestByCard.values.sorted { left, right in
            if left.score == right.score {
                return left.candidate.displayName < right.candidate.displayName
            }
            return left.score > right.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private func buildNameSearchIndex(_ candidates: [CardRecognitionCandidate]) -> [CardNameIndexEntry] {
        var entries: [CardNameIndexEntry] = []
        var seen = Set<String>()
        for candidate in candidates {
            for name in candidate.searchNames {
                let normalizedName = normalizeOCRText(name)
                guard normalizedName.count >= 2, normalizedName.count <= 12 else {
                    continue
                }
                let key = "\(candidate.cardId)|\(normalizedName)"
                guard seen.insert(key).inserted else {
                    continue
                }
                entries.append(CardNameIndexEntry(
                    candidate: candidate,
                    name: name,
                    normalizedName: normalizedName,
                    characters: Set(normalizedName)
                ))
            }
        }
        return entries
    }

    private func isLikelyCardNameText(_ normalizedText: String) -> Bool {
        guard normalizedText.count >= 2, normalizedText.count <= 12 else {
            return false
        }
        if normalizedText.allSatisfy(\.isNumber) {
            return false
        }
        return true
    }

    private func isReliableTextMatch(_ match: CardTextCandidateMatch) -> Bool {
        if match.score >= reliableTextThreshold {
            return true
        }
        let raw = normalizeOCRText(match.rawText)
        let name = normalizeOCRText(match.matchedName)
        return min(raw.count, name.count) <= 3 && match.score >= 0.66
    }

    private func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs {
            return 1
        }
        if lhs.count >= 2, rhs.contains(lhs) {
            return min(0.96, Double(lhs.count) / Double(rhs.count) + 0.15)
        }
        if rhs.count >= 2, lhs.contains(rhs) {
            return min(0.94, Double(rhs.count) / Double(lhs.count) + 0.10)
        }

        let distance = levenshtein(lhs, rhs)
        return max(0, 1 - Double(distance) / Double(max(lhs.count, rhs.count)))
    }

    private func normalizeOCRText(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
        let scalars = folded.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for (leftIndex, leftCharacter) in left.enumerated() {
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let cost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + cost
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private func writeTextDebugArtifacts(
        imageURL: URL,
        originalImage: UIImage,
        textMatch: TextLayoutMatch,
        traceRows: [String]
    ) -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = base
            .appendingPathComponent("HearthStoneDraftAssistant", isDirectory: true)
            .appendingPathComponent("ScreenshotDebug", isDirectory: true)
            .appendingPathComponent("\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))-ocr", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try originalImage.writePNG(to: directory.appendingPathComponent("00-original.png"))
            for (index, image) in textMatch.cardImages.enumerated() {
                try image.writePNG(to: directory.appendingPathComponent("card-\(index + 1)-full.png"))
            }
            for (index, image) in textMatch.nameImages.enumerated() {
                try image.writePNG(to: directory.appendingPathComponent("card-\(index + 1)-name.png"))
            }
            let summary = ([
                "source: \(imageURL.path)",
                "layout: \(textMatch.layout.name)",
                "accepted: \(textMatch.acceptedCardIds.joined(separator: ","))"
            ] + textMatch.debugRows + ["", "trace:"] + traceRows).joined(separator: "\n")
            try summary.write(to: directory.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
            return directory
        } catch {
            return nil
        }
    }
}

private struct ScreenshotLayout {
    let name: String
    let cardRegions: [CGRect]
    let artworkRegion: CGRect
    let nameRegions: [CGRect]
}

private struct RecognitionTrace {
    private let startedAt = DispatchTime.now()
    private(set) var rows: [String] = []

    mutating func log(_ message: String) {
        let line = "[+\(Self.formatElapsed(since: startedAt))] \(message)"
        rows.append(line)
        NSLog("[DraftScreenshot] %@", line)
    }

    mutating func logStage(_ name: String, since start: DispatchTime, detail: String? = nil) {
        if let detail, !detail.isEmpty {
            log("\(name)完成，耗时 \(Self.formatElapsed(since: start))，\(detail)")
        } else {
            log("\(name)完成，耗时 \(Self.formatElapsed(since: start))")
        }
    }

    func finishedRows() -> [String] {
        ["耗时日志："] + rows + ["[总耗时] \(Self.formatElapsed(since: startedAt))"]
    }

    static func formatElapsed(since start: DispatchTime) -> String {
        let nanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let milliseconds = Double(nanos) / 1_000_000
        if milliseconds < 1 {
            return String(format: "%.2fms", milliseconds)
        }
        if milliseconds < 1_000 {
            return String(format: "%.1fms", milliseconds)
        }
        return String(format: "%.2fs", milliseconds / 1_000)
    }
}

private struct TextLayoutMatch {
    let layout: ScreenshotLayout
    let cardImages: [UIImage]
    let nameImages: [UIImage]
    let acceptedMatches: [CardTextMatch]
    let debugRows: [String]
    let rankingScore: Double
    var debugDirectory: URL?

    var acceptedCardIds: [String] {
        acceptedMatches.sorted { $0.index < $1.index }.map(\.candidate.cardId)
    }

    var acceptedCardIdSlots: [String?] {
        var slots = Array<String?>(repeating: nil, count: 3)
        for match in acceptedMatches {
            guard slots.indices.contains(match.index) else {
                continue
            }
            slots[match.index] = match.candidate.cardId
        }
        return slots
    }

    var summary: String {
        if debugRows.isEmpty {
            return "暂无 OCR 输出"
        }
        return debugRows.joined(separator: "；")
    }
}

private struct CardTextMatch {
    let index: Int
    let rawText: String
    let candidate: CardRecognitionCandidate
    let matchedName: String
    let score: Double
}

private struct CardTextCandidateMatch {
    let rawText: String
    let candidate: CardRecognitionCandidate
    let matchedName: String
    let score: Double
}

private struct CardNameIndexEntry {
    let candidate: CardRecognitionCandidate
    let name: String
    let normalizedName: String
    let characters: Set<Character>
}

private struct LayoutMatch {
    let layout: ScreenshotLayout
    let cardImages: [UIImage]
    let artworkImages: [UIImage]
    let matches: [CardImageMatch]
    let topMatchesByCard: [[CardImageMatch]]
    let averageDistance: Double
    let debugRows: [String]
}

private struct CardImageMatch {
    let candidate: CardRecognitionCandidate
    let candidateArtworkImage: UIImage
    let distance: Double
}

private actor CardImageFeatureCache {
    fileprivate struct CandidateImage {
        let candidate: CardRecognitionCandidate
        let artworkImage: UIImage
    }

    private var memoryCache: [String: UIImage] = [:]
    private let cacheRoot: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        cacheRoot = base
            .appendingPathComponent("HearthStoneDraftAssistant", isDirectory: true)
            .appendingPathComponent("CardImageCache", isDirectory: true)
    }

    fileprivate func images(for candidates: [CardRecognitionCandidate]) async -> [CandidateImage] {
        await withTaskGroup(of: CandidateImage?.self) { group in
            for candidate in candidates {
                group.addTask {
                    await self.candidateImage(for: candidate)
                }
            }

            var images: [CandidateImage] = []
            images.reserveCapacity(candidates.count)
            for await image in group {
                if let image {
                    images.append(image)
                }
            }
            return images
        }
    }

    private func candidateImage(for candidate: CardRecognitionCandidate) async -> CandidateImage? {
        if let artwork = memoryCache[candidate.cardId] {
            return CandidateImage(candidate: candidate, artworkImage: artwork)
        }

        guard let image = await loadCardImage(cardId: candidate.cardId),
              let artwork = try? image.cropped(pixelCrop: cardArtworkPixelRegion()) else {
            return nil
        }

        memoryCache[candidate.cardId] = artwork
        return CandidateImage(candidate: candidate, artworkImage: artwork)
    }

    private func cardArtworkPixelRegion() -> CGRect {
        // Arena-Tracker crops 59,70,82,82 from Hearthstone's 256px card render.
        CGRect(x: 59.0, y: 70.0, width: 82.0, height: 82.0)
    }

    private func loadCardImage(cardId: String) async -> UIImage? {
        let fileURL = cacheRoot
            .appendingPathComponent(sanitized(cardId))
            .appendingPathExtension("png")
        if let image = UIImage(contentsOfFile: fileURL.path) {
            return image
        }

        guard let url = URL(string: "https://art.hearthstonejson.com/v1/render/latest/zhCN/256x/\(cardId).png") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private func sanitized(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    func cropped(normalizedCrop: CGRect) throws -> UIImage {
        guard let cgImage else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let pixelRect = CGRect(
            x: normalizedCrop.minX * imageWidth,
            y: normalizedCrop.minY * imageHeight,
            width: normalizedCrop.width * imageWidth,
            height: normalizedCrop.height * imageHeight
        ).integral.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard !pixelRect.isEmpty,
              let cropped = cgImage.cropping(to: pixelRect) else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    func cropped(pixelCrop: CGRect) throws -> UIImage {
        guard let cgImage else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }

        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let pixelRect = pixelCrop.integral.intersection(imageBounds)
        guard !pixelRect.isEmpty,
              let cropped = cgImage.cropping(to: pixelRect) else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    func writePNG(to url: URL) throws {
        guard let data = pngData() else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }
        try data.write(to: url, options: .atomic)
    }
}

enum DraftScreenshotRecognitionError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "无法读取这张截图"
        }
    }
}

final class DraftScreenshotPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL) -> Void
    private let onCancel: () -> Void

    init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            onCancel()
            return
        }
        onPick(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel()
    }
}
