import Foundation
import XCTest
@testable import Aiyifan

@MainActor
final class LibraryServicesTests: XCTestCase {
    func testAppSettingsPersistAlertsAndCloudOptIn() {
        let suite = "LibraryServicesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettingsStore(defaults: defaults)
        settings.setUpdateAlertsEnabled(true)
        settings.setCloudSyncEnabled(true)

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(restored.updateAlertsEnabled)
        XCTAssertEqual(restored.cloudSyncEnabled, AppCapabilities.iCloudSyncAvailable)
    }

    func testDeepLinkRoundTripAndRejectsUntrustedScheme() throws {
        let item = AiyifanItem(listPath: "series/42", title: "A Show")
        let url = try XCTUnwrap(AiyifanDeepLink.makeURL(item: item, episodeKey: "ep-4"))
        let destination = try XCTUnwrap(AiyifanDeepLink.parse(url))

        XCTAssertEqual(destination.item, item)
        XCTAssertEqual(destination.episodeKey, "ep-4")
        XCTAssertNil(AiyifanDeepLink.parse(URL(string: "https://example.com/play?id=42")!))
    }

    func testCloudMergeKeepsUniqueSavedAndNewestPlayedRecord() {
        let item = AiyifanItem(listPath: "series", title: "Series")
        let old = PlayedRecord(
            item: item, episodeKey: "ep-1", episodeTitle: "01", position: 10,
            duration: 100, lastPlayedAt: Date(timeIntervalSince1970: 1)
        )
        let new = PlayedRecord(
            item: item, episodeKey: "ep-1", episodeTitle: "01", position: 70,
            duration: 100, lastPlayedAt: Date(timeIntervalSince1970: 2)
        )
        let local = CloudLibraryPayload(savedItems: [item], playedItems: [old])
        let cloud = CloudLibraryPayload(savedItems: [item], playedItems: [new])

        let merged = CloudLibraryMerger.merge(local: local, cloud: cloud)

        XCTAssertEqual(merged.savedItems, [item])
        XCTAssertEqual(merged.playedItems, [new])
    }

    func testCloudSyncReportsUnavailableWhenBuildHasNoICloudEntitlement() {
        let item = AiyifanItem(listPath: "saved", title: "Saved")

        let result = CloudLibrarySync.shared.synchronize(
            savedItems: [item],
            playedItems: [],
            enabled: true
        )

        XCTAssertFalse(AppCapabilities.iCloudSyncAvailable)
        XCTAssertEqual(CloudLibrarySync.shared.status, "Unavailable")
        XCTAssertEqual(result.savedItems, [item])
    }

    func testNotificationBatchIncludesOnlyEnabledNewItems() throws {
        let first = AiyifanItem(listPath: "one", title: "One", subTitle: "EP 2")
        let second = AiyifanItem(listPath: "two", title: "Two", subTitle: "EP 4")

        let batch = try XCTUnwrap(NotificationBatch.make(
            items: [first, second],
            notificationsEnabled: { $0.id == first.id }
        ))

        XCTAssertEqual(batch.title, "Aiyifan: 1 new update")
        XCTAssertTrue(batch.body.contains("One"))
        XCTAssertFalse(batch.body.contains("Two"))
        XCTAssertEqual(AiyifanDeepLink.parse(batch.deepLink)?.item, first)
    }

    func testEpisodeUpdateNotificationDeepLinksToTheNewEpisode() throws {
        let item = AiyifanItem(listPath: "series", title: "Series", isSerial: true)
        let update = SavedEpisodeUpdate(
            item: item,
            episode: EpisodeSelection(mediaKey: "episode-8", title: "8")
        )

        let batch = try XCTUnwrap(NotificationBatch.make(
            episodeUpdates: [update],
            notificationsEnabled: { _ in true }
        ))

        XCTAssertTrue(batch.body.contains("Episode 8"))
        XCTAssertEqual(AiyifanDeepLink.parse(batch.deepLink)?.episodeKey, "episode-8")
    }

