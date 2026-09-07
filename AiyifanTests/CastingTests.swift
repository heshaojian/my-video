import XCTest
@testable import Aiyifan

final class CastingTests: XCTestCase {
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

    func testPlanPreservesAdvertisementBeforeProgramAndResumesOnlyProgram() throws {
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(url: URL(string: "https://ads.example.com/front.mp4")!, isAdvertisement: true),
            NativePlaybackEntry(url: URL(string: "https://media.example.com/full.m3u8")!, isAdvertisement: false)
        ])

        let plan = try CastPlaybackPlanBuilder.make(
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            playback: playback,
            programPosition: 42
        )

        XCTAssertEqual(plan.entries.map(\.url), playback.entries.map(\.url))
        XCTAssertEqual(plan.entries.map(\.isAdvertisement), [true, false])
        XCTAssertEqual(plan.entries.map(\.startPosition), [0, 42])
    }

    func testPlanIncludesEpisodeAndArtworkMetadata() throws {
        let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
        let item = AiyifanItem(
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
            item: AiyifanItem(listPath: "movie", title: "Movie"),
            playback: playback,
            programPosition: 0
        ))
    }
}
