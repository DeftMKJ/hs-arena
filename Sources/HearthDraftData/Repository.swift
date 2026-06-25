import Foundation

public actor DraftDataRepository {
    private var cardsById: [String: CardMetadata] = [:]
    private var cardIdsByNormalizedName: [String: [String]] = [:]
    private var metricsByClassAndCard: [ArenaClass: [String: [MetricSource: CardMetric]]] = [:]
    private var rotation: ArenaRotation?

    public init() {}

    public func replaceCards(_ cards: [CardMetadata]) {
        cardsById = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        cardIdsByNormalizedName = buildNameIndex(cards)
    }

    public func replaceMetrics(_ metrics: [CardMetric], source: MetricSource) {
        for arenaClass in ArenaClass.allCases {
            guard var cardMetrics = metricsByClassAndCard[arenaClass] else {
                continue
            }

            for cardId in cardMetrics.keys {
                cardMetrics[cardId]?[source] = nil
                if cardMetrics[cardId]?.isEmpty == true {
                    cardMetrics.removeValue(forKey: cardId)
                }
            }

            metricsByClassAndCard[arenaClass] = cardMetrics
        }

        for metric in metrics {
            metricsByClassAndCard[metric.classContext, default: [:]][metric.cardId, default: [:]][source] = metric
        }
    }

    public func setRotation(_ rotation: ArenaRotation) {
        self.rotation = rotation
    }

    public func currentRotation() -> ArenaRotation? {
        rotation
    }

    public func isReadyForEvaluation() -> Bool {
        !cardsById.isEmpty && metricsByClassAndCard.values.contains { !$0.isEmpty }
    }

    public func card(id: String) -> CardMetadata? {
        cardsById[id]
    }

    public func resolveCardInput(_ input: String, classContext: ArenaClass) -> CardInputResolution {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CardInputResolution(input: input, cardId: nil)
        }

        if let card = cardsById[trimmed] {
            return CardInputResolution(input: input, cardId: card.id, matchedName: card.name)
        }
        if hasMetrics(cardId: trimmed, classContext: classContext) {
            return CardInputResolution(input: input, cardId: trimmed)
        }

        let normalizedInput = normalizeCardName(trimmed)
        if let exactId = cardsById.keys.first(where: { normalizeCardName($0) == normalizedInput }),
           let card = cardsById[exactId] {
            return CardInputResolution(input: input, cardId: exactId, matchedName: card.name)
        }
        if let metricId = metricsByClassAndCard[classContext]?.keys.first(where: { normalizeCardName($0) == normalizedInput })
            ?? metricsByClassAndCard[.neutral]?.keys.first(where: { normalizeCardName($0) == normalizedInput }) {
            return CardInputResolution(input: input, cardId: metricId)
        }

        let candidates = cardIdsByNormalizedName[normalizedInput] ?? []
        guard !candidates.isEmpty else {
            return CardInputResolution(input: input, cardId: nil)
        }

        let compatible = candidates.filter { cardId in
            guard let card = cardsById[cardId] else {
                return false
            }
            return isCard(card, playableBy: classContext)
        }
        let scopedCandidates = compatible.isEmpty ? candidates : compatible
        let selected = bestCandidate(from: scopedCandidates, classContext: classContext)
        return CardInputResolution(
            input: input,
            cardId: selected,
            matchedName: selected.flatMap { cardsById[$0]?.name },
            isAmbiguous: scopedCandidates.count > 1
        )
    }

    public func aggregate(cardId: String, classContext: ArenaClass) -> CardAggregate {
        // CORE_ 前缀 fallback：若原 ID 无数据，尝试去掉/加上 CORE_ 前缀
        let lookupId = effectiveLookupId(for: cardId, classContext: classContext)
        let direct = metricsByClassAndCard[classContext]?[lookupId] ?? [:]
        let neutral = metricsByClassAndCard[.neutral]?[lookupId] ?? [:]
        let merged = neutral.merging(direct) { _, direct in direct }
        return CardAggregate(
            cardId: cardId,
            metadata: cardsById[cardId] ?? cardsById[lookupId],
            hearthArena: merged[.hearthArena],
            hsReplay: merged[.hsReplay],
            firestone: merged[.firestone]
        )
    }

    // 若 cardId 在数据源里找不到，尝试 CORE_ 互转作为 fallback
    private func effectiveLookupId(for cardId: String, classContext: ArenaClass) -> String {
        if hasMetric(cardId, classContext: classContext) { return cardId }
        let alt: String
        if cardId.hasPrefix("CORE_") {
            alt = String(cardId.dropFirst(5))
        } else {
            alt = "CORE_" + cardId
        }
        return hasMetric(alt, classContext: classContext) ? alt : cardId
    }

    private func hasMetric(_ cardId: String, classContext: ArenaClass) -> Bool {
        (metricsByClassAndCard[classContext]?[cardId] != nil) ||
        (metricsByClassAndCard[.neutral]?[cardId] != nil)
    }

    public func evaluateDraftChoices(
        cardIds: [String],
        classContext: ArenaClass,
        preferredSource: MetricSource? = nil
    ) -> DraftChoiceEvaluation {
        let resolutions = cardIds.map { resolveCardInput($0, classContext: classContext) }
        let choices = resolutions.compactMap(\.cardId).map { aggregate(cardId: $0, classContext: classContext) }
        let recommendationsBySource = Dictionary(
            uniqueKeysWithValues: MetricSource.allCases.compactMap { source in
                bestChoice(in: choices, source: source).map { (source, $0.cardId) }
            }
        )
        let recommended = preferredSource.flatMap { recommendationsBySource[$0] }
            ?? recommendationsBySource[.firestone]
            ?? recommendationsBySource[.hsReplay]
            ?? recommendationsBySource[.hearthArena]
        return DraftChoiceEvaluation(
            classContext: classContext,
            inputResolutions: resolutions,
            choices: choices,
            recommendedCardId: recommended,
            recommendationsBySource: recommendationsBySource
        )
    }

    public func recognitionCandidates(for classContexts: [ArenaClass]) -> [CardRecognitionCandidate] {
        let contexts = classContexts.isEmpty ? ArenaClass.allCases.filter { $0 != .neutral } : classContexts
        return cardsById.values
            .filter { card in
                isRecognizableDraftCard(card)
                    && contexts.contains { context in isCard(card, playableBy: context) }
            }
            .map { card in
                let names = Array(Set([card.name] + Array(card.localizedNames.values)))
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .sorted()
                return CardRecognitionCandidate(
                    cardId: card.id,
                    displayName: card.name,
                    searchNames: names
                )
            }
            .sorted { left, right in
                if left.displayName == right.displayName {
                    return left.cardId < right.cardId
                }
                return left.displayName < right.displayName
            }
    }

    private func bestChoice(in choices: [CardAggregate], source: MetricSource) -> CardAggregate? {
        choices
            .compactMap { choice -> (CardAggregate, Double)? in
                rankingScore(choice, source: source).map { (choice, $0) }
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    private func rankingScore(_ aggregate: CardAggregate, source: MetricSource) -> Double? {
        switch source {
        case .hearthArena:
            aggregate.hearthArena?.score
        case .hsReplay:
            reliableScore(aggregate.hsReplay)
        case .firestone:
            reliableScore(aggregate.firestone)
        }
    }

    private func reliableScore(_ metric: CardMetric?) -> Double? {
        guard let metric, metric.hasReliableSample else {
            return nil
        }
        return metric.includedWinRate
    }

    private func buildNameIndex(_ cards: [CardMetadata]) -> [String: [String]] {
        var index: [String: [String]] = [:]
        for card in cards {
            let names = Set([card.name] + Array(card.localizedNames.values))
            for name in names {
                index[normalizeCardName(name), default: []].append(card.id)
            }
        }
        return index
    }

    private func normalizeCardName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func isCard(_ card: CardMetadata, playableBy classContext: ArenaClass) -> Bool {
        if card.cardClass == nil || card.cardClass == .neutral || card.cardClass == classContext {
            return true
        }
        return card.multiClass.contains(classContext) || card.multiClass.contains(.neutral)
    }

    private func isRecognizableDraftCard(_ card: CardMetadata) -> Bool {
        guard card.collectible else {
            return false
        }
        guard let type = card.type?.uppercased() else {
            return false
        }
        let supportedTypes: Set<String> = ["MINION", "SPELL", "WEAPON", "LOCATION"]
        guard supportedTypes.contains(type) else {
            return false
        }
        if let rarity = card.rarity?.uppercased(), rarity == "FREE" {
            return false
        }
        if let set = card.set?.uppercased(),
           set.contains("BATTLEGROUNDS") || set.contains("LETTUCE") || set.contains("MERCENARIES") || set == "CREDITS" {
            return false
        }
        return card.cost != nil
    }

    private func bestCandidate(from cardIds: [String], classContext: ArenaClass) -> String? {
        cardIds.max { lhs, rhs in
            candidateRank(lhs, classContext: classContext) < candidateRank(rhs, classContext: classContext)
        }
    }

    private func candidateRank(_ cardId: String, classContext: ArenaClass) -> Double {
        let id = effectiveLookupId(for: cardId, classContext: classContext)
        if let firestone = metricsByClassAndCard[classContext]?[id]?[.firestone]?.sampleSize {
            return 3_000_000 + Double(firestone)
        }
        if let hsReplay = metricsByClassAndCard[classContext]?[id]?[.hsReplay]?.sampleSize {
            return 2_000_000 + Double(hsReplay)
        }
        if metricsByClassAndCard[classContext]?[id]?[.hearthArena] != nil {
            return 1_000_000
        }
        if metricsByClassAndCard[.neutral]?[id]?[.hearthArena] != nil {
            return 500_000
        }
        return 0
    }

    private func hasMetrics(cardId: String, classContext: ArenaClass) -> Bool {
        metricsByClassAndCard[classContext]?[cardId]?.isEmpty == false
            || metricsByClassAndCard[.neutral]?[cardId]?.isEmpty == false
    }
}
