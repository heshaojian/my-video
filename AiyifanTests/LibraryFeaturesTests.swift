import XCTest
@testable import Aiyifan

final class LibraryFeaturesTests: XCTestCase {
    func testSearchCombinesTextCategoryLanguageYearAndWatchState() {
        let documents = [
            LibraryDocument(
                item: AiyifanItem(listPath: "cn-drama", title: "漫长的季节 2023", subTitle: "更新至12集"),
                category: .drama,
                watchState: .inProgress,
                hasNewUpdate: true
            ),
            LibraryDocument(
                item: AiyifanItem(listPath: "en-movie", title: "The Brutalist", subTitle: "Movie 2024"),
                category: .movie,
                watchState: .unplayed,
                hasNewUpdate: false
            )
        ]
        let filter = LibraryFilter(
            query: "季节",
            category: .drama,
            language: .chinese,
            year: 2023,
            watchState: .newUpdate
        )

        XCTAssertEqual(LibrarySearchEngine.results(in: documents, matching: filter).map(\.item.id), ["cn-drama"])
    }

    func testLanguageAndYearClassificationAreHonestAboutUnknownMetadata() {
        let chinese = AiyifanItem(listPath: "cn", title: "庆余年")
        let english = AiyifanItem(listPath: "en", title: "Severance")
        let ambiguous = AiyifanItem(listPath: "ambiguous", title: "1234")
        let dated = AiyifanItem(listPath: "dated", title: "Movie", subTitle: "Released 2025")

        XCTAssertEqual(ContentLanguage.classify(chinese), .chinese)
        XCTAssertEqual(ContentLanguage.classify(english), .english)
        XCTAssertEqual(ContentLanguage.classify(ambiguous), .unknown)
        XCTAssertEqual(LibraryMetadata.year(for: dated), 2025)
    }

    func testContinueWatchingKeepsLatestIncompleteEpisodePerTitle() {
        let show = AiyifanItem(listPath: "show", title: "Show")
        let movie = AiyifanItem(listPath: "movie", title: "Movie")
        let records = [
            record(item: show, episode: "03", position: 20, duration: 100, date: 300),
            record(item: show, episode: "02", position: 40, duration: 100, date: 200),
            record(item: movie, episode: nil, position: 95, duration: 100, date: 400)
        ]

        let projected = ContinueWatchingProjector.records(from: records)

        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected[0].episodeKey, "03")
    }

    func testUpdateTrackerSuppressesBaselineAndReturnsOnlyChangedSavedTitles() {
        let previous = [
            "saved": UpdateMarker(itemID: "saved", updateKey: "episode-3"),
            "unsaved": UpdateMarker(itemID: "unsaved", updateKey: "episode-1")
        ]
        let current = [
            "saved": UpdateMarker(itemID: "saved", updateKey: "episode-4"),
            "unsaved": UpdateMarker(itemID: "unsaved", updateKey: "episode-2")
        ]

        XCTAssertTrue(UpdateTracker.changedItemIDs(previous: nil, current: current, savedItemIDs: ["saved"]).isEmpty)
        XCTAssertEqual(
            UpdateTracker.changedItemIDs(previous: previous, current: current, savedItemIDs: ["saved"]),
            ["saved"]
        )
    }

    func testEpisodeNavigatorUsesChronologicalPlaybackFromNewestFirstList() {
        let episodes = [
            Episode(mediaKey: "4", title: "04", updateDate: nil),
            Episode(mediaKey: "3", title: "03", updateDate: nil),
            Episode(mediaKey: "2", title: "02", updateDate: nil)
        ]

        XCTAssertEqual(EpisodeNavigator.next(in: episodes, current: episodes[1])?.mediaKey, "4")
        XCTAssertEqual(EpisodeNavigator.previous(in: episodes, current: episodes[1])?.mediaKey, "2")
        XCTAssertNil(EpisodeNavigator.next(in: episodes, current: episodes[0]))
        XCTAssertNil(EpisodeNavigator.previous(in: episodes, current: episodes[2]))
    }

    private func record(
        item: AiyifanItem,
        episode: String?,
        position: Double,
        duration: Double,
        date: TimeInterval
    ) -> PlayedRecord {
        PlayedRecord(
            item: item,
            episodeKey: episode,
            episodeTitle: episode,
            position: position,
            duration: duration,
            lastPlayedAt: Date(timeIntervalSince1970: date)
        )
    }
}
