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

// MARK: - iOS: Vision OCR only

struct VisionOnlyDraftScreenshotRecognizer: DraftScreenshotRecognizing {
    private let ocr = DraftTextRecognizer()

    func recognizeCards(
        from imageURL: URL,
        candidates: [CardRecognitionCandidate]
    ) async throws -> DraftScreenshotRecognitionResult {
        var trace = RecognitionTrace()
        trace.log("开始截图识别（Vision OCR）：\(imageURL.path)")
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            throw DraftScreenshotRecognitionError.unreadableImage
        }
        trace.log("候选卡数量：\(candidates.count)")
        guard !candidates.isEmpty else {
            return DraftScreenshotRecognitionResult(
                imageURL: imageURL,
                recognizedCardIds: [],
                confidence: nil,
                notes: ["当前确认职业下没有可用于识别的候选卡，请先刷新数据并确认职业。"] + trace.finishedRows()
            )
        }

        let textResult = ocr.recognizeByText(from: image, imageURL: imageURL, candidates: candidates, trace: &trace)
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
                    "识别方式：Apple Vision OCR + 卡名模糊匹配（iOS 模式）。",
                    "截图布局：\(textResult.layout.name)。",
                    "OCR 命中：\(textResult.acceptedCardIds.count)/3。",
                    missingSlots.isEmpty ? "三张牌均已识别。" : "未识别槽位：\(missingSlots.joined(separator: "，"))。",
                    "OCR 结果：\(textResult.acceptedMatches.map { "第 \($0.index + 1) 张「\($0.rawText)」→ \($0.candidate.displayName)（相似度 \(String(format: "%.1f", $0.score * 100))%）" }.joined(separator: "；"))"
                ] + textResult.debugRows + trace.finishedRows()
            )
        }

        return DraftScreenshotRecognitionResult(
            imageURL: imageURL,
            recognizedCardIds: [],
            confidence: nil,
            notes: [
                "Vision OCR 未识别出任何卡牌名称。",
                "请确保截图清晰且包含完整选牌界面，或手动填写卡牌名称。"
            ] + textResult.debugRows + trace.finishedRows()
        )
    }
}

// MARK: - macCatalyst: OpenCV image matching + Vision OCR

#if targetEnvironment(macCatalyst)
struct OpenCVDraftScreenshotRecognizer: DraftScreenshotRecognizing {
    private let imageCache = CardImageFeatureCache()
    private let ocr = DraftTextRecognizer()
    private let reliableDistanceThreshold = 0.46

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

        let textResult = ocr.recognizeByText(from: image, imageURL: imageURL, candidates: candidates, trace: &trace)
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

        trace.log("OCR 未完整命中三张牌，进入 OpenCV 图像匹配兜底，OCR命中 \(textResult.acceptedCardIds.count)/3")
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
        let layoutMatches = ocr.screenshotLayouts().compactMap { layout -> LayoutMatch? in
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

}
#endif

// MARK: - Shared OCR recognizer (all platforms)

struct DraftTextRecognizer {
    private let reliableTextThreshold = 0.80

    fileprivate func screenshotLayouts() -> [ScreenshotLayout] {
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
        // 牌名横幅在卡片区域的 y 约 55%~80%，横向居中；多个候选区从宽到窄提高 OCR 命中率
        [
            CGRect(x: 0.05, y: 0.55, width: 0.90, height: 0.25),
            CGRect(x: 0.08, y: 0.58, width: 0.84, height: 0.20),
            CGRect(x: 0.12, y: 0.61, width: 0.76, height: 0.17),
            CGRect(x: 0.15, y: 0.63, width: 0.70, height: 0.14)
        ]
    }

    private func cardRegions(centers: [CGFloat], width: CGFloat, topY: CGFloat, height: CGFloat) -> [CGRect] {
        centers.map { centerX in
            CGRect(x: centerX - width / 2, y: topY, width: width, height: height)
        }
    }