    func testDailySavedUpdatePolicyRunsWhenNoCheckExistsOrDayElapsed() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertTrue(DailySavedUpdatePolicy.isDue(lastChecked: nil, now: now))
        XCTAssertFalse(DailySavedUpdatePolicy.isDue(lastChecked: now.addingTimeInterval(-86_399), now: now))
        XCTAssertTrue(DailySavedUpdatePolicy.isDue(lastChecked: now.addingTimeInterval(-86_400), now: now))
    }

    func testAppOpenRefreshPolicyUsesFifteenMinuteForegroundWindow() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertTrue(AppOpenRefreshPolicy.isDue(lastSuccessfulRefresh: nil, now: now))
        XCTAssertFalse(AppOpenRefreshPolicy.isDue(
            lastSuccessfulRefresh: now.addingTimeInterval(-899),
            now: now
        ))
        XCTAssertTrue(AppOpenRefreshPolicy.isDue(
            lastSuccessfulRefresh: now.addingTimeInterval(-900),
            now: now
        ))
    }

    func testAppOpenRefreshCoordinatorCoalescesOverlappingCalls() async {
        let coordinator = AppOpenLibraryRefreshCoordinator()
        let now = Date(timeIntervalSince1970: 100_000)
        let counter = AsyncCounter()

        async let first = coordinator.refreshIfNeeded(now: now) {
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(100))
            return true
        }
        await Task.yield()
        async let second = coordinator.refreshIfNeeded(now: now) {
            await counter.increment()
            return true
        }

        let results = await (first, second)
        let operationCount = await counter.value()
        XCTAssertEqual(operationCount, 1)
        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(coordinator.lastSuccessfulRefresh, now)
    }

    func testPartialAppOpenRefreshDoesNotAdvanceSuccessAndCanRetry() async {
        let coordinator = AppOpenLibraryRefreshCoordinator()
        let firstDate = Date(timeIntervalSince1970: 100_000)
        var operationCount = 0

        let first = await coordinator.refreshIfNeeded(now: firstDate) {
            operationCount += 1
            return false
        }
        let second = await coordinator.refreshIfNeeded(now: firstDate.addingTimeInterval(1)) {
            operationCount += 1
            return true
        }

        XCTAssertFalse(first)
        XCTAssertTrue(second)
        XCTAssertEqual(operationCount, 2)
        XCTAssertEqual(coordinator.lastSuccessfulRefresh, firstDate.addingTimeInterval(1))
    }

    func testSuccessfulAppOpenRefreshSkipsRapidForegroundReturn() async {
        let coordinator = AppOpenLibraryRefreshCoordinator()
        let firstDate = Date(timeIntervalSince1970: 100_000)
        var operationCount = 0

        _ = await coordinator.refreshIfNeeded(now: firstDate) {
            operationCount += 1
            return true
        }
        let skipped = await coordinator.refreshIfNeeded(now: firstDate.addingTimeInterval(899)) {
            operationCount += 1
            return true
        }

        XCTAssertFalse(skipped)
        XCTAssertEqual(operationCount, 1)
    }

    func testCancellingSavedUpdateCheckDoesNotScheduleMoreItems() async throws {
        let resolver = BlockingSavedEpisodeResolver()
        let items = (1...3).map {
            AiyifanItem(listPath: "series-\($0)", title: "Series \($0)", isSerial: true)
        }
        let task = Task {
            await SavedUpdateChecker.check(
                items: items,
                resolver: resolver,
                maximumConcurrentChecks: 1
            )
        }
        for _ in 0..<100 where await resolver.startedCount() == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        task.cancel()
        let result = await task.value
        let startedCount = await resolver.startedCount()

        XCTAssertEqual(startedCount, 1)
        XCTAssertEqual(result.completedCount, 0)
        XCTAssertFalse(result.isComplete)
    }
}

