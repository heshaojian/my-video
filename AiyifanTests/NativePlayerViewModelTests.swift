import AVFoundation
import Foundation
import XCTest
@testable import Aiyifan

@MainActor
final class NativePlayerViewModelTests: XCTestCase {
    func testSerialCatalogItemExposesEpisodeControlBeforeAndAfterResolution() async throws {
        let episodes = (1...10).reversed().map {
            Episode(mediaKey: "episode-\($0)", title: String(format: "%02d", $0), updateDate: nil)
        }
        let playback = NativePlayback(
            entries: [NativePlaybackEntry(
                url: URL(string: "https://media.example.com/episode-10.m3u8")!,
                isAdvertisement: false
            )],
            episodes: episodes,
            selectedEpisode: episodes[0]
        )
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(
                listPath: "series",
                title: "Series",
                isSerial: true,
                latestEpisodeKey: "episode-10",
                latestEpisodeTitle: "10",
                categoryPath: "0,1,4,152"
            ),
            resolver: StubPlaybackResolver(playback: playback)
        )

        XCTAssertTrue(viewModel.shouldShowEpisodeControl)
        XCTAssertEqual(viewModel.episodeControlTitle, "Loading Episodes")

        viewModel.start()
        try await waitUntil { viewModel.episodes.count == 10 }

