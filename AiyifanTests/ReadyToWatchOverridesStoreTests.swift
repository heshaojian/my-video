import XCTest
@testable import Aiyifan

@MainActor
final class ReadyToWatchOverridesStoreTests: XCTestCase {
    func testVersionedRoundTripPersistsPinsDismissalsAndTombstones() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(defaults: defaults)

        store.pin(titleID: "alpha", episodeKey: "02", at: date(10))
        store.dismiss(titleID: "beta", episodeKey: "04", at: date(20))
        store.unpin(titleID: "removed", at: date(30))

        let restored = makeStore(defaults: defaults)

        XCTAssertEqual(restored.overrides, store.overrides)
        XCTAssertFalse(restored.hasPendingPersistence)
        XCTAssertNil(restored.persistenceErrorMessage)
    }

    func testCorruptAndFutureEnvelopesRestoreAsEmpty() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not-json".utf8), forKey: ReadyToWatchOverridesStore.storageKey)
        XCTAssertEqual(makeStore(defaults: defaults).overrides, ReadyToWatchOverrides())

        let future: [String: Any] = ["version": 999, "overrides": ["pins": []]]
        defaults.set(
            try JSONSerialization.data(withJSONObject: future),
            forKey: ReadyToWatchOverridesStore.storageKey
        )
        XCTAssertEqual(makeStore(defaults: defaults).overrides, ReadyToWatchOverrides())
    }

    func testPinIsIdempotentAndReorderIsStable() {
        let store = makeStore(tokens: ["a", "b", "c"])

        store.pin(titleID: "alpha", episodeKey: "01", at: date(10))
        let original = store.overrides
        store.pin(titleID: "alpha", episodeKey: "01", at: date(20))
        XCTAssertEqual(store.overrides, original)

        store.pin(titleID: "beta", episodeKey: "02", at: date(30))
        store.pin(titleID: "gamma", episodeKey: "03", at: date(40))
        store.reorder(titleIDs: ["gamma", "alpha", "gamma"], at: date(50))

        XCTAssertEqual(store.overrides.pins.map(\.titleID), ["gamma", "alpha", "beta"])
        XCTAssertEqual(Set(store.overrides.pins.map(\.orderToken)).count, 3)
    }

    func testUnpinCreatesTombstoneAndAllowsAutomaticProjection() {
        let store = makeStore()
        let show = AiyifanItem(listPath: "show", title: "Show", isSerial: true)
        store.pin(titleID: show.id, episodeKey: "03", at: date(10))

        store.unpin(titleID: show.id, at: date(20))

        XCTAssertTrue(store.overrides.pins.isEmpty)
        XCTAssertEqual(store.overrides.tombstones.count, 1)
        XCTAssertEqual(store.overrides.tombstones[0].kind, .pin)
        let projected = ReadyToWatchProjector.project(
            savedItems: [show],
            updates: [ReadyToWatchUpdate(
                itemID: show.id,
                episode: Episode(mediaKey: "04", title: "04", updateDate: nil),
                detectedAt: date(30)
            )],
            playedRecords: [],
            overrides: store.overrides
        )
        XCTAssertEqual(projected.map(\.episodeKey), ["04"])
        XCTAssertEqual(projected.map(\.source), [.newEpisode])
    }

    func testDismissAndPruneRemoveUnsavedIntentWithTombstones() {
        let store = makeStore(tokens: ["a", "b"])
        store.pin(titleID: "keep", episodeKey: "01", at: date(10))
        store.pin(titleID: "remove", episodeKey: "02", at: date(20))
        store.dismiss(titleID: "remove", episodeKey: "03", at: date(30))

        store.prune(savedTitleIDs: ["keep"], at: date(40))

        XCTAssertEqual(store.overrides.pins.map(\.titleID), ["keep"])
        XCTAssertTrue(store.overrides.dismissals.isEmpty)
        XCTAssertEqual(
            Set(store.overrides.tombstones.filter { $0.titleID == "remove" }.map(\.kind)),
            [.pin, .dismissal]
        )
    }

    func testFailedPersistenceKeepsMemoryAndRetryWritesLatestState() throws {
        let persistence = FailingPersistence()
        persistence.shouldFail = true
        let store = ReadyToWatchOverridesStore(
            persistence: persistence.adapter,
            tokenGenerator: { "token" }
        )

        store.pin(titleID: "show", episodeKey: "07", at: date(10))

        XCTAssertEqual(store.overrides.pins.map(\.titleID), ["show"])
        XCTAssertTrue(store.hasPendingPersistence)
        XCTAssertNotNil(store.persistenceErrorMessage)
        XCTAssertNil(persistence.data)

        persistence.shouldFail = false
        XCTAssertTrue(store.retryPersistence())
        XCTAssertFalse(store.hasPendingPersistence)
        XCTAssertNil(store.persistenceErrorMessage)
        XCTAssertNotNil(persistence.data)

        let restored = ReadyToWatchOverridesStore(
            persistence: persistence.adapter,
            tokenGenerator: { "unused" }
        )
        XCTAssertEqual(restored.overrides, store.overrides)
    }

    func testMergeUsesNewestOperationStableEqualTimeTieAndTombstones() {
        let timestamp = date(100)
        let left = ReadyToWatchOverrides(
            pins: [ReadyPin(
                titleID: "same",
                episodeKey: "01",
                orderToken: "0001:a",
                modifiedAt: timestamp
            )]
        )
        let right = ReadyToWatchOverrides(
            pins: [
                ReadyPin(
                    titleID: "same",
                    episodeKey: "02",
                    orderToken: "0001:z",
                    modifiedAt: timestamp
                ),
                ReadyPin(
                    titleID: "removed",
                    episodeKey: "03",
                    orderToken: "0002:x",
                    modifiedAt: date(50)
                )
            ],
            tombstones: [ReadyOverrideTombstone(
                kind: .pin,
                titleID: "removed",
                episodeKey: nil,
                modifiedAt: date(60)
            )]
        )

        let leftThenRight = left.merging(right)
        let rightThenLeft = right.merging(left)

        XCTAssertEqual(leftThenRight, rightThenLeft)
        XCTAssertEqual(leftThenRight.pins.map(\.titleID), ["same"])
        XCTAssertEqual(leftThenRight.pins.first?.episodeKey, "02")
        XCTAssertEqual(leftThenRight.tombstones.map(\.titleID), ["removed"])
    }

    func testHundredEntryFixtureRoundTripsWithoutDuplicates() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(defaults: defaults)

        for index in 0..<100 {
            store.pin(
                titleID: "title-\(index)",
                episodeKey: "episode-\(index)",
                at: date(TimeInterval(index))
            )
        }

        let restored = makeStore(defaults: defaults)
        XCTAssertEqual(restored.overrides.pins.count, 100)
        XCTAssertEqual(Set(restored.overrides.pins.map(\.titleID)).count, 100)
        XCTAssertEqual(restored.overrides.pins, store.overrides.pins)
    }

    func testMergeRejectsPoisonedOrderTokensAndStillAllowsLocalPin() {
        let store = makeStore(tokens: ["local-token"])
        let invalidPins = [
            ReadyPin(
                titleID: "overflow",
                episodeKey: "01",
                orderToken: "9223372036854775807:bad",
                modifiedAt: date(10)
            ),
            ReadyPin(
                titleID: "malformed",
                episodeKey: "02",
                orderToken: "not-a-rank",
                modifiedAt: date(20)
            ),
            ReadyPin(
                titleID: "oversized",
                episodeKey: "03",
                orderToken: "00000001:\(String(repeating: "x", count: 129))",
                modifiedAt: date(30)
            )
        ]

        store.merge(ReadyToWatchOverrides(pins: invalidPins))
        store.pin(titleID: "local", episodeKey: "04", at: date(40))

        XCTAssertEqual(store.overrides.pins.map(\.titleID), ["local"])
        XCTAssertEqual(store.overrides.pins.first?.orderToken, "00000000:local-token")
    }

    private func makeStore(
        defaults: UserDefaults? = nil,
        tokens: [String] = (0..<120).map { "token-\($0)" }
    ) -> ReadyToWatchOverridesStore {
        let defaults = defaults ?? isolatedDefaults().0
        var iterator = tokens.makeIterator()
        return ReadyToWatchOverridesStore(
            defaults: defaults,
            tokenGenerator: { iterator.next() ?? UUID().uuidString }
        )
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "ReadyToWatchOverridesStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}

private final class FailingPersistence {
    enum Failure: Error {
        case write
    }

    var data: Data?
    var shouldFail = false

    var adapter: ReadyToWatchOverridesPersistence {
        ReadyToWatchOverridesPersistence(
            load: { [weak self] in self?.data },
            save: { [weak self] data in
                guard let self else { return }
                if self.shouldFail {
                    throw Failure.write
                }
                self.data = data
            }
        )
    }
}
