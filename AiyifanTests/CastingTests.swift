import XCTest
@testable import Aiyifan

final class CastingTests: XCTestCase {
    func testSessionSnapshotClampsInvalidProgressValues() {
        let negative = CastSessionSnapshot(
            phase: .paused,
            receiverName: "Living Room TV",
            title: "Series",
            position: -20,
            duration: 100
        )
        let beyondEnd = CastSessionSnapshot(
            phase: .playing,
            receiverName: "Living Room TV",
            title: "Series",
            position: 120,
            duration: 100
        )
        let nonFinite = CastSessionSnapshot(
            phase: .loading,
            receiverName: "Living Room TV",
            title: "Series",
            position: .infinity,
            duration: .nan
        )

        XCTAssertEqual(negative.position, 0)
        XCTAssertEqual(negative.progress, 0)
        XCTAssertEqual(beyondEnd.position, 100)
        XCTAssertEqual(beyondEnd.progress, 1)
        XCTAssertEqual(nonFinite.position, 0)
        XCTAssertEqual(nonFinite.duration, 0)
        XCTAssertEqual(nonFinite.progress, 0)
    }

    func testSessionSnapshotExposesPlaybackAndErrorState() {
        let playing = CastSessionSnapshot(
            phase: .playing,
            receiverName: "Bedroom TV",
            title: "Movie",
            position: 30,
            duration: 120
        )
        let failed = CastSessionSnapshot(
            phase: .failed,
            receiverName: "Bedroom TV",
            title: "Movie",
            errorMessage: "Receiver unavailable"
        )

        XCTAssertTrue(playing.isPlaying)
        XCTAssertFalse(playing.hasError)
        XCTAssertFalse(failed.isPlaying)
        XCTAssertTrue(failed.hasError)
    }

    func testMuteStateMutesAdvertisementsAndRestoresPreviousSetting() {
        let mutedForAdvertisement = CastMuteState().transition(
            isAdvertisement: true,
            receiverIsMuted: false
        )
        XCTAssertEqual(mutedForAdvertisement.desiredMute, true)
        XCTAssertEqual(mutedForAdvertisement.previousMute, false)

        let restoredForProgram = mutedForAdvertisement.transition(
            isAdvertisement: false,
            receiverIsMuted: true
        )
        XCTAssertEqual(restoredForProgram.desiredMute, false)
        XCTAssertNil(restoredForProgram.previousMute)
    }

    func testMuteStatePreservesAnAlreadyMutedReceiver() {
        let mutedForAdvertisement = CastMuteState().transition(
            isAdvertisement: true,
            receiverIsMuted: true
        )
        let restoredForProgram = mutedForAdvertisement.transition(
            isAdvertisement: false,
            receiverIsMuted: true
        )

        XCTAssertEqual(restoredForProgram.desiredMute, true)
        XCTAssertNil(restoredForProgram.previousMute)
    }

    func testPlanDiscardsAdvertisementAndResumesOnlyProgram() throws {
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(url: URL(string: "https://ads.example.com/front.mp4")!, isAdvertisement: true),
            NativePlaybackEntry(url: URL(string: "https://media.example.com/full.m3u8")!, isAdvertisement: false)
        ])

        let plan = try CastPlaybackPlanBuilder.make(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            playback: playback,
            programPosition: 42
        )

        XCTAssertEqual(plan.entries.map(\.url.absoluteString), ["https://media.example.com/full.m3u8"])
        XCTAssertEqual(plan.entries.map(\.isAdvertisement), [false])
        XCTAssertEqual(plan.entries.map(\.startPosition), [42])
    }

    func testPlanIncludesEpisodeAndArtworkMetadata() throws {
        let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
        let item = MyVideoItem(
            listPath: "series",
            title: "Series",
            verticalImg: "https://images.example.com/poster.jpg"
        )
        let playback = NativePlayback(
            entries: [NativePlaybackEntry(
                url: URL(string: "https://media.example.com/episode.m3u8")!,
                isAdvertisement: false
            )],
            episodes: [episode],
            selectedEpisode: episode
        )

        let plan = try CastPlaybackPlanBuilder.make(item: item, playback: playback, programPosition: 0)

        XCTAssertEqual(plan.title, "Series")
        XCTAssertEqual(plan.subtitle, "Episode 04")
        XCTAssertEqual(plan.artworkURL, item.thumbnailURL)
        XCTAssertEqual(plan.entries[0].contentType, "application/x-mpegURL")
    }

    func testPlanRejectsPlaybackWithoutProgram() {
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(url: URL(string: "https://ads.example.com/front.mp4")!, isAdvertisement: true)
        ])

        XCTAssertThrowsError(try CastPlaybackPlanBuilder.make(
            item: MyVideoItem(listPath: "movie", title: "Movie"),
            playback: playback,
            programPosition: 0
        ))
    }
}