    // 用 VNDetectRectanglesRequest 在全图中找三张卡片的实际位置
    // 返回归一化 CGRect 数组（Vision 坐标系：左下角为原点），已转换为 UIKit 坐标系（左上角为原点）
    private func detectCardRects(in image: UIImage, trace: inout RecognitionTrace) -> [CGRect]? {
        guard let cgImage = image.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        guard imgW > 0, imgH > 0 else { return nil }

        var detectedRects: [VNRectangleObservation] = []
        let request = VNDetectRectanglesRequest { req, _ in
            detectedRects = (req.results as? [VNRectangleObservation]) ?? []
        }
        request.minimumSize = 0.06          // 至少占图宽/高 6%
        request.maximumObservations = 16    // 最多取 16 个候选
        request.minimumConfidence = 0.4
        request.quadratureTolerance = 25    // 允许一定程度的梯形

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
        guard (try? handler.perform([request])) != nil else { return nil }

        // Vision 坐标系：y=0 在底部，转换为 UIKit（y=0 在顶部）
        let uiRects = detectedRects.map { obs -> CGRect in
            let b = obs.boundingBox
            return CGRect(x: b.origin.x, y: 1 - b.origin.y - b.height, width: b.width, height: b.height)
        }

        // 筛选：高宽比 1.1~2.5（炉石卡片约 1.4），面积占全图 2%~35%
        let cardAspectMin: CGFloat = 1.1
        let cardAspectMax: CGFloat = 2.5
        let minArea: CGFloat = 0.02
        let maxArea: CGFloat = 0.35
        let cardCandidates = uiRects.filter { r in
            guard r.width > 0 else { return false }
            let aspect = r.height / r.width
            let area = r.width * r.height
            return aspect >= cardAspectMin && aspect <= cardAspectMax && area >= minArea && area <= maxArea
        }

        guard cardCandidates.count >= 3 else {
            trace.log("矩形检测：候选 \(cardCandidates.count) 个，不足3张，跳过自动布局")
            return nil
        }

        // 按 X 中心排序，取三个面积最大且均匀分布的
        let sorted = cardCandidates.sorted { $0.midX < $1.midX }

        // 用滑动窗口找三个间距最均匀的
        var bestTriple: (CGFloat, [CGRect]) = (.infinity, [])
        for i in 0..<(sorted.count - 2) {
            let triple = [sorted[i], sorted[i + 1], sorted[i + 2]]
            // 检查三个的 X 中心是否近似等间距
            let gaps = [triple[1].midX - triple[0].midX, triple[2].midX - triple[1].midX]
            let gapVariance = abs(gaps[0] - gaps[1]) / max(gaps[0], gaps[1], 0.001)
            // 检查三个的 Y 中心是否接近（同一行）
            let ys = triple.map { $0.midY }
            let ySpread = (ys.max()! - ys.min()!) / imgH * imgH  // 像素差
            if gapVariance < bestTriple.0 && ySpread < 0.25 {
                bestTriple = (gapVariance, triple)
            }
        }

        guard bestTriple.0 < 0.5 else {
            trace.log("矩形检测：找不到三个均匀分布的卡片矩形（最优方差 \(String(format: "%.2f", bestTriple.0))），跳过")
            return nil
        }

        trace.log("矩形检测：成功定位三张卡片，方差 \(String(format: "%.2f", bestTriple.0))，区域 \(bestTriple.1.map { String(format: "(%.2f,%.2f,%.2fx%.2f)", $0.origin.x, $0.origin.y, $0.width, $0.height) }.joined(separator: " "))")
        return bestTriple.1
    }

    // 把检测到的三个卡片 CGRect 转换为 ScreenshotLayout（nameRegions 相对于卡片区域）
    private func layoutFromDetectedRects(_ rects: [CGRect]) -> ScreenshotLayout {
        ScreenshotLayout(
            name: "自动检测卡片位置",
            cardRegions: rects,
            artworkRegion: .zero,
            nameRegions: titleCandidateRegions()
        )
    }