        XCTAssertEqual(viewModel.episodeControlTitle, "Episode 10/10")
        XCTAssertEqual(viewModel.episodes.map(\.mediaKey), (1...10).reversed().map { "episode-\($0)" })
        viewModel.stop()
    }

    func testPlayerPublishesResolvedViewerMetrics() async throws {
        let metrics = ViewerMetrics(likes: 76, favorites: 221, score: 9.6, views: 170_000)
        let playback = NativePlayback(
            entries: [NativePlaybackEntry(
                url: URL(string: "https://media.example.com/movie.m3u8")!,
                isAdvertisement: false
            )],
            metrics: metrics
        )
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Original Title"),
            resolver: StubPlaybackResolver(playback: playback)
        )

        viewModel.start()
        try await waitUntil { viewModel.viewerMetrics != nil }

        XCTAssertEqual(viewModel.viewerMetrics, metrics)
        viewModel.stop()
    }

    func testEnglishMetricFormattingUsesCompactCountsAndValidatedScores() {
        XCTAssertEqual(CompactMetricFormatter.count(983), "983")
        XCTAssertEqual(CompactMetricFormatter.count(9_831), "9.8K")
        XCTAssertEqual(CompactMetricFormatter.count(170_000), "170K")
        XCTAssertEqual(CompactMetricFormatter.count(1_250_000), "1.3M")
        XCTAssertEqual(CompactMetricFormatter.score(9.6), "9.6")
        XCTAssertEqual(CompactMetricFormatter.score(6), "6.0")
    }

    func testMovieWithoutEpisodesDoesNotExposeEpisodeControl() {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie", isSerial: false),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: []))
        )

        XCTAssertFalse(viewModel.shouldShowEpisodeControl)
        XCTAssertNil(viewModel.episodeControlTitle)
    }

    func testPlayedEpisodeKeyRestoresEpisodeControlForLegacyItem() async throws {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "legacy-series", title: "Legacy Series"),
            initialEpisodeKey: "episode-4",
            resolver: FixtureNativePlaybackResolver()
        )

        XCTAssertTrue(viewModel.shouldShowEpisodeControl)
        XCTAssertEqual(viewModel.episodeControlTitle, "Loading Episodes")

        viewModel.start()
        try await waitUntil { viewModel.selectedEpisode?.mediaKey == "episode-4" }

        XCTAssertEqual(viewModel.episodes.count, 3)
        XCTAssertEqual(viewModel.episodeControlTitle, "Episode 4/10")
        viewModel.stop()
    }

    func testEpisodeDisplayFormatterNormalizesNumericAndSpecialTitles() {
        XCTAssertEqual(EpisodeDisplayFormatter.title(for: "第10集"), "第10集")
        XCTAssertEqual(EpisodeDisplayFormatter.title(for: "Episode 04"), "Episode 04")
        XCTAssertEqual(EpisodeDisplayFormatter.title(for: " Special "), "Special")
        XCTAssertEqual(EpisodeDisplayFormatter.title(for: "2026 特别篇"), "2026 特别篇")
        XCTAssertEqual(EpisodeDisplayFormatter.title(for: "SP 2"), "SP 2")
    }

    func testPresentationTransitionDoesNotStopUntilScreenActuallyDisappears() {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: []))
        )
        viewModel.player.insert(
            AVPlayerItem(url: URL(string: "https://media.example.com/full.m3u8")!),
            after: nil
        )

        viewModel.setFullScreenPresentationActive(true)
        viewModel.handleScreenDisappear()
        XCTAssertEqual(viewModel.player.items().count, 1)

        viewModel.setFullScreenPresentationActive(false)
        XCTAssertEqual(viewModel.player.items().count, 1)

        viewModel.handleScreenDisappear()
        XCTAssertTrue(viewModel.player.items().isEmpty)
    }

    func testStartQueuesOnlyProgramAndRepeatedStartIsIdempotent() async throws {
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
        let resolver = CountingPlaybackResolver(playback: playback)
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "media-key", title: "Movie"),
            resolver: resolver
        )

        viewModel.start()
        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }

        let resolveCount = await resolver.resolveCount()
        XCTAssertEqual(viewModel.preparedEntryCount, 1)
        XCTAssertEqual(resolveCount, 1)
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

    func testAdvertisementEntriesAreNeverPreparedOrShown() async throws {
        let playback = playbackWithAdvertisement()
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playback)
        )
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "04" }

        XCTAssertEqual(viewModel.preparedEntryCount, 1)
        viewModel.stop()
    }

    func testRemovingAdvertisementPreservesExistingMuteChoice() async throws {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement())
        )
        viewModel.player.isMuted = true
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "04" }

        XCTAssertTrue(viewModel.player.isMuted)
        viewModel.stop()
    }

    func testPlayedHistoryAdvancesOnlyWhileProgramIsActuallyPlaying() async throws {
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

        viewModel.handlePlaybackEntry(index: 0, position: 15, duration: 100, isPlaying: false)
        XCTAssertTrue(store.items.isEmpty)

        viewModel.handlePlaybackEntry(index: 0, position: 30, duration: 100, isPlaying: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].episodeKey, "episode-4")
        XCTAssertEqual(store.items[0].position, 30)

        viewModel.handlePlaybackEntry(index: 0, position: 35, duration: 100, isPlaying: true)
        XCTAssertEqual(store.items[0].position, 30)
        viewModel.handlePlaybackEntry(index: 0, position: 41, duration: 100, isPlaying: false)
        XCTAssertEqual(store.items[0].position, 41)
        viewModel.handlePlaybackEntry(index: 0, position: 70, duration: 100, isPlaying: false)
        XCTAssertEqual(store.items[0].position, 41)
        viewModel.stop()
    }

    func testPresentationStateKeepsSessionAliveDuringFullscreenAndPictureInPicture() {
        var state = PlayerPresentationState()

        XCTAssertTrue(state.shouldStopOnDisappear)
        state.setFullScreenActive(true)
        XCTAssertFalse(state.shouldStopOnDisappear)
        state.setPictureInPictureActive(true)
        state.setFullScreenActive(false)
        XCTAssertFalse(state.shouldStopOnDisappear)
        state.setPictureInPictureActive(false)
        XCTAssertTrue(state.shouldStopOnDisappear)
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

        XCTAssertEqual(castManager.preparedPlans[0].entries.map(\.startPosition), [42])
        XCTAssertEqual(castManager.loadIfConnectedValues, [true])
        viewModel.handlePlaybackEntry(index: 0, position: 63, duration: 100, isPlaying: true)
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
        viewModel.handlePlaybackEntry(index: 0, position: 0, duration: 100, isPlaying: false)

        XCTAssertFalse(viewModel.hasAppliedResume)
        XCTAssertEqual(viewModel.pendingResumePosition, 42)
        XCTAssertTrue(castManager.updatedPositions.isEmpty)
        viewModel.stop()
    }

    func testNextAndPreviousEpisodeFollowChronologicalOrder() async throws {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "series", title: "Series"),
            initialEpisodeKey: "episode-3",
            resolver: EpisodeAwareStubResolver()
        )
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "03" }

        XCTAssertEqual(viewModel.nextEpisode?.mediaKey, "episode-4")
        XCTAssertNil(viewModel.previousEpisode)

        viewModel.playNextEpisode()
        try await waitUntil { viewModel.episodeTitle == "04" }
        XCTAssertNil(viewModel.nextEpisode)
        XCTAssertEqual(viewModel.previousEpisode?.mediaKey, "episode-3")
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

private actor CountingPlaybackResolver: NativePlaybackResolving {
    private let playback: NativePlayback
    private var count = 0

    init(playback: NativePlayback) {
        self.playback = playback
    }

    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        count += 1
        return playback
    }

    func resolveCount() -> Int {
        count
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
