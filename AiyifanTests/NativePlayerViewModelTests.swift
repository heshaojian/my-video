import Foundation
import XCTest
@testable import Aiyifan

@MainActor
final class NativePlayerViewModelTests: XCTestCase {
    func testStartQueuesAdvertisementBeforeProgram() async throws {
        let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(
                url: URL(string: "https://ads.example.com/front.mp4")!,
                isAdvertisement: true
            ),
            NativePlaybackEntry(
                url: URL(string: "https://media.example.com/full.m3u8")!,
                isAdvertisement: false
            )
        ], episodes: [episode], selectedEpisode: episode)
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "media-key", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playback)
        )

        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 2 }

        XCTAssertEqual(viewModel.preparedEntryCount, 2)
        XCTAssertEqual(viewModel.episodeTitle, "04")
        viewModel.stop()
        XCTAssertTrue(viewModel.player.items().isEmpty)
    }

    func testResolverErrorBecomesUserFacingPlaybackError() async throws {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "media-key", title: "Movie"),
            resolver: StubPlaybackResolver(error: .loginRequired)
        )

        viewModel.start()
        try await waitUntil { viewModel.errorMessage != nil }

        XCTAssertEqual(viewModel.errorMessage, "This title requires you to sign in on the website.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testAdvertisementMutesAndProgramRestoresPreviousSoundState() async throws {
        let playback = playbackWithAdvertisement()
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playback)
        )
        viewModel.player.isMuted = false
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "04" }

        viewModel.handlePlaybackEntry(index: 0, position: 10, duration: 20)
        XCTAssertTrue(viewModel.player.isMuted)
        XCTAssertTrue(viewModel.isPlayingAdvertisement)

        viewModel.handlePlaybackEntry(index: 1, position: 0, duration: 100)
        XCTAssertFalse(viewModel.player.isMuted)
        XCTAssertFalse(viewModel.isPlayingAdvertisement)
        viewModel.stop()
    }

    func testAdvertisementPreservesAnExistingMuteChoice() async throws {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement())
        )
        viewModel.player.isMuted = true
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "04" }

        viewModel.handlePlaybackEntry(index: 0, position: 10, duration: 20)
        viewModel.handlePlaybackEntry(index: 1, position: 0, duration: 100)

        XCTAssertTrue(viewModel.player.isMuted)
        viewModel.stop()
    }

    func testPlayedHistoryStartsWithProgramAndIgnoresAdvertisementProgress() async throws {
        let (store, defaults, suiteName) = playedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "series", title: "Series")
        let viewModel = NativePlayerViewModel(
            item: item,
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            playedItemsStore: store
        )
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "04" }

        viewModel.handlePlaybackEntry(index: 0, position: 15, duration: 20)
        XCTAssertTrue(store.items.isEmpty)

        viewModel.handlePlaybackEntry(index: 1, position: 30, duration: 100)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].episodeKey, "episode-4")
        XCTAssertEqual(store.items[0].position, 30)

        viewModel.handlePlaybackEntry(index: 1, position: 35, duration: 100)
        XCTAssertEqual(store.items[0].position, 30)
        viewModel.handlePlaybackEntry(index: 1, position: 41, duration: 100)
        XCTAssertEqual(store.items[0].position, 41)
        viewModel.stop()
    }

    func testResumeAndEpisodeSelectionUseEpisodeSpecificRecord() async throws {
        let (store, defaults, suiteName) = playedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "series", title: "Series")
        let older = Episode(mediaKey: "episode-3", title: "03", updateDate: nil)
        store.record(item: item, episode: older, position: 42, duration: 100)
        let viewModel = NativePlayerViewModel(
            item: item,
            initialEpisodeKey: older.mediaKey,
            resolver: EpisodeAwareStubResolver(),
            playedItemsStore: store
        )

        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "03" }
        XCTAssertEqual(viewModel.pendingResumePosition, 42)

        viewModel.selectEpisode(Episode(mediaKey: "episode-4", title: "04", updateDate: nil))
        try await waitUntil { viewModel.episodeTitle == "04" }
        XCTAssertEqual(viewModel.pendingResumePosition, 0)
        viewModel.stop()
    }

    func testResolvedPlaybackPreparesCastQueueAtResumePosition() async throws {
        let (store, defaults, suiteName) = playedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "series", title: "Series")
        let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
        store.record(item: item, episode: episode, position: 42, duration: 100)
        let castManager = MockCastPlaybackManager()
        let viewModel = NativePlayerViewModel(
            item: item,
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            playedItemsStore: store,
            castManager: castManager
        )

        viewModel.start()
        try await waitUntil { castManager.preparedPlans.count == 1 }

        XCTAssertEqual(castManager.preparedPlans[0].entries.map(\.startPosition), [0, 42])
        XCTAssertEqual(castManager.loadIfConnectedValues, [true])
        viewModel.handlePlaybackEntry(index: 1, position: 63, duration: 100)
        XCTAssertEqual(castManager.updatedPositions, [63])
        viewModel.stop()
    }

    func testExistingCastSessionPreventsDuplicateLocalPlayback() async throws {
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            castManager: castManager
        )

        viewModel.start()
        try await waitUntil { castManager.preparedPlans.count == 1 }

        XCTAssertEqual(viewModel.player.rate, 0)
        viewModel.stop()
    }

    func testProgramWithoutAdvertisementKeepsResumePendingUntilPlayerIsReady() async throws {
        let (store, defaults, suiteName) = playedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "movie", title: "Movie")
        store.record(item: item, episode: nil, position: 42, duration: 100)
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(
                url: URL(string: "https://media.example.com/full.m3u8")!,
                isAdvertisement: false
            )
        ])
        let castManager = MockCastPlaybackManager()
        let viewModel = NativePlayerViewModel(
            item: item,
            resolver: StubPlaybackResolver(playback: playback),
            playedItemsStore: store,
            castManager: castManager
        )

        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }
        viewModel.handlePlaybackEntry(index: 0, position: 0, duration: 100)

        XCTAssertFalse(viewModel.hasAppliedResume)
        XCTAssertEqual(viewModel.pendingResumePosition, 42)
        XCTAssertTrue(castManager.updatedPositions.isEmpty)
        viewModel.stop()
    }

    private func waitUntil(
        timeoutIterations: Int = 250,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition was not satisfied before timeout")
    }

    private func playbackWithAdvertisement() -> NativePlayback {
        let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
        return NativePlayback(entries: [
            NativePlaybackEntry(url: URL(string: "https://ads.example.com/front.mp4")!, isAdvertisement: true),
            NativePlaybackEntry(url: URL(string: "https://media.example.com/full.m3u8")!, isAdvertisement: false)
        ], episodes: [episode], selectedEpisode: episode)
    }

    private func playedStore() -> (PlayedItemsStore, UserDefaults, String) {
        let suiteName = "NativePlayerViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (PlayedItemsStore(defaults: defaults), defaults, suiteName)
    }
}

