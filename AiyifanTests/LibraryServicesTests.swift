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
        XCTAssertNil(result.totalFailureMessage)
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
        XCTAssertEqual(staleRequestCount, AiyifanCategory.allCases.count)

        let forcedRefresh = await viewModel.loadLatestIfNeeded(force: true, now: now)
        let forcedRequestCount = await service.requestCount()
        XCTAssertTrue(forcedRefresh)
        XCTAssertEqual(forcedRequestCount, AiyifanCategory.allCases.count * 2)
    }
}

final class AiyifanFeedServiceTests: XCTestCase {
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