private actor BlockingSavedEpisodeResolver: SavedEpisodeResolving {
    private var startedItemIDs: [String] = []

    func episodesForSavedUpdate(
        for item: AiyifanItem,
        expectedEpisodeKey: String?
    ) async throws -> [EpisodeSelection]? {
        startedItemIDs.append(item.id)
        try await Task.sleep(for: .seconds(30))
        return nil
    }

    func startedCount() -> Int {
        startedItemIDs.count
    }
}

private actor AsyncCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

final class FeedRepositoryTests: XCTestCase {
    func testPartialRefreshUsesCacheForFailedCategory() async {
        let suite = "FeedRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cached = AiyifanItem(listPath: "cached-series", title: "Cached Series")
        let cache = FeedCacheStore(defaults: defaults)
        cache.save([.drama: [cached]], refreshedAt: Date(timeIntervalSince1970: 1))
        let service = StubFeedService(failing: [.drama])
        let repository = FeedRepository(service: service, cache: cache)

        let result = await repository.refresh()

        XCTAssertEqual(result.items[.drama], [cached])
        XCTAssertTrue(result.staleCategories.contains(.drama))
        XCTAssertFalse(result.items[.movie, default: []].isEmpty)
        XCTAssertTrue(result.hasFreshContent)
        XCTAssertNil(result.totalFailureMessage)
    }

    func testTotalFailureWithCacheDoesNotReportFreshContent() async {
        let suite = "FeedRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = FeedCacheStore(defaults: defaults)
        cache.save(
            [.drama: [AiyifanItem(listPath: "cached", title: "Cached")]],
            refreshedAt: Date(timeIntervalSince1970: 1)
        )
        let repository = FeedRepository(
            service: StubFeedService(failing: Set(AiyifanCategory.allCases)),
            cache: cache
        )

        let result = await repository.refresh()

        XCTAssertFalse(result.hasFreshContent)
        XCTAssertEqual(result.items[.drama]?.first?.title, "Cached")
    }

    func testTotalFailureWithoutCacheReturnsMessage() async {
        let suite = "FeedRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = FeedRepository(
            service: StubFeedService(failing: Set(AiyifanCategory.allCases)),
            cache: FeedCacheStore(defaults: defaults)
        )

        let result = await repository.refresh()

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNotNil(result.totalFailureMessage)
    }
}

@MainActor
final class HomeFeedFreshnessTests: XCTestCase {
    func testRefreshPolicyTreatsMissingAndExpiredFeedsAsStale() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(HomeFeedRefreshPolicy.shouldRefresh(
            hasContent: false,
            lastRefreshedAt: now,
            now: now
        ))
        XCTAssertTrue(HomeFeedRefreshPolicy.shouldRefresh(
            hasContent: true,
            lastRefreshedAt: nil,
            now: now
        ))
        XCTAssertFalse(HomeFeedRefreshPolicy.shouldRefresh(
            hasContent: true,
            lastRefreshedAt: now.addingTimeInterval(-899),
            now: now
        ))
        XCTAssertTrue(HomeFeedRefreshPolicy.shouldRefresh(
            hasContent: true,
            lastRefreshedAt: now.addingTimeInterval(-900),
            now: now
        ))
    }

    func testViewModelSkipsFreshFeedAndRefreshesStaleOrForcedFeed() async {
        let suite = "HomeFeedFreshnessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = CountingFeedService()
        let repository = FeedRepository(
            service: service,
            cache: FeedCacheStore(defaults: defaults)
        )
        let viewModel = BrowserViewModel(feedRepository: repository)
        let now = Date(timeIntervalSince1970: 10_000)
        viewModel.latestItems = [.movie: [AiyifanItem(listPath: "existing", title: "Existing")]]
        viewModel.lastFeedRefresh = now.addingTimeInterval(-899)

        let refreshedFreshFeed = await viewModel.loadLatestIfNeeded(now: now)
        let freshRequestCount = await service.requestCount()
        XCTAssertFalse(refreshedFreshFeed)
        XCTAssertEqual(freshRequestCount, 0)

        viewModel.lastFeedRefresh = now.addingTimeInterval(-900)
        let refreshedStaleFeed = await viewModel.loadLatestIfNeeded(now: now)
        let staleRequestCount = await service.requestCount()
        XCTAssertTrue(refreshedStaleFeed)
        XCTAssertTrue(viewModel.lastLoadProducedFreshContent)
        XCTAssertEqual(staleRequestCount, AiyifanCategory.allCases.count)

        let forcedRefresh = await viewModel.loadLatestIfNeeded(force: true, now: now)
        let forcedRequestCount = await service.requestCount()
        XCTAssertTrue(forcedRefresh)
        XCTAssertEqual(forcedRequestCount, AiyifanCategory.allCases.count * 2)
    }

    func testViewModelMarksCacheOnlyFailureAsNotFresh() async {
        let suite = "HomeFeedFreshnessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = FeedCacheStore(defaults: defaults)
        cache.save(
            [.movie: [AiyifanItem(listPath: "cached", title: "Cached")]],
            refreshedAt: Date(timeIntervalSince1970: 1)
        )
        let repository = FeedRepository(
            service: StubFeedService(failing: Set(AiyifanCategory.allCases)),
            cache: cache
        )
        let viewModel = BrowserViewModel(feedRepository: repository)

        let didAttemptRefresh = await viewModel.loadLatestIfNeeded(force: true)
        XCTAssertTrue(didAttemptRefresh)
        XCTAssertFalse(viewModel.lastLoadProducedFreshContent)
        XCTAssertEqual(viewModel.latestItems[.movie]?.first?.title, "Cached")
    }
}

