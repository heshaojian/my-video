import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import XCTest
@testable import Aiyifan

@MainActor
final class PlaybackFeaturesTests: XCTestCase {
    func testPlaybackQualityProjectionRejectsMalformedVariantsAndDeduplicatesHeights() {
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 3_840, height: 2_160, averageBitRate: 12_000_000, peakBitRate: 16_000_000),
            PlaybackVariantDescriptor(width: 1_920, height: 1_080, averageBitRate: 5_000_000, peakBitRate: 7_000_000),
            PlaybackVariantDescriptor(width: 1_920, height: 1_080, averageBitRate: 6_000_000, peakBitRate: 8_000_000),
            PlaybackVariantDescriptor(width: 1_280, height: 720, averageBitRate: 3_000_000, peakBitRate: 4_000_000),
            PlaybackVariantDescriptor(width: 0, height: 720, averageBitRate: 1_000_000, peakBitRate: 2_000_000),
            PlaybackVariantDescriptor(width: 640, height: -1, averageBitRate: 1_000_000, peakBitRate: 2_000_000),
            PlaybackVariantDescriptor(width: 640, height: 360, averageBitRate: .nan, peakBitRate: 2_000_000)
        ])

        XCTAssertEqual(options.map(\.height), [2_160, 1_080, 720])
        XCTAssertEqual(options.map(\.title), ["2160p", "1080p", "720p"])
        XCTAssertEqual(options.first(where: { $0.height == 1_080 })?.peakBitRate, 8_000_000)
    }

    func testCinematicDimensionsUseBothAxesForTruthfulQualityTiers() {
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 3_840, height: 1_608, averageBitRate: 12_000_000, peakBitRate: 16_000_000),
            PlaybackVariantDescriptor(width: 1_920, height: 804, averageBitRate: 5_000_000, peakBitRate: 7_000_000),
            PlaybackVariantDescriptor(width: 1_280, height: 536, averageBitRate: 3_000_000, peakBitRate: 4_000_000),
            PlaybackVariantDescriptor(width: 864, height: 362, averageBitRate: 1_000_000, peakBitRate: 1_500_000)
        ])

        XCTAssertEqual(options.map(\.tierHeight), [2_160, 1_080, 720, 480])
        XCTAssertEqual(options.map(\.title), ["2160p", "1080p", "720p", "480p"])
        XCTAssertEqual(options.map(\.width), [3_840, 1_920, 1_280, 864])
        XCTAssertEqual(options.map(\.height), [1_608, 804, 536, 362])
        XCTAssertEqual(options.last?.averageBitRate, 1_000_000)
        XCTAssertEqual(options.last?.peakBitRate, 1_500_000)
    }

    func testQualityProjectionRejectsExtremeAspectRatios() {
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 3_840, height: 1, averageBitRate: 1_000_000, peakBitRate: nil),
            PlaybackVariantDescriptor(width: 8_192, height: 144, averageBitRate: 1_000_000, peakBitRate: nil)
        ])

        XCTAssertTrue(options.isEmpty)
    }

    func testPlaybackQualityProjectionKeepsProvider576Tier() {
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 1_024, height: 576, averageBitRate: 1_500_000, peakBitRate: nil)
        ])

        XCTAssertEqual(options.map(\.tierHeight), [576])
        XCTAssertEqual(options.first?.title, "576p")
    }

    func testPlaybackQualityProjectionPreserves1440AndNormalizesOnlyRecognizedProviderTiers() {
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 2_560, height: 1_440, averageBitRate: 8_000_000, peakBitRate: nil)
        ])

        XCTAssertEqual(options.map(\.tierHeight), [1_440])
        XCTAssertEqual(PlaybackQualityProjector.normalizedTier(from: 144), 144)
        XCTAssertEqual(PlaybackQualityProjector.normalizedTier(from: 1_440), 1_440)
        XCTAssertEqual(PlaybackQualityProjector.normalizedTier(from: 2_160), 2_160)
        XCTAssertNil(PlaybackQualityProjector.normalizedTier(from: 2_000))
    }

    func testQualityMenuUnionsRealAdaptiveAndProviderSourcesByTier() throws {
        let adaptiveOptions = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 3_840, height: 2_160, averageBitRate: 12_000_000, peakBitRate: nil),
            PlaybackVariantDescriptor(width: 1_920, height: 1_080, averageBitRate: 5_000_000, peakBitRate: nil)
        ])
        let provider1080URL = URL(string: "https://media.example.com/1080.m3u8")!
        let providerSources = [
            ProviderPlaybackSource(url: URL(string: "https://media.example.com/1440.m3u8")!, tierHeight: 1_440),
            ProviderPlaybackSource(url: provider1080URL, tierHeight: 1_080),
            ProviderPlaybackSource(url: URL(string: "https://media.example.com/720.m3u8")!, tierHeight: 720)
        ]

        let menuOptions = PlaybackQualityMenuProjector.options(
            adaptiveOptions: adaptiveOptions,
            providerSources: providerSources
        )

        XCTAssertEqual(menuOptions.map(\.tierHeight), [2_160, 1_440, 1_080, 720])
        XCTAssertTrue(menuOptions.allSatisfy(\.isSelectable))
        let shared1080 = try XCTUnwrap(menuOptions.first { $0.tierHeight == 1_080 })
        XCTAssertEqual(shared1080.adaptiveOption?.tierHeight, 1_080)
        XCTAssertEqual(shared1080.providerSource?.url, provider1080URL)
    }

    func testQualityMenuDoesNotCreateCatalogOnlyChoices() {
        let menuOptions = PlaybackQualityMenuProjector.options(
            adaptiveOptions: [],
            providerSources: []
        )

        XCTAssertTrue(menuOptions.isEmpty)
    }

    func testVariantDiscoveryWinsAndPlayableVideoTrackProvidesSingleRenditionFallback() {
        let variant = PlaybackVariantDescriptor(
            width: 1_920,
            height: 804,
            averageBitRate: 5_000_000,
            peakBitRate: 7_000_000
        )
        let fallbackTracks = [
            PlaybackTrackDescriptor(
                width: 3_840,
                height: 1_608,
                estimatedBitRate: 12_000_000,
                isPlayable: true
            ),
            PlaybackTrackDescriptor(
                width: 864,
                height: 362,
                estimatedBitRate: 1_000_000,
                isPlayable: false
            )
        ]

        let variantOptions = PlaybackQualityProjector.options(
            from: [variant],
            fallbackTracks: fallbackTracks
        )
        let fallbackOptions = PlaybackQualityProjector.options(
            from: [],
            fallbackTracks: fallbackTracks
        )

        XCTAssertEqual(variantOptions.map(\.tierHeight), [1_080])
        XCTAssertEqual(variantOptions.first?.height, 804)
        XCTAssertEqual(fallbackOptions.map(\.tierHeight), [2_160])
        XCTAssertEqual(fallbackOptions.first?.height, 1_608)
        XCTAssertEqual(fallbackOptions.first?.averageBitRate, 12_000_000)
    }

    func testPlaybackQualitySelectionDefaultsToExact1080AndFallsBackPredictably() throws {
        let options = PlaybackQualityProjector.options(from: [
            PlaybackVariantDescriptor(width: 3_840, height: 2_160, averageBitRate: 12_000_000, peakBitRate: 16_000_000),
            PlaybackVariantDescriptor(width: 1_920, height: 1_080, averageBitRate: 5_000_000, peakBitRate: 7_000_000),
            PlaybackVariantDescriptor(width: 1_280, height: 720, averageBitRate: 3_000_000, peakBitRate: 4_000_000)
        ])

        XCTAssertEqual(PlaybackQualitySelector.select(from: options, targetHeight: 1_080)?.tierHeight, 1_080)
        XCTAssertEqual(PlaybackQualitySelector.select(from: options, targetHeight: 900)?.tierHeight, 720)
        XCTAssertEqual(PlaybackQualitySelector.select(from: options, targetHeight: 480)?.tierHeight, 2_160)

        let without1080 = options.filter { $0.height != 1_080 }
        XCTAssertEqual(
            PlaybackQualitySelector.select(
                from: without1080,
                targetHeight: 1_080,
                fallbackToHighest: true
            )?.tierHeight,
            2_160
        )
    }

    func testPlaybackQualityPreferenceDefaultsTo1080PersistsAndRecoversFromCorruption() {
        let suite = "PlaybackQualityPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality")
        XCTAssertEqual(store.targetHeight, 1_080)
        XCTAssertFalse(store.hasManualSelection)

        store.setTargetHeight(720)
        XCTAssertEqual(PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality").targetHeight, 720)
        XCTAssertTrue(PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality").hasManualSelection)

        store.setAutomatic()
        XCTAssertEqual(PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality").targetHeight, 1_080)
        XCTAssertFalse(PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality").hasManualSelection)

        defaults.set(-4, forKey: "quality")
        XCTAssertEqual(PlaybackQualityPreferenceStore(defaults: defaults, storageKey: "quality").targetHeight, 1_080)
    }

    func testPlaybackPreferencesPersistRateAndAutoplay() {
        let suite = "PlaybackFeaturesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = PlaybackPreferencesStore(defaults: defaults)
        preferences.setPlaybackRate(1.5)
        preferences.setAutoplayNext(false)

        let restored = PlaybackPreferencesStore(defaults: defaults)
        XCTAssertEqual(restored.playbackRate, 1.5)
        XCTAssertFalse(restored.autoplayNext)
    }

    func testPlaybackPreferencesRejectUnsupportedRates() {
        let preferences = PlaybackPreferencesStore(defaults: UserDefaults())
        let originalRate = preferences.playbackRate

        preferences.setPlaybackRate(3)

        XCTAssertEqual(preferences.playbackRate, originalRate)
    }

    func testSleepTimerExpiresAndEndOfEpisodeWaitsForCompletion() {
        let start = Date(timeIntervalSince1970: 1_000)
        let timed = SleepTimerState.starting(.minutes(15), now: start)
        XCTAssertFalse(timed.shouldPause(now: start.addingTimeInterval(899), programCompleted: false))
        XCTAssertTrue(timed.shouldPause(now: start.addingTimeInterval(900), programCompleted: false))

        let endOfEpisode = SleepTimerState.starting(.endOfEpisode, now: start)
        XCTAssertFalse(endOfEpisode.shouldPause(now: start.addingTimeInterval(9_000), programCompleted: false))
        XCTAssertTrue(endOfEpisode.shouldPause(now: start.addingTimeInterval(9_000), programCompleted: true))
    }

    func testSleepTimerRemainingLabelIsStable() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = SleepTimerState.starting(.minutes(30), now: start)

        XCTAssertEqual(state.remainingLabel(now: start.addingTimeInterval(61)), "28:59")
        XCTAssertEqual(SleepTimerState.off.remainingLabel(now: start), nil)
    }

    func testNowPlayingSnapshotUsesProgramMetadata() {
        let item = AiyifanItem(
            listPath: "series",
            title: "City Lights",
            image: "https://images.example.com/poster.jpg"
        )
        let snapshot = NowPlayingSnapshot(
            item: item,
            episodeTitle: "12",
            duration: 1_800,
            elapsed: 90,
            playbackRate: 1.25,
            isPlaying: true
        )

        XCTAssertEqual(snapshot.title, "City Lights")
        XCTAssertEqual(snapshot.subtitle, "Episode 12")
        XCTAssertEqual(snapshot.duration, 1_800)
        XCTAssertEqual(snapshot.elapsed, 90)
        XCTAssertEqual(snapshot.rate, 1.25)
        XCTAssertEqual(snapshot.artworkURL, item.thumbnailURL)
    }

    func testBackgroundAudioConfigurationUsesPlaybackMovieMode() {
        let configuration = PlaybackAudioSessionConfiguration.standard

        XCTAssertEqual(configuration.category, .playback)
        XCTAssertEqual(configuration.mode, .moviePlayback)
        XCTAssertTrue(configuration.options.isEmpty)
    }

    func testInterruptionStateResumesOnlyPreviouslyPlayingProgram() {
        var state = PlaybackInterruptionState()

        state.begin(wasPlaying: true, playbackRate: 1.25)
        XCTAssertEqual(state.end(systemSuggestsResume: true), .resume(rate: 1.25))
        XCTAssertEqual(state.end(systemSuggestsResume: true), .none)

        state.begin(wasPlaying: false, playbackRate: 1.5)
        XCTAssertEqual(state.end(systemSuggestsResume: true), .none)

        state.begin(wasPlaying: true, playbackRate: 2)
        XCTAssertEqual(state.end(systemSuggestsResume: false), .none)
    }

    func testNowPlayingMetadataIncludesLockScreenPlaybackFields() {
        let item = AiyifanItem(listPath: "series", title: "City Lights")
        let snapshot = NowPlayingSnapshot(
            item: item,
            episodeTitle: "12",
            duration: 1_800,
            elapsed: 90,
            playbackRate: 1.25,
            isPlaying: true
        )

        let metadata = NowPlayingMetadataBuilder.values(for: snapshot)

        XCTAssertEqual(metadata[MPMediaItemPropertyTitle] as? String, "City Lights")
        XCTAssertEqual(metadata[MPMediaItemPropertyAlbumTitle] as? String, "Episode 12")
        XCTAssertEqual(metadata[MPMediaItemPropertyPlaybackDuration] as? Double, 1_800)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 90)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyPlaybackRate] as? Float, 1.25)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyMediaType] as? UInt, MPNowPlayingInfoMediaType.video.rawValue)
    }

    func testBundledBrandArtworkIsAvailableForLockScreenAndLaunch() {
        XCTAssertNotNil(UIImage(named: "BrandMark"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreenBrandImage") as? String, "BrandMark")
    }

    func testLockScreenArtworkCanRenderOnMediaPlayersBackgroundQueue() async throws {
        let image = try XCTUnwrap(UIImage(named: "BrandMark"))
        let artwork = try XCTUnwrap(NowPlayingArtworkBuilder.make(from: image))
        let sendableArtwork = UncheckedSendableArtwork(artwork)

        let rendered = await Task.detached {
            sendableArtwork.value.image(at: CGSize(width: 180, height: 180)) != nil
        }.value

        XCTAssertTrue(rendered)
    }

    func testRecoveryPolicyRetriesOnlyTransientFailuresOnce() {
        XCTAssertTrue(PlaybackRecoveryPolicy.shouldRetry(error: URLError(.timedOut), attempt: 0))
        XCTAssertFalse(PlaybackRecoveryPolicy.shouldRetry(error: URLError(.timedOut), attempt: 1))
        XCTAssertFalse(PlaybackRecoveryPolicy.shouldRetry(error: NativePlaybackError.loginRequired, attempt: 0))
        XCTAssertFalse(PlaybackRecoveryPolicy.shouldRetry(error: NativePlaybackError.previewOnly, attempt: 0))
    }
}

private struct UncheckedSendableArtwork: @unchecked Sendable {
    let value: MPMediaItemArtwork

    init(_ value: MPMediaItemArtwork) {
        self.value = value
    }
}
