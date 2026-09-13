import XCTest
@testable import MyVideo

@MainActor
final class PlayedItemsStoreTests: XCTestCase {
    func testRecordingEpisodesKeepsIndependentNewestFirstHistory() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlayedItemsStore(defaults: defaults)
        let item = MyVideoItem(listPath: "series", title: "Series")
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)

        store.record(
            item: item,
            episode: Episode(mediaKey: "episode-1", title: "01", updateDate: nil),
            position: 40,
            duration: 1_000,
            playedAt: olderDate
        )
        store.record(
            item: item,
            episode: Episode(mediaKey: "episode-2", title: "02", updateDate: nil),
            position: 10,
            duration: 1_000,
            playedAt: newerDate
        )

        XCTAssertEqual(store.items.map(\.episodeKey), ["episode-2", "episode-1"])
        XCTAssertEqual(store.items.map(\.lastPlayedAt), [newerDate, olderDate])
    }

    func testRecordingSameEpisodeReplacesRatherThanDuplicates() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlayedItemsStore(defaults: defaults)
        let item = MyVideoItem(listPath: "series", title: "Series")
        let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)

        store.record(item: item, episode: episode, position: 10, duration: 100, playedAt: Date(timeIntervalSince1970: 100))
        store.record(item: item, episode: episode, position: 55, duration: 100, playedAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].position, 55)
    }

    func testResumeClampsPositionAndCompletedRecordRestarts() {
        let item = MyVideoItem(listPath: "movie", title: "Movie")
        let active = PlayedRecord(
            item: item,
            episodeKey: nil,
            episodeTitle: nil,
            position: -5,
            duration: 100,
            lastPlayedAt: Date()
        )
        let completed = PlayedRecord(
            item: item,
            episodeKey: nil,
            episodeTitle: nil,
            position: 90,
            duration: 100,
            lastPlayedAt: Date()
        )

        XCTAssertEqual(active.resumePosition, 0)
        XCTAssertEqual(completed.resumePosition, 0)
        XCTAssertTrue(completed.isCompleted)
    }

    func testPlayedPositionLabelUsesFixedMediaTimeInsteadOfWallClockTime() {
        XCTAssertEqual(
            PlayedPositionFormatter.label(position: 40, duration: 100),
            "Paused at 00:40 / 01:40"
        )
        XCTAssertEqual(
            PlayedPositionFormatter.label(position: 3_723, duration: 7_200),
            "Paused at 1:02:03 / 2:00:00"
        )
    }

    func testRemoveAndClearPersistAcrossStoreInstances() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = MyVideoItem(listPath: "first", title: "First")
        let second = MyVideoItem(listPath: "second", title: "Second")
        let store = PlayedItemsStore(defaults: defaults)
        store.record(item: first, episode: nil, position: 10, duration: 100)
        store.record(item: second, episode: nil, position: 20, duration: 100)

        store.remove(store.items.first { $0.item.id == first.id }!)
        XCTAssertEqual(PlayedItemsStore(defaults: defaults).items.map(\.item.id), [second.id])

        store.removeAll()
        XCTAssertTrue(PlayedItemsStore(defaults: defaults).items.isEmpty)
    }

    func testPersistenceKeepsValidRecordsWhenOneStoredRecordIsCorrupt() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "movie", title: "Movie")
        let valid = PlayedRecord(
            item: item,
            episodeKey: nil,
            episodeTitle: nil,
            position: 30,
            duration: 100,
            lastPlayedAt: Date(timeIntervalSince1970: 100)
        )
        let validObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        let envelope: [String: Any] = [
            "version": 1,
            "records": [validObject, ["broken": true]]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: envelope), forKey: PlayedItemsStore.storageKey)

        let restored = PlayedItemsStore(defaults: defaults)

        XCTAssertEqual(restored.items.count, 1)
        XCTAssertEqual(restored.items[0].item, item)
    }

    func testWatchedUnwatchedRestartAndTitleResetPersist() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "series", title: "Series")
        let first = Episode(mediaKey: "episode-1", title: "01", updateDate: nil)
        let second = Episode(mediaKey: "episode-2", title: "02", updateDate: nil)
        let store = PlayedItemsStore(defaults: defaults)
        store.record(item: item, episode: first, position: 20, duration: 100)
        store.record(item: item, episode: second, position: 30, duration: 100)

        let firstRecord = store.record(for: item, episodeKey: first.mediaKey)!
        store.markWatched(firstRecord)
        XCTAssertTrue(store.record(for: item, episodeKey: first.mediaKey)!.isCompleted)

        store.markUnwatched(store.record(for: item, episodeKey: first.mediaKey)!)
        XCTAssertFalse(store.record(for: item, episodeKey: first.mediaKey)!.isCompleted)

        store.restart(store.record(for: item, episodeKey: second.mediaKey)!)
        XCTAssertEqual(store.record(for: item, episodeKey: second.mediaKey)!.position, 0)

        store.removeAll(for: item)
        XCTAssertTrue(PlayedItemsStore(defaults: defaults).items.isEmpty)
    }

    func testMarkUnstartedExactEpisodeWatchedPersistsCompletionOverride() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "series", title: "Series", isSerial: true)
        let episode = Episode(mediaKey: "episode-8", title: "08", updateDate: nil)
        let store = PlayedItemsStore(defaults: defaults)

        store.markWatched(item: item, episode: episode)

        let record = PlayedItemsStore(defaults: defaults).record(for: item, episodeKey: episode.mediaKey)
        XCTAssertEqual(record?.episodeTitle, "08")
        XCTAssertEqual(record?.completionOverride, true)
        XCTAssertTrue(record?.isCompleted == true)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "PlayedItemsStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
