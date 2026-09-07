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
        XCTAssertTrue(restored.cloudSyncEnabled)
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

private struct StubFeedService: AiyifanFeedServing {
    let failing: Set<AiyifanCategory>

    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem] {
        if failing.contains(category) {
            throw URLError(.notConnectedToInternet)
        }
        return [AiyifanItem(listPath: "live-\(category.id)", title: category.title)]
    }
}