@MainActor
private final class MockCastPlaybackManager: CastPlaybackManaging {
    var isCasting = false
    private(set) var preparedPlans: [CastPlaybackPlan] = []
    private(set) var loadIfConnectedValues: [Bool] = []
    private(set) var updatedPositions: [Double] = []

    func configure() {}

    func prepare(_ plan: CastPlaybackPlan, loadIfConnected: Bool) {
        preparedPlans = preparedPlans + [plan]
        loadIfConnectedValues = loadIfConnectedValues + [loadIfConnected]
    }

    func updateProgramPosition(_ position: Double) {
        updatedPositions = updatedPositions + [position]
    }
    func clear() {}
}

private struct StubPlaybackResolver: NativePlaybackResolving {
    let playback: NativePlayback?
    let error: NativePlaybackError?

    init(playback: NativePlayback? = nil, error: NativePlaybackError? = nil) {
        self.playback = playback
        self.error = error
    }

    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        if let error {
            throw error
        }
        return playback ?? NativePlayback(entries: [])
    }
}

private struct EpisodeAwareStubResolver: NativePlaybackResolving {
    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        let episodes = [
            Episode(mediaKey: "episode-4", title: "04", updateDate: nil),
            Episode(mediaKey: "episode-3", title: "03", updateDate: nil)
        ]
        let selected = episodes.first { $0.mediaKey == preferredEpisodeKey } ?? episodes[0]
        return NativePlayback(
            entries: [NativePlaybackEntry(
                url: URL(string: "https://media.example.com/\(selected.mediaKey).m3u8")!,
                isAdvertisement: false
            )],
            episodes: episodes,
            selectedEpisode: selected
        )
    }
}
