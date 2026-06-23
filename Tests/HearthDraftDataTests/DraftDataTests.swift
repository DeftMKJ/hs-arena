import Foundation
import Testing
@testable import HearthDraftData

@Suite("Draft data layer")
struct DraftDataTests {
    @Test("HearthArena provider normalizes class score maps")
    func hearthArenaProvider() async throws {
        let loader = RemoteJSONLoader(
            httpClient: MockHTTPClient(payloads: [:]),
            cache: MemoryPayloadCache(payloads: [
                "ha": #"{"Mage":{"CARD_001":70},"Neutral":{"CARD_002":65}}"#.data(using: .utf8)!,
                "haOfficial": """
                <section class="tab tierlist mage" id="mage">
                  <dl class="card score_80"><dt class="mage commons" data-card-image="https://cdn.heartharena.com/images/renders/zhCN/CS2_029.webp">火球术
                  </dt><dd class="score score_80">80</dd></dl>
                </section>
                <section class="tab tierlist paladin" id="paladin"></section>
                """.data(using: .utf8)!
            ])
        )
        let provider = HearthArenaProvider(
            loader: loader,
            resource: RemoteJSONResource(
                cacheKey: "ha",
                payloadURL: URL(string: "https://example.com/hearthArena.json")!,
                cachePolicy: .versioned
            ),
            officialHTMLResource: RemoteJSONResource(
                cacheKey: "haOfficial",
                payloadURL: URL(string: "https://example.com/hearthArena.html")!,
                cachePolicy: .oneDay
            )
        )

        let metrics = try await provider.loadMetrics()

        #expect(metrics.contains(CardMetric(cardId: "CARD_001", classContext: .mage, source: .hearthArena, score: 70, updatedAt: metrics[0].updatedAt)))
        #expect(metrics.contains { $0.cardId == "CS2_029" && $0.classContext == .mage && $0.score == 80 })
        #expect(metrics.map(\.cardId).contains("CARD_002"))
    }