final class AiyifanFeedServiceTests: XCTestCase {
    func testFixtureLatestFeedReturnsStableCategoryItemWithoutCatalogRequest() async throws {
        let catalog = LatestCatalogRecordingService()
        let service = AiyifanFeedService(catalogService: catalog, usesFixtureFeed: true)

        let items = try await service.fetchLatest(category: .drama)
        let request = await catalog.lastRequest()

        XCTAssertNil(request)
        XCTAssertEqual(items.map(\.id), ["fixture-drama"])
        XCTAssertEqual(items.first?.title, "Fixture Series")
        XCTAssertEqual(items.first?.latestEpisodeKey, "episode-10")
        XCTAssertEqual(items.first?.latestEpisodeTitle, "10")
        XCTAssertEqual(items.first?.playURL.scheme, "data")
        XCTAssertEqual(items.first?.score, 9.4)
    }

    func testLatestUsesEightItemUpdatedDescendingCatalogQuery() async throws {
        let catalog = LatestCatalogRecordingService()
        let service = AiyifanFeedService(catalogService: catalog)

        let items = try await service.fetchLatest(category: .movie)
        let request = await catalog.lastRequest()

        XCTAssertEqual(items.first?.score, 9.4)
        XCTAssertEqual(request?.query, CatalogQuery(category: .movie))
        XCTAssertEqual(request?.page, 1)
        XCTAssertEqual(request?.pageSize, 8)
    }
}

private actor LatestCatalogRecordingService: CategoryCatalogServing {
    struct Request: Sendable {
        let query: CatalogQuery
        let page: Int
        let pageSize: Int
    }

    private var requests: [Request] = []

    func fetchPage(category: AiyifanCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        requests.append(Request(query: query, page: page, pageSize: pageSize))
        return CategoryCatalogPage(
            items: [AiyifanItem(listPath: "latest", title: "Provider Title", score: 9.4)],
            page: page,
            isLastPage: true
        )
    }

    func lastRequest() -> Request? {
        requests.last
    }
}

private struct StubFeedService: AiyifanFeedServing {
    let failing: Set<AiyifanCategory>

    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem] {
        if failing.contains(category) {
            throw URLError(.notConnectedToInternet)
        }
        return [AiyifanItem(listPath: "live-\(category.id)", title: category.title)]
    }
}

private actor CountingFeedService: AiyifanFeedServing {
    private var count = 0

    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem] {
        count += 1
        return [AiyifanItem(listPath: "fresh-\(category.id)", title: "Fresh \(category.title)")]
    }

    func requestCount() -> Int {
        count
    }
}