    // 全图一次 OCR，按 X 坐标把文字分配到左/中/右三个槽，每槽取最佳匹配
    // 返回 3 个元素（对应槽位），nil 表示该槽未识别
    private func recognizeByFullImageOCR(
        image: UIImage,
        nameIndex: [CardNameIndexEntry],
        trace: inout RecognitionTrace
    ) -> [CardTextCandidateMatch?] {
        let ocrStart = DispatchTime.now()
        let allTexts = recognizeLocatedTextLines(in: image)
        trace.logStage("全图OCR", since: ocrStart, detail: "读到 \(allTexts.count) 条文字")

        guard !allTexts.isEmpty else { return [nil, nil, nil] }

        // 找三张牌的 X 分界：把所有文字 midX 排序，用间距最大的两处做分割点
        // 假设图像左边是第1张、中间第2张、右边第3张（约各占1/3）
        // 用固定三等分作为分槽边界，比动态分割更稳定
        let slotBoundaries: [ClosedRange<CGFloat>] = [0.0...0.38, 0.31...0.69, 0.62...1.0]
        // 注意：左右槽有重叠区间，边界附近的文字会被两个槽都考虑，取最优

        var slotMatches: [CardTextCandidateMatch?] = [nil, nil, nil]

        for (slotIndex, xRange) in slotBoundaries.enumerated() {
            // 只取该槽 X 范围内的文字
            let slotTexts = allTexts.filter { xRange.contains($0.midX) }.map(\.text)
            let unique = Array(NSOrderedSet(array: slotTexts)) as? [String] ?? slotTexts
            guard !unique.isEmpty else { continue }

            let candidates = bestTextMatches(rawTexts: unique, nameIndex: nameIndex, limit: 3)
            // 全图OCR场景：当最优候选得分明显高于第二候选（或唯一候选）时，适当放宽门槛到0.60
            // 因为全图OCR已经通过坐标槽位限制了范围，误匹配风险较低
            let fullOCRThreshold: Double = (candidates.count == 1 || (candidates.count >= 2 && candidates[0].score - candidates[1].score >= 0.15)) ? 0.60 : reliableTextThreshold
            if let best = candidates.first, best.score >= fullOCRThreshold || isReliableTextMatch(best) {
                // 若多个槽都命中同一张牌，保留置信度更高的槽
                if let existing = (0..<3).compactMap({ slotMatches[$0] }).first(where: { $0.candidate.cardId == best.candidate.cardId }) {
                    if best.score > existing.score {
                        // 清除旧槽，填入新槽
                        for i in 0..<3 where slotMatches[i]?.candidate.cardId == best.candidate.cardId { slotMatches[i] = nil }
                        slotMatches[slotIndex] = best
                    }
                } else {
                    slotMatches[slotIndex] = best
                }
            }
            let summary = candidates.prefix(3).map { "\($0.candidate.displayName) \(String(format: "%.0f", $0.score * 100))%" }.joined(separator: "；")
            trace.log("全图OCR 槽\(slotIndex + 1) 文字：\(unique.joined(separator: "/"))；Top3：\(summary.isEmpty ? "无" : summary)")
        }

        return slotMatches
    }