    @Test("HSReplay provider reads pickrate, winrate, played winrate and samples")
    func hsReplayProvider() async throws {
        let payload = """
        {
          "data": {
            "MAGE": [
              {
                "card_id": "CARD_001",
                "popularity": 12.5,
                "win_rate": 53.44,
                "drawn_win_rate": 54.82,
                "played_win_rate": 51.26,
                "num_games": 1234
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let loader = RemoteJSONLoader(
            httpClient: MockHTTPClient(payloads: [:]),
            cache: MemoryPayloadCache(payloads: ["hsr": payload])
        )
        let provider = HSReplayCardStatsProvider(
            loader: loader,
            resource: RemoteJSONResource(
                cacheKey: "hsr",
                payloadURL: URL(string: "https://example.com/hsr.json")!,
                cachePolicy: .versioned
            )
        )

        let metric = try #require(await provider.loadMetrics().first)

        #expect(metric.classContext == .mage)
        #expect(metric.pickRate == 12.5)
        #expect(metric.includedWinRate == 53.4)
        #expect(metric.drawnWinRate == 54.8)
        #expect(metric.playedWinRate == 51.3)
        #expect(metric.sampleSize == 1234)
    }

    @Test("CardsJSON provider accepts localized name dictionaries")
    func cardsJSONProviderLocalizedNames() async throws {
        let payload = """
        [
          {
            "id": "CARD_001",
            "dbfId": 1,
            "name": {
              "enUS": "Arcane Scholar",
              "zhCN": "奥术学者"
            },
            "cardClass": "MAGE",
            "rarity": "COMMON",
            "type": "MINION",
            "cost": 2
          }
        ]
        """.data(using: .utf8)!
        let loader = RemoteJSONLoader(
            httpClient: MockHTTPClient(payloads: [:]),
            cache: MemoryPayloadCache(payloads: ["cards": payload])
        )
        let provider = CardsJSONProvider(
            loader: loader,
            resource: RemoteJSONResource(
                cacheKey: "cards",
                payloadURL: URL(string: "https://example.com/cards.json")!,
                cachePolicy: .versioned
            )
        )

        let card = try #require(await provider.loadCards().first)

        #expect(card.name == "奥术学者")
        #expect(card.localizedNames["enUS"] == "Arcane Scholar")
        #expect(card.cardClass == .mage)
    }

    @Test("Repository recommends the best card for each source independently")
    func repositoryRecommendation() async {
        let repository = DraftDataRepository()
        await repository.replaceMetrics([
            CardMetric(cardId: "A", classContext: .mage, source: .hearthArena, score: 100),
            CardMetric(cardId: "B", classContext: .mage, source: .firestone, includedWinRate: 55, sampleSize: 2000),
            CardMetric(cardId: "C", classContext: .mage, source: .hsReplay, includedWinRate: 54, sampleSize: 2000)
        ], source: .hearthArena)
        await repository.replaceMetrics([
            CardMetric(cardId: "B", classContext: .mage, source: .firestone, includedWinRate: 55, sampleSize: 2000)
        ], source: .firestone)
        await repository.replaceMetrics([
            CardMetric(cardId: "C", classContext: .mage, source: .hsReplay, includedWinRate: 54, sampleSize: 2000)
        ], source: .hsReplay)

        let evaluation = await repository.evaluateDraftChoices(cardIds: ["A", "B", "C"], classContext: .mage)

        #expect(evaluation.recommendedCardId == "B")
        #expect(evaluation.recommendationsBySource[.hearthArena] == "A")
        #expect(evaluation.recommendationsBySource[.firestone] == "B")
        #expect(evaluation.recommendationsBySource[.hsReplay] == "C")
    }

    @Test("Repository ignores low sample statistics when recommending")
    func repositoryIgnoresLowSampleStats() async {
        let repository = DraftDataRepository()
        await repository.replaceMetrics([
            CardMetric(cardId: "LOW", classContext: .mage, source: .firestone, includedWinRate: 90, sampleSize: 1),
            CardMetric(cardId: "ENOUGH", classContext: .mage, source: .firestone, includedWinRate: 52, sampleSize: 100)
        ], source: .firestone)

        let evaluation = await repository.evaluateDraftChoices(cardIds: ["LOW", "ENOUGH"], classContext: .mage)

        #expect(evaluation.recommendationsBySource[.firestone] == "ENOUGH")
        #expect(evaluation.recommendedCardId == "ENOUGH")
    }

    @Test("Repository can prefer a selected metric source")
    func repositoryPrefersSelectedSource() async {
        let repository = DraftDataRepository()
        await repository.replaceMetrics([
            CardMetric(cardId: "HA", classContext: .mage, source: .hearthArena, score: 100)
        ], source: .hearthArena)
        await repository.replaceMetrics([
            CardMetric(cardId: "FIRE", classContext: .mage, source: .firestone, includedWinRate: 55, sampleSize: 1000)
        ], source: .firestone)

        let evaluation = await repository.evaluateDraftChoices(
            cardIds: ["HA", "FIRE"],
            classContext: .mage,
            preferredSource: .hearthArena
        )

        #expect(evaluation.recommendedCardId == "HA")
        #expect(evaluation.recommendationsBySource[.firestone] == "FIRE")
    }

    @Test("Repository resolves localized names before draft evaluation")
    func repositoryResolvesCardNames() async {
        let repository = DraftDataRepository()
        await repository.replaceCards([
            CardMetadata(
                id: "MAGE_001",
                name: "Arcane Scholar",
                localizedNames: ["zhCN": "奥术学者", "enUS": "Arcane Scholar"],
                cardClass: .mage
            ),
            CardMetadata(
                id: "CORE_MAGE_001",
                name: "Arcane Scholar",
                localizedNames: ["zhCN": "奥术学者", "enUS": "Arcane Scholar"],
                cardClass: .mage
            ),
            CardMetadata(
                id: "HUNTER_001",
                name: "Arcane Scholar",
                localizedNames: ["zhCN": "奥术学者", "enUS": "Arcane Scholar"],
                cardClass: .hunter
            )
        ])
        await repository.replaceMetrics([
            CardMetric(cardId: "MAGE_001", classContext: .mage, source: .hsReplay, includedWinRate: 51, sampleSize: 100),
            CardMetric(cardId: "CORE_MAGE_001", classContext: .mage, source: .hsReplay, includedWinRate: 53, sampleSize: 500)
        ], source: .hsReplay)

        let evaluation = await repository.evaluateDraftChoices(cardIds: ["奥术学者", "arcane scholar", "missing"], classContext: .mage)

        #expect(evaluation.inputResolutions[0].cardId == "CORE_MAGE_001")
        #expect(evaluation.inputResolutions[0].isAmbiguous)
        #expect(evaluation.inputResolutions[1].cardId == "CORE_MAGE_001")
        #expect(evaluation.inputResolutions[2].cardId == nil)
        #expect(evaluation.choices.map(\.cardId) == ["CORE_MAGE_001", "CORE_MAGE_001"])
    }

    @Test("Service loads cached providers before first evaluation")
    func serviceLoadsBeforeFirstEvaluation() async {
        let service = DraftDataService(
            repository: DraftDataRepository(),
            cardProvider: MockCardProvider(cards: [
                CardMetadata(
                    id: "CATA_156",
                    name: "试验演示",
                    localizedNames: ["zhCN": "试验演示", "enUS": "Experimental Animation"],
                    cardClass: .deathKnight
                )
            ]),
            rotationProvider: MockRotationProvider(),
            metricProviders: [
                MockMetricProvider(source: .hearthArena, metrics: [
                    CardMetric(cardId: "CATA_156", classContext: .deathKnight, source: .hearthArena, score: 100)
                ])
            ],
            dataSourceInspector: DataSourceInspector(
                cache: FilePayloadCache(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString))
            )
        )

        let evaluation = await service.evaluateDraftChoices(
            cardIds: ["试验演示"],
            classContext: ArenaClass.deathKnight,
            preferredSource: MetricSource.hearthArena
        )

        #expect(evaluation.recommendedCardId == "CATA_156")
        #expect(evaluation.recommendationsBySource[MetricSource.hearthArena] == "CATA_156")
    }
}

private struct MockHTTPClient: HTTPClient {
    let payloads: [URL: Data]

    func data(from url: URL) async throws -> Data {
        guard let data = payloads[url] else {
            throw DataLayerError.missingCachedPayload(url.absoluteString)
        }
        return data
    }
}

private struct MockCardProvider: CardMetadataProviding {
    let cards: [CardMetadata]

    func loadCards() async throws -> [CardMetadata] {
        cards
    }
}

private struct MockMetricProvider: CardMetricsProviding {
    let source: MetricSource
    let metrics: [CardMetric]

    func loadMetrics() async throws -> [CardMetric] {
        metrics
    }
}

private struct MockRotationProvider: ArenaRotationProviding {
    func loadRotation() async throws -> ArenaRotation {
        ArenaRotation(version: 1, sets: [])
    }
}

private actor MemoryPayloadCache: PayloadCache {
    private var payloads: [String: CachedPayload]

    init(payloads: [String: Data]) {
        self.payloads = payloads.mapValues {
            CachedPayload(data: $0, version: nil, storedAt: Date())
        }
    }

    func read(key: String) async throws -> CachedPayload? {
        payloads[key]
    }

    func write(key: String, data: Data, version: String?) async throws {
        payloads[key] = CachedPayload(data: data, version: version, storedAt: Date())
    }
}
