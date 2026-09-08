import XCTest
@testable import Aiyifan

final class ReadyToWatchProjectorTests: XCTestCase {
    func testIncompleteEpisodeWinsContinuityAndProducesOneCandidatePerSavedTitle() {
        let show = item("show")
        let updates = [update(show, episode: "04", detectedAt: 300)]
        let played = [
            record(show, episode: "02", position: 20, playedAt: 100),
            record(show, episode: "03", position: 40, playedAt: 200)
        ]

        let entries = project(saved: [show, show], updates: updates, played: played)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].item.id, show.id)
        XCTAssertEqual(entries[0].episodeKey, "03")
        XCTAssertEqual(entries[0].source, .incomplete)
        XCTAssertEqual(entries[0].resumePosition, 40)
    }

    func testCompletedEpisodeAdvancesToNewestUnseenEpisode() {
        let show = item("show")
        let completed = record(show, episode: "03", position: 90, playedAt: 200)

        let entries = project(
            saved: [show],
            updates: [update(show, episode: "04", detectedAt: 300)],
            played: [completed]
        )

        XCTAssertEqual(entries.map(\.episodeKey), ["04"])
        XCTAssertEqual(entries.map(\.source), [.newEpisode])
        XCTAssertEqual(entries.map(\.isNew), [true])
    }

    func testManualPinsUseExactEpisodeAndUserOrderBeforeAutomaticCandidates() {
        let alpha = item("alpha")
        let beta = item("beta")
        let gamma = item("gamma")
        let overrides = ReadyToWatchOverrides(
            pins: [
                ReadyPin(titleID: beta.id, episodeKey: "08", orderToken: "0001:b", modifiedAt: date(10)),
                ReadyPin(titleID: alpha.id, episodeKey: "02", orderToken: "0002:a", modifiedAt: date(20))
            ]
        )

        let entries = project(
            saved: [alpha, beta, gamma],
            updates: [update(gamma, episode: "05", detectedAt: 500)],
            played: [record(alpha, episode: "01", position: 10, playedAt: 900)],
            overrides: overrides
        )

        XCTAssertEqual(entries.map(\.item.id), [beta.id, alpha.id, gamma.id])
        XCTAssertEqual(entries.map(\.episodeKey), ["08", "02", "05"])
        XCTAssertEqual(entries.map(\.source), [.manual, .manual, .newEpisode])
    }

    func testAutomaticOrderingUsesSourceDateThenStableTitleTieBreak() {
        let updateA = item("update-a")
        let updateB = item("update-b")
        let playedA = item("played-a")
        let playedB = item("played-b")

        let entries = project(
            saved: [playedB, updateB, playedA, updateA],
            updates: [
                update(updateB, episode: "02", detectedAt: 400),
                update(updateA, episode: "03", detectedAt: 400)
            ],
            played: [
                record(playedB, episode: "07", position: 10, playedAt: 200),
                record(playedA, episode: "06", position: 10, playedAt: 200)
            ]
        )

        XCTAssertEqual(
            entries.map(\.item.id),
            [updateA.id, updateB.id, playedA.id, playedB.id]
        )
    }

    func testDismissalSuppressesOnlyTheMatchingEpisode() {
        let show = item("show")
        let overrides = ReadyToWatchOverrides(
            dismissals: [ReadyDismissal(titleID: show.id, episodeKey: "04", modifiedAt: date(10))]
        )

        XCTAssertTrue(project(
            saved: [show],
            updates: [update(show, episode: "04", detectedAt: 100)],
            overrides: overrides
        ).isEmpty)

        let next = project(
            saved: [show],
            updates: [update(show, episode: "05", detectedAt: 200)],
            overrides: overrides
        )
        XCTAssertEqual(next.map(\.episodeKey), ["05"])
    }

    func testProjectionRejectsUnsavedMalformedCompletedAndDuplicateInputs() {
        let saved = item("saved")
        let unsaved = item("unsaved")
        let malformed = AiyifanItem(listPath: "   ", title: "Malformed")
        let duplicateUpdate = update(saved, episode: "03", detectedAt: 100)

        let entries = project(
            saved: [saved, malformed],
            updates: [
                duplicateUpdate,
                duplicateUpdate,
                update(saved, episode: "   ", detectedAt: 900),
                update(unsaved, episode: "09", detectedAt: 900)
            ],
            played: [
                record(saved, episode: "02", position: .infinity, playedAt: 800),
                record(saved, episode: "01", position: 10, duration: 0, playedAt: 700),
                record(unsaved, episode: "08", position: 10, playedAt: 600)
            ]
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].item.id, saved.id)
        XCTAssertEqual(entries[0].episodeKey, "03")
    }

    func testProjectionRejectsSavedItemWhoseIdentifierNeedsNormalization() {
        let malformed = AiyifanItem(listPath: " padded ", title: "Malformed", isSerial: true)
        let overrides = ReadyToWatchOverrides(pins: [
            ReadyPin(
                titleID: "padded",
                episodeKey: "01",
                orderToken: "00000000:token",
                modifiedAt: date(10)
            )
        ])

        XCTAssertTrue(project(saved: [malformed], overrides: overrides).isEmpty)
    }

    private func project(
        saved: [AiyifanItem],
        updates: [ReadyToWatchUpdate] = [],
        played: [PlayedRecord] = [],
        overrides: ReadyToWatchOverrides = ReadyToWatchOverrides()
    ) -> [ReadyToWatchEntry] {
        ReadyToWatchProjector.project(
            savedItems: saved,
            updates: updates,
            playedRecords: played,
            overrides: overrides
        )
    }

    private func item(_ id: String) -> AiyifanItem {
        AiyifanItem(listPath: id, title: id, isSerial: true)
    }

    private func update(
        _ item: AiyifanItem,
        episode: String,
        detectedAt: TimeInterval
    ) -> ReadyToWatchUpdate {
        ReadyToWatchUpdate(
            itemID: item.id,
            episode: Episode(mediaKey: episode, title: episode, updateDate: nil),
            detectedAt: date(detectedAt)
        )
    }

    private func record(
        _ item: AiyifanItem,
        episode: String?,
        position: Double,
        duration: Double = 100,
        playedAt: TimeInterval
    ) -> PlayedRecord {
        PlayedRecord(
            item: item,
            episodeKey: episode,
            episodeTitle: episode,
            position: position,
            duration: duration,
            lastPlayedAt: date(playedAt)
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
