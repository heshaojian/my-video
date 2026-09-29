import XCTest
@testable import MyVideo

final class SavedLibrarySynchronizationTests: XCTestCase {
    func testPosterProjectionHidesOpaqueEpisodeKeyAndUsesLanguageAndYear() {
        let key = "fz4AxompbuT"
        let item = MyVideoItem(
            listPath: "series",
            title: "Series",
            subTitle: key,
            year: "2025",
            isSerial: true,
            latestEpisodeKey: key,
            latestEpisodeTitle: key,
            language: "国语"
        )

        XCTAssertEqual(PosterCardProjection(item: item).detailText, "国语 · 2025")
    }

    func testPosterProjectionUsesResolvedEpisodeThenLanguageAndYear() {
        let item = MyVideoItem(
            listPath: "series",
            title: "Series",
            subTitle: "09",
            year: "2026",
            isSerial: true,
            latestEpisodeKey: "episode-9",
            latestEpisodeTitle: "09",
            language: "粤语"
        )
        let state = SavedEpisodeUpdateState(
            episodes: [EpisodeSelection(mediaKey: "episode-10", title: "10")],
            latestEpisodeKey: "episode-10",
            seenEpisodeKey: "episode-9",
            detectedAt: nil,
            lastObservedAt: nil
        )

        XCTAssertEqual(
            PosterCardProjection(item: item, episodeState: state).detailText,
            "10 · 粤语 · 2026"
        )
    }

    func testPosterProjectionAcceptsRecognizedAndMeaningfulSerialEpisodeLabels() {
        let labels = ["09", "Episode 10", "第10集", "第10期", "Season Finale"]

        for label in labels {
            let projection = PosterCardProjection(
                item: MyVideoItem(
                    listPath: "series",
                    title: "Series",
                    subTitle: label,
                    isSerial: true
                )
            )

            XCTAssertEqual(projection.detailText, label, "Expected \(label) to be an episode label")
        }
    }

    func testPosterProjectionUsesProviderEpisodeBeforeSubtitleAndOmitsMissingFields() {
        let providerEpisode = PosterCardProjection(
            item: MyVideoItem(
                listPath: "series",
                title: "Series",
                subTitle: "09",
                isSerial: true,
                latestEpisodeKey: "episode-10",
                latestEpisodeTitle: "Episode 10"
            )
        )
        let missing = PosterCardProjection(
            item: MyVideoItem(listPath: "series", title: "Series", isSerial: true)
        )

        XCTAssertEqual(providerEpisode.detailText, "Episode 10")
        XCTAssertNil(missing.detailText)
    }

    func testPosterProjectionSkipsListPathAndOpaqueProviderTitle() {
        let projection = PosterCardProjection(
            item: MyVideoItem(
                listPath: "series",
                title: "Series",
                subTitle: "series",
                year: "2026",
                isSerial: true,
                latestEpisodeKey: "episode-10",
                latestEpisodeTitle: "fz4AxompbuT",
                language: "国语"
            )
        )

        XCTAssertEqual(projection.detailText, "国语 · 2026")
    }

    func testEpisodeDisplayLabelPreservesProviderLabelsAndHidesOpaqueKeys() {
        XCTAssertEqual(EpisodeDisplayLabel.sanitized("第10集", excluding: ["episode-10"]), "第10集")
        XCTAssertNil(EpisodeDisplayLabel.sanitized("fz4AxompbuT"))
        XCTAssertNil(EpisodeDisplayLabel.sanitized("episode-10", excluding: [" episode-10 "]))
    }

    func testPosterProjectionDoesNotTreatMovieSubtitleAsEpisode() {
        let projection = PosterCardProjection(
            item: MyVideoItem(
                listPath: "movie",
                title: "Movie",
                subTitle: "New release",
                year: "2026",
                isSerial: false,
                language: "国语"
            )
        )

        XCTAssertEqual(projection.detailText, "国语 · 2026")
    }

