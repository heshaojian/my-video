import AVFoundation
import Foundation
import XCTest
@testable import MyVideo

@MainActor
final class NativePlayerViewModelTests: XCTestCase {
    func testPlayerAppliesDefault1080QualityAndChangesItWithoutReplacingCurrentItem() async throws {
        let suite = "NativePlayerQualityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality")
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 3_840, height: 1_608, averageBitRate: 12_000_000, peakBitRate: 16_000_000),
            PlaybackVariantDescriptor(width: 1_920, height: 804, averageBitRate: 5_000_000, peakBitRate: 7_000_000),
            PlaybackVariantDescriptor(width: 1_280, height: 536, averageBitRate: 3_000_000, peakBitRate: 4_000_000)
        ])
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(
                url: URL(string: "https://media.example.com/master.m3u8")!,
                isAdvertisement: false
            )
        ])
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playback),
            castManager: castManager,
            qualityLoader: StubQualityLoader(options: options),
            qualityPreferences: preferences
        )

        viewModel.start()
        try await waitUntil { viewModel.selectedQuality?.tierHeight == 1_080 }

        let currentItem = try XCTUnwrap(viewModel.preparedPlayerItems.first)
        XCTAssertEqual(viewModel.qualityOptions.map(\.tierHeight), [2_160, 1_080, 720])
        XCTAssertEqual(viewModel.qualityOptions.map(\.height), [1_608, 804, 536])
        XCTAssertEqual(currentItem.preferredMaximumResolution, CGSize(width: 1_920, height: 804))
        XCTAssertEqual(currentItem.preferredPeakBitRate, 7_000_000)

        let lower = try XCTUnwrap(viewModel.qualityOptions.first { $0.tierHeight == 720 })
        viewModel.setQuality(lower)

        XCTAssertTrue(viewModel.preparedPlayerItems.first === currentItem)
        XCTAssertEqual(viewModel.manualQualityOptions.map(\.tierHeight), [2_160, 1_080, 720])
        XCTAssertFalse(viewModel.usesAutomaticQuality)
        XCTAssertEqual(viewModel.selectedQuality?.tierHeight, 720)
        XCTAssertEqual(currentItem.preferredMaximumResolution, CGSize(width: 1_280, height: 536))
        XCTAssertEqual(currentItem.preferredPeakBitRate, 4_000_000)
        XCTAssertEqual(preferences.targetHeight, 720)

        viewModel.setAutomaticQuality()
        XCTAssertTrue(viewModel.usesAutomaticQuality)
        XCTAssertTrue(viewModel.preparedPlayerItems.first === currentItem)
        XCTAssertEqual(viewModel.selectedQuality?.tierHeight, 1_080)
        XCTAssertEqual(currentItem.preferredMaximumResolution, CGSize(width: 1_920, height: 804))
        XCTAssertEqual(currentItem.preferredPeakBitRate, 7_000_000)
        viewModel.stop()
    }

    func testSingleQualityIsAppliedAndStillExposesAutomaticQualityControl() async throws {
        let option = PlaybackQualityOption(
            width: 1_280,
            height: 720,
            averageBitRate: 3_000_000,
            peakBitRate: 4_000_000
        )
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/master.m3u8")!,
                    isAdvertisement: false
                )
            ])),
            castManager: castManager,
            qualityLoader: StubQualityLoader(options: [option])
        )

        viewModel.start()
        try await waitUntil { viewModel.selectedQuality != nil }

        XCTAssertTrue(viewModel.usesAutomaticQuality)
        XCTAssertTrue(viewModel.manualQualityOptions.isEmpty)
        XCTAssertEqual(viewModel.qualityAvailabilityText, "720p only")
        let preparedItem = try XCTUnwrap(viewModel.preparedPlayerItems.first)
        XCTAssertEqual(preparedItem.preferredMaximumResolution, CGSize(width: 1_280, height: 720))
        viewModel.stop()
    }

    func testUnknownStreamReportsQualityUnavailable() async throws {
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/master.m3u8")!,
                    isAdvertisement: false
                )
            ])),
            castManager: castManager,
            qualityLoader: StubQualityLoader(options: [])
        )

        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }

        XCTAssertTrue(viewModel.manualQualityOptions.isEmpty)
        XCTAssertEqual(viewModel.qualityAvailabilityText, "Stream quality unavailable")
        viewModel.stop()
    }

    func testQualityMenuIncludesUnavailableAdvertisedResolutions() async throws {
        let deliveredOptions = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(
                width: 1_024,
                height: 576,
                averageBitRate: 1_500_000,
                peakBitRate: nil
            )
        ])
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(
                listPath: "movie",
                title: "Movie",
                quality: "1080P"
            ),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/movie.m3u8")!,
                    isAdvertisement: false
                )
            ])),
            castManager: castManager,
            qualityLoader: StubQualityLoader(options: deliveredOptions)
        )

        viewModel.start()
        try await waitUntil { viewModel.selectedQuality?.tierHeight == 576 }

        XCTAssertEqual(viewModel.qualityMenuOptions.map(\.tierHeight), [1_080, 720, 576])
        XCTAssertEqual(viewModel.qualityMenuOptions.map(\.isPlayable), [false, false, true])
        let unavailable1080 = try XCTUnwrap(viewModel.qualityMenuOptions.first)
        viewModel.setQuality(unavailable1080)
        XCTAssertTrue(viewModel.usesAutomaticQuality)
        XCTAssertEqual(viewModel.selectedQuality?.tierHeight, 576)
        viewModel.stop()
    }

    func testQualityMenuUsesResolvedAdvertisedQualityWhenItemDoesNotHaveQuality() async throws {
        let deliveredOptions = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(
                width: 1_024,
                height: 576,
                averageBitRate: 1_500_000,
                peakBitRate: nil
            )
        ])
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(
                listPath: "movie",
                title: "Movie"
            ),
            resolver: StubPlaybackResolver(playback: NativePlayback(
                entries: [
                    NativePlaybackEntry(
                        url: URL(string: "https://media.example.com/movie.m3u8")!,
                        isAdvertisement: false
                    )
                ],
                advertisedQuality: "1080P"
            )),
            qualityLoader: StubQualityLoader(options: deliveredOptions)
        )

        viewModel.start()
        try await waitUntil { viewModel.selectedQuality?.tierHeight == 576 }

        XCTAssertEqual(viewModel.advertisedQuality, "1080P")
        XCTAssertEqual(viewModel.qualityMenuOptions.map(\.tierHeight), [1_080, 720, 576])
        XCTAssertEqual(viewModel.qualityMenuOptions.map(\.isPlayable), [false, false, true])
        viewModel.stop()
    }

    func testTeLiDuXingUsesDelivered480pInsteadOfCatalog4KClaim() async throws {
        let deliveredOptions = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(
                width: 864,
                height: 362,
                averageBitRate: 1_000_000,
                peakBitRate: 1_500_000
            )
        ])
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(
                listPath: "te-li-du-xing",
                title: "特立独行",
                quality: "4K"
            ),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/te-li-du-xing.m3u8")!,
                    isAdvertisement: false
                )
            ])),
            castManager: castManager,
            qualityLoader: StubQualityLoader(options: deliveredOptions)
        )

        viewModel.start()
        try await waitUntil { viewModel.selectedQuality != nil }

        XCTAssertEqual(viewModel.item.quality, "4K")
        XCTAssertEqual(viewModel.selectedQuality?.tierHeight, 480)
        XCTAssertEqual(viewModel.selectedQuality?.width, 864)
        XCTAssertEqual(viewModel.selectedQuality?.height, 362)
        XCTAssertEqual(viewModel.qualityAvailabilityText, "480p only")
        XCTAssertTrue(viewModel.manualQualityOptions.isEmpty)
        viewModel.stop()
    }

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
            item: MyVideoItem(
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

    func testResolvedPlaybackPublishesEpisodeObservation() async throws {
        let episodes = [
            Episode(mediaKey: "episode-10", title: "10", updateDate: nil),
            Episode(mediaKey: "episode-9", title: "09", updateDate: nil)
        ]
        var observations: [[EpisodeSelection]] = []
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "series", title: "Series", isSerial: true),
            resolver: StubPlaybackResolver(playback: NativePlayback(
                entries: [NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/episode-10.m3u8")!,
                    isAdvertisement: false
                )],
                episodes: episodes,
                selectedEpisode: episodes[0]
            )),
            onEpisodesObserved: { observations.append($0) }
        )

        viewModel.start()
        try await waitUntil { observations.count == 1 }

        XCTAssertEqual(observations[0].map(\.mediaKey), ["episode-10", "episode-9"])
        viewModel.stop()
    }

    func testKnownLatestStartsBeforeIndependentEpisodeListRecoveryCompletes() async throws {
        var observations: [[EpisodeSelection]] = []
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(
                listPath: "series",
                title: "Series",
                isSerial: true,
                latestEpisodeKey: "episode-10",
                latestEpisodeTitle: "10"
            ),
            resolver: IndependentEpisodeResolver(),
            qualityLoader: StubQualityLoader(options: []),
            onEpisodesObserved: { observations.append($0) }
        )

        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }
        let preparedItem = try XCTUnwrap(viewModel.preparedPlayerItems.first)
        try await waitUntil { viewModel.episodes.count == 2 }

        XCTAssertTrue(viewModel.preparedPlayerItems.first === preparedItem)
        XCTAssertEqual(viewModel.selectedEpisode?.mediaKey, "episode-10")
        XCTAssertEqual(viewModel.episodeControlTitle, "Episode 10/10")
        XCTAssertEqual(observations.last?.map(\.mediaKey), ["episode-10", "episode-9"])
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
            item: MyVideoItem(listPath: "movie", title: "Original Title"),
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
            item: MyVideoItem(listPath: "movie", title: "Movie", isSerial: false),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: []))
        )

        XCTAssertFalse(viewModel.shouldShowEpisodeControl)
        XCTAssertNil(viewModel.episodeControlTitle)
    }

    func testPlayedEpisodeKeyRestoresEpisodeControlForLegacyItem() async throws {
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "legacy-series", title: "Legacy Series"),
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
            item: MyVideoItem(listPath: "movie", title: "Movie"),
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
            item: MyVideoItem(listPath: "media-key", title: "Movie"),
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
            item: MyVideoItem(listPath: "media-key", title: "Movie"),
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
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playback)
        )
        viewModel.start()
        try await waitUntil { viewModel.episodeTitle == "04" }

        XCTAssertEqual(viewModel.preparedEntryCount, 1)
        viewModel.stop()
    }

    func testRemovingAdvertisementPreservesExistingMuteChoice() async throws {
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
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
        let item = MyVideoItem(listPath: "series", title: "Series")
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
        let item = MyVideoItem(listPath: "series", title: "Series")
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
        let item = MyVideoItem(listPath: "series", title: "Series")
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
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            castManager: castManager
        )

        viewModel.start()
        try await waitUntil { castManager.preparedPlans.count == 1 }

        XCTAssertEqual(viewModel.player.rate, 0)
        viewModel.stop()
    }

    func testPlaybackEntryUpdatesTimelineState() async throws {
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement())
        )

        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }
        viewModel.handlePlaybackEntry(index: 0, position: 32, duration: 100, isPlaying: true)

        XCTAssertEqual(viewModel.playbackPosition, 32)
        XCTAssertEqual(viewModel.playbackDuration, 100)
        viewModel.stop()
    }

    func testLocalTransportSkipButtonsMoveProgramPositionByTenSeconds() async throws {
        let castManager = MockCastPlaybackManager()
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            castManager: castManager
        )
        attachSeekableItem(to: viewModel)

        viewModel.skipForward10Seconds()
        try await waitUntil { viewModel.player.currentTime().seconds >= 9.5 }
        viewModel.skipBackward10Seconds()
        try await waitUntil { viewModel.player.currentTime().seconds <= 0.5 }

        XCTAssertEqual(castManager.updatedPositions, [10, 0])
        viewModel.stop()
    }

    func testLocalTransportSkipButtonsAreIgnoredWhileCasting() {
        let castManager = MockCastPlaybackManager()
        castManager.isCasting = true
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            castManager: castManager
        )
        attachSeekableItem(to: viewModel)

        viewModel.skipForward10Seconds()
        viewModel.skipBackward10Seconds()

        XCTAssertTrue(castManager.updatedPositions.isEmpty)
        viewModel.stop()
    }

    func testManualSeekCancelsPendingAutoplay() async throws {
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "series", title: "Series"),
            initialEpisodeKey: "episode-3",
            resolver: EpisodeAwareStubResolver()
        )
        viewModel.start()
        try await waitUntil { viewModel.nextEpisode != nil }
        attachSeekableItem(to: viewModel)

        viewModel.handlePlaybackEntry(index: 0, position: 100, duration: 100, isPlaying: false)
        try await waitUntil { viewModel.autoplayCountdown != nil }
        viewModel.skipBackward10Seconds()

        XCTAssertNil(viewModel.autoplayCountdown)
        viewModel.stop()
    }

    func testSkipIntroOpportunityPerformsAbsoluteSeekAndOffersUndo() async throws {
        let skipStore = makeSkipStore()
        XCTAssertTrue(skipStore.save(profile: try SeriesSkipProfile(
            validatingSeriesID: "series",
            intro: SkipIntroMarker(start: nil, end: 60),
            outroStartSecondsRemaining: nil,
            confidence: 1,
            agreeingEpisodeCount: 1,
            source: .userCorrected,
            referenceDuration: 100,
            updatedAt: Date(timeIntervalSince1970: 1),
            disabled: false
        )))
        let castManager = MockCastPlaybackManager()
        let viewModel = NativePlayerViewModel(
            item: MyVideoItem(listPath: "series", title: "Series", isSerial: true),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            castManager: castManager,
            skipMarkerStore: skipStore
        )
        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }
        attachSeekableItem(to: viewModel)
        viewModel.handlePlaybackEntry(index: 0, position: 10, duration: 100, isPlaying: true)

        XCTAssertEqual(viewModel.skipOpportunity, SkipOpportunity(kind: .intro, target: 60))
        viewModel.performSkip()
        XCTAssertTrue(viewModel.canUndoSkip)
        XCTAssertEqual(castManager.updatedPositions.last, 60)

        viewModel.undoSkip()
        XCTAssertFalse(viewModel.canUndoSkip)
        XCTAssertEqual(castManager.updatedPositions.last, 10)
        viewModel.stop()
    }

    func testManualSkipCorrectionsPersistAndMoviesNeverOfferSkip() async throws {
        let skipStore = makeSkipStore()
        let series = NativePlayerViewModel(
            item: MyVideoItem(listPath: "series", title: "Series", isSerial: true),
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            skipMarkerStore: skipStore
        )
        series.start()
        try await waitUntil { series.preparedEntryCount == 1 }
        attachSeekableItem(to: series)
        series.handlePlaybackEntry(index: 0, position: 42, duration: 100, isPlaying: true)
        series.setIntroEndHere()
        XCTAssertEqual(skipStore.profile(for: "series")?.intro?.end, 42)
        series.handlePlaybackEntry(index: 0, position: 80, duration: 100, isPlaying: true)
        series.setOutroStartHere()
        XCTAssertEqual(skipStore.profile(for: "series")?.outroStartSecondsRemaining, 20)

        let movie = NativePlayerViewModel(
            item: MyVideoItem(listPath: "movie", title: "Movie", isSerial: false),
            resolver: StubPlaybackResolver(playback: NativePlayback(entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/movie.m3u8")!,
                    isAdvertisement: false
                )
            ])),
            skipMarkerStore: skipStore
        )
        movie.start()
        try await waitUntil { movie.preparedEntryCount == 1 }
        attachSeekableItem(to: movie)
        movie.handlePlaybackEntry(index: 0, position: 10, duration: 100, isPlaying: true)
        XCTAssertNil(movie.skipOpportunity)
        series.stop()
        movie.stop()
    }

    func testPreferredEpisodeInfersSerialSkipSupportWithoutProviderFlag() async throws {
        let skipStore = makeSkipStore()
        let item = MyVideoItem(listPath: "inferred-series", title: "Inferred Series", isSerial: false)
        let viewModel = NativePlayerViewModel(
            item: item,
            initialEpisodeKey: "episode-4",
            resolver: StubPlaybackResolver(playback: playbackWithAdvertisement()),
            skipMarkerStore: skipStore
        )

        viewModel.start()
        try await waitUntil { viewModel.preparedEntryCount == 1 }
        attachSeekableItem(to: viewModel)
        viewModel.handlePlaybackEntry(index: 0, position: 36, duration: 100, isPlaying: true)
        viewModel.setIntroEndHere()

        XCTAssertTrue(viewModel.supportsSkip)
        XCTAssertEqual(skipStore.profile(for: item.id)?.intro?.end, 36)
        viewModel.stop()
    }

    func testProgramWithoutAdvertisementKeepsResumePendingUntilPlayerIsReady() async throws {
        let (store, defaults, suiteName) = playedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = MyVideoItem(listPath: "movie", title: "Movie")
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
            item: MyVideoItem(listPath: "series", title: "Series"),
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

    private func attachSeekableItem(to viewModel: NativePlayerViewModel) {
        let composition = AVMutableComposition()
        composition.insertEmptyTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 60, preferredTimescale: 600))
        )
        viewModel.player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
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

    private func makeSkipStore() -> SkipMarkerStore {
        var profileData: Data?
        var fingerprintData: Data?
        return SkipMarkerStore(
            profilePersistence: SkipDataPersistence(
                load: { profileData },
                save: { profileData = $0 }
            ),
            fingerprintPersistence: SkipDataPersistence(
                load: { fingerprintData },
                save: { fingerprintData = $0 }
            )
        )
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

    func resolve(item: MyVideoItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
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

    func resolve(item: MyVideoItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        count += 1
        return playback
    }

    func resolveCount() -> Int {
        count
    }
}

private struct EpisodeAwareStubResolver: NativePlaybackResolving {
    func resolve(item: MyVideoItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
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

private struct IndependentEpisodeResolver: NativePlaybackResolving, EpisodePlaylistResolving {
    func resolve(item: MyVideoItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        NativePlayback(
            entries: [NativePlaybackEntry(
                url: URL(string: "https://media.example.com/episode-10.m3u8")!,
                isAdvertisement: false
            )],
            selectedEpisode: Episode(mediaKey: "episode-10", title: "10", updateDate: nil)
        )
    }

    func loadEpisodes(for item: MyVideoItem, expectedEpisodeKey: String?) async throws -> [Episode] {
        try await Task.sleep(for: .milliseconds(20))
        return [
            Episode(mediaKey: "episode-10", title: "10", updateDate: nil),
            Episode(mediaKey: "episode-9", title: "09", updateDate: nil)
        ]
    }
}

private struct StubQualityLoader: PlaybackQualityLoading {
    let options: [PlaybackQualityOption]

    func loadOptions(for url: URL) async throws -> [PlaybackQualityOption] {
        options
    }
}