    fileprivate func recognizeByText(
        from image: UIImage,
        imageURL: URL,
        candidates: [CardRecognitionCandidate],
        trace: inout RecognitionTrace
    ) -> TextLayoutMatch {
        let ocrChainStart = DispatchTime.now()
        trace.log("进入 OCR 链路：候选卡 \(candidates.count) 张")
        let indexStart = DispatchTime.now()
        let nameIndex = buildNameSearchIndex(candidates)
        trace.logStage("构建卡名索引", since: indexStart, detail: "名称 \(nameIndex.count)")

        // 第一步：全图OCR + 三槽分配（不依赖任何固定坐标）
        let fullOCRStart = DispatchTime.now()
        let fullImageSlots = recognizeByFullImageOCR(image: image, nameIndex: nameIndex, trace: &trace)
        let fullOCRHits = fullImageSlots.compactMap { $0 }.count
        trace.logStage("全图OCR分槽", since: fullOCRStart, detail: "命中 \(fullOCRHits)/3")

        if fullOCRHits == 3 {
            // 全部识别成功，直接返回结果，不再做固定布局扫描
            let acceptedMatches = fullImageSlots.enumerated().compactMap { index, match -> CardTextMatch? in
                guard let m = match else { return nil }
                return CardTextMatch(index: index, rawText: m.rawText, candidate: m.candidate, matchedName: m.matchedName, score: m.score)
            }
            let score = acceptedMatches.map(\.score).reduce(0, +) + Double(acceptedMatches.count)
            var result = TextLayoutMatch(
                layout: ScreenshotLayout(name: "全图OCR分槽", cardRegions: [], artworkRegion: .zero, nameRegions: []),
                cardImages: [],
                nameImages: [],
                acceptedMatches: acceptedMatches,
                debugRows: [],
                rankingScore: score,
                debugDirectory: nil
            )
            result.debugDirectory = writeTextDebugArtifacts(imageURL: imageURL, originalImage: image, textMatch: result, traceRows: trace.rows)
            trace.log("全图OCR分槽完整命中3张，跳过固定布局扫描")
            return result
        }

        // 第二步：固定布局扫描（兜底，用于部分命中或全图OCR失败的情况）
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
                // 只扫卡片下半部分（牌名横幅所在区域），避免卡图上方文字干扰
                let cardBottomHalf = (try? cardImage.cropped(normalizedCrop: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))) ?? cardImage
                let rawTexts = Array(NSOrderedSet(array: recognizeTextLines(in: cardBottomHalf) + titleImages.flatMap { recognizeTextLines(in: $0) })) as? [String] ?? []
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
        // 把全图OCR的部分命中也作为候选（可能比固定布局命中的槽不同）
        if fullOCRHits > 0 {
            let fullAccepted = fullImageSlots.enumerated().compactMap { index, match -> CardTextMatch? in
                guard let m = match else { return nil }
                return CardTextMatch(index: index, rawText: m.rawText, candidate: m.candidate, matchedName: m.matchedName, score: m.score)
            }
            let fullScore = fullAccepted.map(\.score).reduce(0, +) + Double(fullAccepted.count)
            layoutResults.append(TextLayoutMatch(
                layout: ScreenshotLayout(name: "全图OCR分槽", cardRegions: [], artworkRegion: .zero, nameRegions: []),
                cardImages: [], nameImages: [],
                acceptedMatches: fullAccepted,
                debugRows: [],
                rankingScore: fullScore,
                debugDirectory: nil
            ))
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

    // 带位置信息的 OCR 结果
    private struct LocatedText {
        let text: String
        let midX: CGFloat  // 归一化坐标 [0,1]，UIKit 坐标系（左上角原点）
        let midY: CGFloat
    }

    // 对图像做 OCR，返回每行文字及其中心坐标（UIKit 坐标系，左上角为原点）
    private func recognizeLocatedTextLines(in image: UIImage) -> [LocatedText] {
        guard let cgImage = image.cgImage else { return [] }

        var results: [LocatedText] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                // Vision 坐标系：y=0 在底部，转换为 UIKit：y = 1 - visionY
                let midX = obs.boundingBox.midX
                let midY = 1.0 - obs.boundingBox.midY
                for candidate in obs.topCandidates(3) {
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    results.append(LocatedText(text: text, midX: midX, midY: midY))
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        try? VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        ).perform([request])
        return results
    }

    private func recognizeTextLines(in image: UIImage) -> [String] {
        recognizeLocatedTextLines(in: image).map(\.text)
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
        if lhs == rhs { return 1 }

        if lhs.count >= 2, rhs.contains(lhs) {
            return min(0.96, Double(lhs.count) / Double(rhs.count) + 0.15)
        }
        if rhs.count >= 2, lhs.contains(rhs) {
            return min(0.94, Double(rhs.count) / Double(lhs.count) + 0.10)
        }

        let distance = levenshtein(lhs, rhs)
        let editScore = max(0, 1 - Double(distance) / Double(max(lhs.count, rhs.count)))

        // 字符覆盖率：候选名字中有多少比例的字符出现在 OCR 文本里
        // 中文 OCR 常见噪点是单个字被识别错，但大部分字还是对的
        // 若覆盖率高但 edit 距离因少数噪点字拉低了得分，给额外加分
        let nameChars = Set(rhs)  // rhs 是候选名（标准名），lhs 是 OCR 结果
        let coveredCount = nameChars.filter { lhs.contains($0) }.count
        let coverage = Double(coveredCount) / Double(max(nameChars.count, 1))
        // 只有名字较短（≤6字）且覆盖率高时才加分，避免误匹配长名字
        let coverageBonus: Double
        if rhs.count <= 6, coverage >= 0.6 {
            coverageBonus = coverage * 0.25
        } else {
            coverageBonus = 0
        }

        return min(0.95, max(editScore, editScore + coverageBonus))
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

fileprivate struct ScreenshotLayout {
    let name: String
    let cardRegions: [CGRect]
    let artworkRegion: CGRect
    let nameRegions: [CGRect]
}

fileprivate struct RecognitionTrace {
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

fileprivate struct TextLayoutMatch {
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

fileprivate struct CardTextMatch {
    let index: Int
    let rawText: String
    let candidate: CardRecognitionCandidate
    let matchedName: String
    let score: Double
}

fileprivate struct CardTextCandidateMatch {
    let rawText: String
    let candidate: CardRecognitionCandidate
    let matchedName: String
    let score: Double
}

fileprivate struct CardNameIndexEntry {
    let candidate: CardRecognitionCandidate
    let name: String
    let normalizedName: String
    let characters: Set<Character>
}

fileprivate struct LayoutMatch {
    let layout: ScreenshotLayout
    let cardImages: [UIImage]
    let artworkImages: [UIImage]
    let matches: [CardImageMatch]
    let topMatchesByCard: [[CardImageMatch]]
    let averageDistance: Double
    let debugRows: [String]
}

fileprivate struct CardImageMatch {
    let candidate: CardRecognitionCandidate
    let candidateArtworkImage: UIImage
    let distance: Double
}

fileprivate actor CardImageFeatureCache {
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
