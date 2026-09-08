import Combine
import XCTest
@testable import Aiyifan

@MainActor
final class LibraryFeaturesTests: XCTestCase {
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

    func testExactEpisodeSelectionPublishesEpisodeKeyBeforeItem() {
        let viewModel = BrowserViewModel()
        let item = AiyifanItem(listPath: "series", title: "Series", isSerial: true)
        var observedEpisodeKey: String?
        let observation = viewModel.$selectedItem
            .dropFirst()
            .sink { _ in observedEpisodeKey = viewModel.selectedEpisodeKey }

        viewModel.selectItem(item, episodeKey: "episode-8")

        XCTAssertEqual(observedEpisodeKey, "episode-8")
        XCTAssertEqual(viewModel.selectedItem, item)
        withExtendedLifetime(observation) {}
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