    func testPromotesAValidatedNewerEpisodeAndDeduplicatesSnapshot() {
        let previous = SavedEpisodeUpdateState(
            episodes: [
                EpisodeSelection(mediaKey: "episode-9", title: "09"),
                EpisodeSelection(mediaKey: "episode-8", title: "08")
            ],
            latestEpisodeKey: "episode-9",
            seenEpisodeKey: "episode-9",
            detectedAt: Date(timeIntervalSince1970: 100),
            lastObservedAt: Date(timeIntervalSince1970: 100)
        )

        let result = SavedEpisodeSnapshotReconciler.reconcile(
            previous: previous,
            observedEpisodes: [
                EpisodeSelection(mediaKey: "episode-10", title: "10"),
                EpisodeSelection(mediaKey: "episode-10", title: "10 duplicate"),
                EpisodeSelection(mediaKey: "episode-9", title: "09")
            ],
            previouslySeenKey: "episode-9",
            observedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result?.state.latestEpisodeKey, "episode-10")
        XCTAssertEqual(result?.state.episodes.map(\.mediaKey), ["episode-10", "episode-9", "episode-8"])
        XCTAssertEqual(result?.state.seenEpisodeKey, "episode-9")
        XCTAssertEqual(result?.state.detectedAt, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(result?.didAdvance == true)
    }

    func testPartialOlderSnapshotCannotRegressLatestEpisode() {
        let previous = SavedEpisodeUpdateState(
            episodes: [
                EpisodeSelection(mediaKey: "episode-10", title: "10"),
                EpisodeSelection(mediaKey: "episode-9", title: "09")
            ],
            latestEpisodeKey: "episode-10",
            seenEpisodeKey: "episode-9",
            detectedAt: Date(timeIntervalSince1970: 100),
            lastObservedAt: Date(timeIntervalSince1970: 100)
        )

        let result = SavedEpisodeSnapshotReconciler.reconcile(
            previous: previous,
            observedEpisodes: [EpisodeSelection(mediaKey: "episode-9", title: "09")],
            previouslySeenKey: "episode-9",
            observedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result?.state.latestEpisodeKey, "episode-10")
        XCTAssertEqual(result?.state.episodes.map(\.mediaKey), ["episode-10", "episode-9"])
        XCTAssertEqual(result?.state.detectedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(result?.state.lastObservedAt, Date(timeIntervalSince1970: 200))
        XCTAssertFalse(result?.didAdvance == true)
    }

    func testProviderOrderPromotesNonnumericEpisodeWhenCurrentEpisodeIsPresent() {
        let previous = SavedEpisodeUpdateState(
            episodes: [EpisodeSelection(mediaKey: "special-a", title: "Special A")],
            latestEpisodeKey: "special-a",
            seenEpisodeKey: "special-a",
            detectedAt: nil,
            lastObservedAt: nil
        )

        let result = SavedEpisodeSnapshotReconciler.reconcile(
            previous: previous,
            observedEpisodes: [
                EpisodeSelection(mediaKey: "special-b", title: "Special B"),
                EpisodeSelection(mediaKey: "special-a", title: "Special A")
            ],
            previouslySeenKey: "special-a",
            observedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result?.state.latestEpisodeKey, "special-b")
        XCTAssertTrue(result?.didAdvance == true)
    }

    func testUnknownNonnumericSnapshotCannotDisplaceKnownLatest() {
        let previous = SavedEpisodeUpdateState(
            episodes: [EpisodeSelection(mediaKey: "special-b", title: "Special B")],
            latestEpisodeKey: "special-b",
            seenEpisodeKey: "special-b",
            detectedAt: nil,
            lastObservedAt: nil
        )

        let result = SavedEpisodeSnapshotReconciler.reconcile(
            previous: previous,
            observedEpisodes: [EpisodeSelection(mediaKey: "unknown", title: "Unknown")],
            previouslySeenKey: "special-b",
            observedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result?.state.latestEpisodeKey, "special-b")
        XCTAssertFalse(result?.didAdvance == true)
    }

    func testLegacyMediaKeyNumberCanAdvanceAfterMetadataMigration() {
        let previous = SavedEpisodeUpdateState(
            episodes: [EpisodeSelection(mediaKey: "episode-9", title: "episode-9")],
            latestEpisodeKey: "episode-9",
            seenEpisodeKey: "episode-9",
            detectedAt: nil,
            lastObservedAt: nil
        )

        let result = SavedEpisodeSnapshotReconciler.reconcile(
            previous: previous,
            observedEpisodes: [EpisodeSelection(mediaKey: "episode-10", title: "10")],
            previouslySeenKey: "episode-9",
            observedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(result?.state.latestEpisodeKey, "episode-10")
        XCTAssertTrue(result?.didAdvance == true)
    }

    func testCatalogMergeUsesNewProviderValuesWithoutErasingKnownMetadata() {
        let saved = MyVideoItem(
            listPath: "series",
            title: "Original",
            verticalImg: "https://example.com/poster.jpg",
            subTitle: "09",
            year: "2026",
            region: "Mainland China",
            isSerial: true,
            score: 8.5
        )
        let observation = MyVideoItem(
            listPath: "series",
            title: "Updated title",
            subTitle: "10",
            addTime: "2026-09-08",
            isSerial: true,
            score: 9.0
        )

        let merged = SavedCatalogItemReconciler.merge(saved: saved, observed: observation)

        XCTAssertEqual(merged.title, "Updated title")
        XCTAssertEqual(merged.subTitle, "10")
        XCTAssertEqual(merged.addTime, "2026-09-08")
        XCTAssertEqual(merged.verticalImg, "https://example.com/poster.jpg")
        XCTAssertEqual(merged.year, "2026")
        XCTAssertEqual(merged.region, "Mainland China")
        XCTAssertEqual(merged.score, 9.0)
    }
}

@MainActor
final class SavedLibraryObservationStoreTests: XCTestCase {
    func testPlayerObservationPromotesSavedEpisodeAndPersistsWithoutChangingPreferences() {
        let suiteName = "SavedLibraryObservationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "series", title: "Series", isSerial: true)
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        store.setNotificationsEnabled(false, for: item)
        _ = store.observeEpisodes(
            itemID: item.id,
            episodes: [EpisodeSelection(mediaKey: "episode-9", title: "09")],
            observedAt: Date(timeIntervalSince1970: 100)
        )

        let updates = store.observeEpisodes(
            itemID: item.id,
            episodes: [
                EpisodeSelection(mediaKey: "episode-10", title: "10"),
                EpisodeSelection(mediaKey: "episode-9", title: "09")
            ],
            observedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(updates.map(\.episode.mediaKey), ["episode-10"])
        XCTAssertEqual(store.episodeUpdateState(for: item)?.latestEpisodeKey, "episode-10")
        XCTAssertFalse(store.notificationsEnabled(for: item))
        let restored = SavedItemsStore(defaults: defaults)
        XCTAssertEqual(restored.episodeUpdateState(for: item)?.latestEpisodeKey, "episode-10")
        XCTAssertFalse(restored.notificationsEnabled(for: item))
    }

    func testCatalogObservationUpdatesSavedCopyAndSortsByUpdatedDateDescending() {
        let suiteName = "SavedLibraryObservationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = MyVideoItem(listPath: "first", title: "First", subTitle: "09", addTime: "2026-09-01")
        let second = MyVideoItem(listPath: "second", title: "Second", addTime: "2026-09-02")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(second)
        store.toggle(first)

        _ = store.refreshUpdateMarkers(with: [
            .drama: [MyVideoItem(listPath: "first", title: "First", subTitle: "10", addTime: "2026-09-03")]
        ])

        XCTAssertEqual(store.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.items.first?.subTitle, "10")
        XCTAssertEqual(SavedItemsStore(defaults: defaults).items.first?.subTitle, "10")
    }

    func testReconciledEpisodeCannotBeDowngradedByStaleCatalogObservation() throws {
        let suiteName = "SavedLibraryObservationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(
            listPath: "series",
            title: "Series",
            subTitle: "09",
            isSerial: true,
            latestEpisodeKey: "episode-9",
            latestEpisodeTitle: "09"
        )
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)
        _ = store.observeEpisodes(
            itemID: item.id,
            episodes: [EpisodeSelection(mediaKey: "episode-9", title: "09")],
            observedAt: Date(timeIntervalSince1970: 100)
        )
        _ = store.observeEpisodes(
            itemID: item.id,
            episodes: [
                EpisodeSelection(mediaKey: "episode-10", title: "10"),
                EpisodeSelection(mediaKey: "episode-9", title: "09")
            ],
            observedAt: Date(timeIntervalSince1970: 200)
        )

        _ = store.refreshUpdateMarkers(with: [
            .drama: [MyVideoItem(
                listPath: "series",
                title: "Series",
                subTitle: "09",
                isSerial: true,
                latestEpisodeKey: "episode-9",
                latestEpisodeTitle: "09"
            )]
        ])

        let saved = try XCTUnwrap(store.items.first)
        XCTAssertEqual(saved.latestEpisodeKey, "episode-10")
        XCTAssertEqual(saved.latestEpisodeTitle, "10")
        XCTAssertEqual(saved.subTitle, "10")
        XCTAssertEqual(SavedItemsStore(defaults: defaults).items.first?.latestEpisodeKey, "episode-10")
    }
}
