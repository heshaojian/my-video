import AVFoundation
import XCTest
@testable import MyVideo

@MainActor
final class PlaybackSessionControllerTests: XCTestCase {
    func testCollapseAndExpandReuseTheSamePlayerWithoutStopping() async throws {
        let controller = makeController()
        let store = PlayedItemsStore(defaults: UserDefaults())
        let item = MyVideoItem(listPath: "movie-a", title: "Movie A")

        controller.play(item: item, episodeKey: nil, playedItemsStore: store, monitorPlayback: false)
        let viewModel = try XCTUnwrap(controller.viewModel)
        try await waitUntil { viewModel.preparedEntryCount == 1 }

        controller.collapse()
        XCTAssertEqual(controller.presentation, .collapsed)
        XCTAssertTrue(controller.viewModel === viewModel)
        XCTAssertEqual(viewModel.preparedEntryCount, 1)

        controller.expand()
        XCTAssertEqual(controller.presentation, .expanded)
        XCTAssertTrue(controller.viewModel === viewModel)
        XCTAssertEqual(viewModel.preparedEntryCount, 1)

        controller.stop()
        XCTAssertEqual(controller.presentation, .inactive)
        XCTAssertNil(controller.viewModel)
        XCTAssertTrue(viewModel.player.items().isEmpty)
    }

    func testPlayingAnotherTitleStopsAndReplacesThePriorSession() async throws {
        let controller = makeController()
        let store = PlayedItemsStore(defaults: UserDefaults())

        controller.play(
            item: MyVideoItem(listPath: "movie-a", title: "Movie A"),
            episodeKey: nil,
            playedItemsStore: store,
            monitorPlayback: false
        )
        let first = try XCTUnwrap(controller.viewModel)
        try await waitUntil { first.preparedEntryCount == 1 }

        controller.play(
            item: MyVideoItem(listPath: "movie-b", title: "Movie B"),
            episodeKey: nil,
            playedItemsStore: store,
            monitorPlayback: false
        )
        let second = try XCTUnwrap(controller.viewModel)

        XCTAssertFalse(first === second)
        XCTAssertTrue(first.player.items().isEmpty)
        XCTAssertEqual(controller.presentation, .expanded)
        XCTAssertEqual(controller.item?.id, "movie-b")
        controller.stop()
    }

    func testSelectingTheActiveTitleOnlyExpandsItsExistingSession() async throws {
        let controller = makeController()
        let store = PlayedItemsStore(defaults: UserDefaults())
        let item = MyVideoItem(listPath: "movie-a", title: "Movie A")

        controller.play(item: item, episodeKey: nil, playedItemsStore: store, monitorPlayback: false)
        let original = try XCTUnwrap(controller.viewModel)
        try await waitUntil { original.preparedEntryCount == 1 }
        controller.collapse()

        controller.play(item: item, episodeKey: nil, playedItemsStore: store, monitorPlayback: false)

        XCTAssertTrue(controller.viewModel === original)
        XCTAssertEqual(controller.presentation, .expanded)
        controller.stop()
    }

    private func makeController() -> PlaybackSessionController {
        PlaybackSessionController { item, episodeKey, playedItemsStore, onEpisodesObserved in
            NativePlayerViewModel(
                item: item,
                initialEpisodeKey: episodeKey,
                resolver: SessionPlaybackResolver(),
                playedItemsStore: playedItemsStore,
                qualityLoader: EmptyQualityLoader(),
                onEpisodesObserved: onEpisodesObserved
            )
        }
    }

    private func waitUntil(
        timeoutIterations: Int = 250,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition was not satisfied before timeout")
    }
}

private struct SessionPlaybackResolver: NativePlaybackResolving {
    func resolve(item: MyVideoItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        NativePlayback(entries: [
            NativePlaybackEntry(
                url: URL(string: "https://media.example.com/\(item.id).m3u8")!,
                isAdvertisement: false
            )
        ])
    }
}

private struct EmptyQualityLoader: PlaybackQualityLoading {
    func loadOptions(for url: URL) async throws -> [PlaybackQualityOption] { [] }
}
