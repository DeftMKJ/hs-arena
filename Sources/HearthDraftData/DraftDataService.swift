import Foundation

public struct DraftDataService: Sendable {
    public let repository: DraftDataRepository
    private let cardProvider: CardMetadataProviding
    private let rotationProvider: ArenaRotationProviding
    private let metricProviders: [CardMetricsProviding]
    private let cachedCardProvider: CardMetadataProviding
    private let cachedRotationProvider: ArenaRotationProviding
    private let cachedMetricProviders: [CardMetricsProviding]
    private let dataSourceInspector: DataSourceInspector

    public init(
        repository: DraftDataRepository,
        cardProvider: CardMetadataProviding,
        rotationProvider: ArenaRotationProviding,
        metricProviders: [CardMetricsProviding],
        cachedCardProvider: CardMetadataProviding? = nil,
        cachedRotationProvider: ArenaRotationProviding? = nil,
        cachedMetricProviders: [CardMetricsProviding]? = nil,
        dataSourceInspector: DataSourceInspector
    ) {
        self.repository = repository
        self.cardProvider = cardProvider
        self.rotationProvider = rotationProvider
        self.metricProviders = metricProviders
        self.cachedCardProvider = cachedCardProvider ?? cardProvider
        self.cachedRotationProvider = cachedRotationProvider ?? rotationProvider
        self.cachedMetricProviders = cachedMetricProviders ?? metricProviders
        self.dataSourceInspector = dataSourceInspector
    }

    public static func live(
        cacheRootURL: URL = FilePayloadCache.defaultRootURL(),
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) -> DraftDataService {
        let cache = FilePayloadCache(rootURL: cacheRootURL)
        let loader = RemoteJSONLoader(httpClient: httpClient, cache: cache)
        let cachedLoader = RemoteJSONLoader(httpClient: httpClient, cache: cache, mode: .cacheOnly)
        return DraftDataService(
            repository: DraftDataRepository(),
            cardProvider: CardsJSONProvider(loader: loader),
            rotationProvider: ArenaRotationProvider(loader: loader),
            metricProviders: [
                HearthArenaProvider(loader: loader),
                HSReplayCardStatsProvider(loader: loader),
                FirestoneCardStatsProvider(loader: loader)
            ],
            cachedCardProvider: CardsJSONProvider(loader: cachedLoader),
            cachedRotationProvider: ArenaRotationProvider(loader: cachedLoader),
            cachedMetricProviders: [
                HearthArenaProvider(loader: cachedLoader),
                HSReplayCardStatsProvider(loader: cachedLoader),
                FirestoneCardStatsProvider(loader: cachedLoader)
            ],
            dataSourceInspector: DataSourceInspector(cache: cache)
        )
    }

    public func refreshAll() async throws {
        try await loadSnapshot(
            cardProvider: cardProvider,
            rotationProvider: rotationProvider,
            metricProviders: metricProviders,
            allowPartialMetrics: false
        )
    }

    @discardableResult
    public func loadCachedSnapshot() async -> Bool {
        do {
            try await loadSnapshot(
                cardProvider: cachedCardProvider,
                rotationProvider: cachedRotationProvider,
                metricProviders: cachedMetricProviders,
                allowPartialMetrics: true
            )
            return await repository.isReadyForEvaluation()
        } catch {
            return false
        }
    }

    private func loadSnapshot(
        cardProvider: CardMetadataProviding,
        rotationProvider: ArenaRotationProviding,
        metricProviders: [CardMetricsProviding],
        allowPartialMetrics: Bool
    ) async throws {
        async let cards = cardProvider.loadCards()

        let loadedMetrics: [(source: MetricSource, metrics: [CardMetric])]
        if allowPartialMetrics {
            var pairs: [(source: MetricSource, metrics: [CardMetric])] = []
            pairs.reserveCapacity(metricProviders.count)
            for provider in metricProviders {
                if let metrics = try? await provider.loadMetrics() {
                    pairs.append((provider.source, metrics))
                }
            }
            loadedMetrics = pairs
        } else {
            let metrics = try await metricProviders.asyncMap { provider in
                try await provider.loadMetrics()
            }
            loadedMetrics = zip(metricProviders.map(\.source), metrics).map { pair in
                (source: pair.0, metrics: pair.1)
            }
        }

        try await repository.replaceCards(cards)
        if allowPartialMetrics {
            if let rotation = try? await rotationProvider.loadRotation() {
                await repository.setRotation(rotation)
            }
        } else {
            let rotation = try await rotationProvider.loadRotation()
            await repository.setRotation(rotation)
        }
        for (source, metrics) in loadedMetrics {
            await repository.replaceMetrics(metrics, source: source)
        }
    }

    public func evaluateDraftChoices(
        cardIds: [String],
        classContext: ArenaClass,
        preferredSource: MetricSource? = nil
    ) async -> DraftChoiceEvaluation {
        if await !repository.isReadyForEvaluation() {
            try? await refreshAll()
        }

        return await repository.evaluateDraftChoices(
            cardIds: cardIds,
            classContext: classContext,
            preferredSource: preferredSource
        )
    }

    public func dataSourceStatuses() async -> [DataSourceStatus] {
        await dataSourceInspector.statuses()
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }

}
