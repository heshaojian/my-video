import XCTest
@testable import MyVideo

@MainActor
final class SavedItemsStoreTests: XCTestCase {
    func testTogglePersistsSavedItemAcrossStoreInstances() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)

        store.toggle(item)

        XCTAssertTrue(store.contains(item))
        XCTAssertEqual(SavedItemsStore(defaults: defaults).items, [item])
    }

    func testToggleRemovesExistingSavedItem() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)

        store.toggle(item)

        XCTAssertFalse(store.contains(item))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testFeedRefreshDetectsNewUpdateAfterBaselineAndCanMarkItSeen() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = MyVideoItem(listPath: "saved-drama", title: "Saved Drama", subTitle: "Episode 3")
        let updated = MyVideoItem(listPath: "saved-drama", title: "Saved Drama", subTitle: "Episode 4")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(original)

        store.refreshUpdateMarkers(with: [.drama: [original]])
        XCTAssertFalse(store.hasNewUpdate(original))

        store.refreshUpdateMarkers(with: [.drama: [updated]])
        XCTAssertTrue(store.hasNewUpdate(updated))

        store.markUpdateSeen(updated)
        XCTAssertFalse(store.hasNewUpdate(updated))
    }

    func testPerTitleNotificationPreferencePersists() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)

        store.setNotificationsEnabled(false, for: item)

        XCTAssertFalse(SavedItemsStore(defaults: defaults).notificationsEnabled(for: item))
    }

    func testDirectEpisodeChecksBaselineThenDetectAndPersistANewEpisode() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "saved-drama", title: "Saved Drama", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        let firstCheck = Date(timeIntervalSince1970: 100)

        let baseline = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(
                itemID: item.id,
                episodes: [
                    EpisodeSelection(mediaKey: "episode-3", title: "3"),
                    EpisodeSelection(mediaKey: "episode-2", title: "2")
                ]
            )!],
            checkedAt: firstCheck,
            observedAt: firstCheck
        )

        XCTAssertTrue(baseline.isEmpty)
        XCTAssertFalse(store.hasNewUpdate(item))
        XCTAssertEqual(store.episodeUpdateState(for: item), SavedEpisodeUpdateState(
            episodes: [
                EpisodeSelection(mediaKey: "episode-3", title: "3"),
                EpisodeSelection(mediaKey: "episode-2", title: "2")
            ],
            latestEpisodeKey: "episode-3",
            seenEpisodeKey: "episode-3",
            detectedAt: firstCheck,
            lastObservedAt: firstCheck
        ))
        let secondCheck = Date(timeIntervalSince1970: 200)
        let updates = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(
                itemID: item.id,
                episodes: [
                    EpisodeSelection(mediaKey: "episode-4", title: "4"),
                    EpisodeSelection(mediaKey: "episode-3", title: "3")
                ]
            )!],
            checkedAt: secondCheck,
            observedAt: secondCheck
        )
        XCTAssertEqual(updates.map(\.episode.mediaKey), ["episode-4"])
        XCTAssertTrue(store.hasNewUpdate(item))
        XCTAssertEqual(
            store.episodeUpdateState(for: item)?.episodes.map(\.mediaKey),
            ["episode-4", "episode-3", "episode-2"]
        )
        XCTAssertEqual(store.episodeUpdateState(for: item)?.seenEpisodeKey, "episode-3")
        XCTAssertEqual(store.episodeUpdateState(for: item)?.detectedAt, secondCheck)

        let restored = SavedItemsStore(defaults: defaults)
        XCTAssertEqual(restored.lastDirectUpdateCheck, secondCheck)
        restored.markUpdateSeen(item)
        XCTAssertFalse(restored.hasNewUpdate(item))
        XCTAssertEqual(restored.episodeUpdateState(for: item)?.seenEpisodeKey, "episode-4")
        XCTAssertEqual(restored.episodeUpdateState(for: item)?.detectedAt, secondCheck)
    }

    func testEpisodeSnapshotIsBoundedAndKeepsNewestFirstOrder() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "long-series", title: "Long Series", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        let episodes = (1...140).reversed().map {
            EpisodeSelection(mediaKey: "episode-\($0)", title: "\($0)")
        }

        _ = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(itemID: item.id, episodes: episodes)!],
            checkedAt: Date(timeIntervalSince1970: 100),
            observedAt: Date(timeIntervalSince1970: 100)
        )

        let retained = store.episodeUpdateState(for: item)?.episodes.map(\.mediaKey)
        XCTAssertEqual(retained?.count, SavedEpisodeUpdateState.maximumEpisodeCount)
        XCTAssertEqual(retained?.first, "episode-140")
        XCTAssertEqual(retained?.last, "episode-41")
    }

    func testPartialEpisodeCheckRetainsOtherTitleAndGlobalCompletionDate() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = MyVideoItem(listPath: "first-series", title: "First", isSerial: true)
        let second = MyVideoItem(listPath: "second-series", title: "Second", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(first)
        store.toggle(second)
        let completedAt = Date(timeIntervalSince1970: 100)
        _ = store.recordEpisodeChecks(
            [
                SavedEpisodeSnapshot(itemID: first.id, episode: EpisodeSelection(mediaKey: "first-1", title: "1")),
                SavedEpisodeSnapshot(itemID: second.id, episode: EpisodeSelection(mediaKey: "second-1", title: "1"))
            ],
            checkedAt: completedAt,
            observedAt: completedAt
        )
        let partialObservation = Date(timeIntervalSince1970: 200)

        _ = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(itemID: first.id, episode: EpisodeSelection(mediaKey: "first-2", title: "2"))],
            checkedAt: nil,
            observedAt: partialObservation
        )

        XCTAssertEqual(store.lastDirectUpdateCheck, completedAt)
        XCTAssertEqual(store.episodeUpdateState(for: first)?.latestEpisodeKey, "first-2")
        XCTAssertEqual(store.episodeUpdateState(for: first)?.lastObservedAt, partialObservation)
        XCTAssertEqual(store.episodeUpdateState(for: second)?.latestEpisodeKey, "second-1")
        XCTAssertEqual(store.episodeUpdateState(for: second)?.lastObservedAt, completedAt)
    }

    func testUnsavingRemovesRetainedEpisodeState() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "saved-drama", title: "Saved Drama", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        _ = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(itemID: item.id, episode: EpisodeSelection(mediaKey: "episode-3", title: "3"))],
            checkedAt: Date(timeIntervalSince1970: 100),
            observedAt: Date(timeIntervalSince1970: 100)
        )

        store.toggle(item)

        XCTAssertNil(store.episodeUpdateState(for: item))
        XCTAssertNil(SavedItemsStore(defaults: defaults).episodeUpdateState(for: item))
    }

    func testMarkEpisodeUpdateSeenOnlyAcknowledgesTheExactLatestEpisode() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "saved-drama", title: "Saved Drama", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        _ = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(itemID: item.id, episode: EpisodeSelection(mediaKey: "episode-3", title: "3"))],
            checkedAt: Date(timeIntervalSince1970: 100)
        )
        _ = store.recordEpisodeChecks(
            [SavedEpisodeSnapshot(itemID: item.id, episode: EpisodeSelection(mediaKey: "episode-4", title: "4"))],
            checkedAt: Date(timeIntervalSince1970: 200)
        )

        store.markEpisodeUpdateSeen(item, episodeKey: "episode-3")
        XCTAssertTrue(store.hasNewUpdate(item))

        store.markEpisodeUpdateSeen(item, episodeKey: "episode-4")
        XCTAssertFalse(store.hasNewUpdate(item))
        XCTAssertEqual(store.episodeUpdateState(for: item)?.seenEpisodeKey, "episode-4")
    }

    func testRestoreDropsMalformedAndDuplicateSavedItems() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let valid = MyVideoItem(listPath: "valid", title: "Valid")
        let malformed = MyVideoItem(listPath: " padded ", title: "Malformed")
        defaults.set(
            try JSONEncoder().encode([valid, valid, malformed]),
            forKey: "savedMyVideoItems"
        )

        let restored = SavedItemsStore(defaults: defaults)

        XCTAssertEqual(restored.items, [valid])
    }

    func testOldMetadataDecodesIntoSeenEpisodeState() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "legacy-series", title: "Legacy", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        let legacyMetadata = try JSONSerialization.data(withJSONObject: [
            "episodeMarkers": [item.id: "episode-7"],
            "seenEpisodeMarkers": [item.id: "episode-7"]
        ])
        defaults.set(legacyMetadata, forKey: "savedMyVideoMetadata")

        let restored = SavedItemsStore(defaults: defaults)

        XCTAssertEqual(restored.episodeUpdateState(for: item)?.latestEpisodeKey, "episode-7")
        XCTAssertEqual(restored.episodeUpdateState(for: item)?.seenEpisodeKey, "episode-7")
        XCTAssertEqual(restored.episodeUpdateState(for: item)?.episodes.map(\.mediaKey), ["episode-7"])
        XCTAssertNil(restored.episodeUpdateState(for: item)?.detectedAt)
        XCTAssertFalse(restored.hasNewUpdate(item))
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "SavedItemsStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
