import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import XCTest
@testable import Aiyifan

@MainActor
final class PlaybackFeaturesTests: XCTestCase {
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
