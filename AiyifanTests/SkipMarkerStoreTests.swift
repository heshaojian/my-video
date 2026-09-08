import XCTest
@testable import Aiyifan

@MainActor
final class SkipMarkerStoreTests: XCTestCase {
    func testProfilesAndFingerprintsRoundTripThroughSeparateVersionedPayloads() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let profile = try makeProfile(seriesID: "series-a")
        let fingerprint = try makeFingerprint(seriesID: "series-a", episodeID: "episode-1", count: 12)

        XCTAssertTrue(store.save(profile: profile))
        XCTAssertTrue(store.save(fingerprint: fingerprint))

        let restored = makeStore(persistence)
        XCTAssertEqual(restored.profile(for: "series-a"), profile)
        XCTAssertEqual(restored.fingerprints(for: "series-a"), [fingerprint])
        XCTAssertNotNil(persistence.profileData)
        XCTAssertNotNil(persistence.fingerprintData)
        XCTAssertNotEqual(persistence.profileData, persistence.fingerprintData)
    }

    func testCorruptAndFuturePayloadsRestoreAsEmptyWithSanitizedDiagnostics() throws {
        let corrupt = InMemorySkipPersistence()
        corrupt.profileData = Data("not-json".utf8)
        corrupt.fingerprintData = Data("not-json".utf8)
        let corruptStore = makeStore(corrupt)

        XCTAssertTrue(corruptStore.profiles.isEmpty)
        XCTAssertTrue(corruptStore.allFingerprints.isEmpty)
        XCTAssertEqual(corruptStore.diagnostic, .invalidStoredData)

        let future = InMemorySkipPersistence()
        future.profileData = try JSONSerialization.data(withJSONObject: [
            "version": 999,
            "profiles": []
        ])
        future.fingerprintData = try JSONSerialization.data(withJSONObject: [
            "version": 999,
            "fingerprints": []
        ])
        let futureStore = makeStore(future)

        XCTAssertTrue(futureStore.profiles.isEmpty)
        XCTAssertTrue(futureStore.allFingerprints.isEmpty)
        XCTAssertEqual(futureStore.diagnostic, .unsupportedStoredVersion)
    }

    func testInvalidRecordsAreRejectedWithoutReplacingValidState() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let valid = try makeProfile(seriesID: "valid")
        XCTAssertTrue(store.save(profile: valid))

        let invalid = SeriesSkipProfile(
            seriesID: "   ",
            intro: SkipIntroMarker(start: 80, end: 40),
            outroStartSecondsRemaining: -1,
            confidence: 9,
            agreeingEpisodeCount: -2,
            source: .learned,
            referenceDuration: .nan,
            updatedAt: Date(),
            disabled: false,
            schemaVersion: 1
        )

        XCTAssertFalse(store.save(profile: invalid))
        XCTAssertEqual(store.profiles, [valid])
        XCTAssertEqual(store.diagnostic, .invalidInput)
    }

    func testUserCorrectionWinsOverNewerLearnedAndProviderProfiles() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let corrected = try makeProfile(
            seriesID: "series",
            source: .userCorrected,
            introEnd: 61,
            updatedAt: 10,
            agreeingEpisodeCount: 1
        )
        let learned = try makeProfile(seriesID: "series", source: .learned, introEnd: 80, updatedAt: 30)
        let provider = try makeProfile(seriesID: "series", source: .provider, introEnd: 70, updatedAt: 40)

        XCTAssertTrue(store.save(profile: corrected))
        XCTAssertFalse(store.save(profile: learned))
        XCTAssertFalse(store.save(profile: provider))
        XCTAssertEqual(store.profile(for: "series")?.intro?.end, 61)
        XCTAssertEqual(store.profile(for: "series")?.source, .userCorrected)
    }

    func testEqualDateMergeIsDeterministicAndCorrectionPrecedenceIsCommutative() throws {
        let timestamp: TimeInterval = 100
        let corrected = try makeProfile(
            seriesID: "series",
            source: .userCorrected,
            introEnd: 61,
            updatedAt: timestamp,
            agreeingEpisodeCount: 1
        )
        let learned = try makeProfile(
            seriesID: "series",
            source: .learned,
            introEnd: 80,
            updatedAt: timestamp
        )

        XCTAssertEqual(
            SeriesSkipProfile.merged(local: corrected, incoming: learned),
            SeriesSkipProfile.merged(local: learned, incoming: corrected)
        )
        XCTAssertEqual(SeriesSkipProfile.merged(local: learned, incoming: corrected), corrected)
    }

    func testDisableAndResetCreateNewestOperationTombstones() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        XCTAssertTrue(store.save(profile: try makeProfile(seriesID: "series", updatedAt: 10)))
        XCTAssertTrue(store.disable(seriesID: "series", at: date(20)))

        XCTAssertEqual(store.profile(for: "series")?.disabled, true)
        XCTAssertEqual(store.tombstones, [
            SkipProfileTombstone(seriesID: "series", kind: .disable, updatedAt: date(20))
        ])

        XCTAssertTrue(store.reset(seriesID: "series", at: date(30)))
        XCTAssertNil(store.profile(for: "series"))
        XCTAssertTrue(store.fingerprints(for: "series").isEmpty)
        XCTAssertEqual(store.tombstones, [
            SkipProfileTombstone(seriesID: "series", kind: .reset, updatedAt: date(30))
        ])

        XCTAssertFalse(store.save(profile: try makeProfile(seriesID: "series", updatedAt: 25)))
        XCTAssertNil(store.profile(for: "series"))
        XCTAssertTrue(store.save(profile: try makeProfile(seriesID: "series", updatedAt: 31)))
    }

    func testDisabledProfileSurvivesRoundTrip() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        XCTAssertTrue(store.save(profile: try makeProfile(seriesID: "series", updatedAt: 10)))
        XCTAssertTrue(store.disable(seriesID: "series", at: date(20)))

        let restored = makeStore(persistence)

        XCTAssertEqual(restored.profile(for: "series")?.disabled, true)
        XCTAssertTrue(restored.isDisabled(seriesID: "series"))
    }

    func testEqualTimeCloudResetWinsRegardlessOfInputOrder() throws {
        let timestamp = date(20)
        let reset = SkipProfileTombstone(seriesID: "series", kind: .reset, updatedAt: timestamp)
        let disable = SkipProfileTombstone(seriesID: "series", kind: .disable, updatedAt: timestamp)
        let firstPersistence = InMemorySkipPersistence()
        let secondPersistence = InMemorySkipPersistence()
        let first = makeStore(firstPersistence)
        let second = makeStore(secondPersistence)

        first.mergeFromCloud(profiles: [], tombstones: [reset, disable])
        second.mergeFromCloud(profiles: [], tombstones: [disable, reset])

        XCTAssertEqual(first.tombstones, [reset])
        XCTAssertEqual(second.tombstones, [reset])
        XCTAssertFalse(first.isDisabled(seriesID: "series"))
        XCTAssertFalse(second.isDisabled(seriesID: "series"))
    }

    func testNewerCloudResetPurgesLocalFingerprintsButStaleResetDoesNot() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let fingerprint = try makeFingerprint(
            seriesID: "series",
            episodeID: "episode",
            count: 2,
            sampledAt: 20
        )
        XCTAssertTrue(store.save(fingerprint: fingerprint))

        store.mergeFromCloud(
            profiles: [],
            tombstones: [SkipProfileTombstone(
                seriesID: "series",
                kind: .reset,
                updatedAt: date(10)
            )]
        )
        XCTAssertEqual(store.fingerprints(for: "series"), [fingerprint])

        store.mergeFromCloud(
            profiles: [],
            tombstones: [SkipProfileTombstone(
                seriesID: "series",
                kind: .reset,
                updatedAt: date(30)
            )]
        )
        XCTAssertTrue(store.fingerprints(for: "series").isEmpty)
    }

    func testFingerprintsAreCappedToThreeNewestEpisodesAndFiveHundredSamples() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        for episode in 1...4 {
            let fingerprint = try makeFingerprint(
                seriesID: "series",
                episodeID: "episode-\(episode)",
                count: 520,
                sampledAt: TimeInterval(episode)
            )
            XCTAssertTrue(store.save(fingerprint: fingerprint))
        }

        let retained = store.fingerprints(for: "series")
        XCTAssertEqual(retained.map(\.episodeID), ["episode-4", "episode-3", "episode-2"])
        XCTAssertTrue(retained.allSatisfy { $0.samples.count == 500 })
        XCTAssertEqual(retained.first?.samples.first?.time, 40)
        XCTAssertEqual(retained.first?.samples.last?.time, 1_078)
    }

    func testReplacingAnEpisodeIsAtomicAndDeduplicatesSampleTimes() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let original = try makeFingerprint(seriesID: "series", episodeID: "episode", count: 3)
        let replacement = try EpisodeFingerprint(
            validatingSeriesID: "series",
            episodeID: "episode",
            duration: 1_000,
            samples: [
                PerceptualHashSample(time: 4, hash: 1),
                PerceptualHashSample(time: 2, hash: 2),
                PerceptualHashSample(time: 4, hash: 3)
            ],
            sampledAt: date(20)
        )

        XCTAssertTrue(store.save(fingerprint: original))
        XCTAssertTrue(store.save(fingerprint: replacement))

        XCTAssertEqual(store.fingerprints(for: "series").count, 1)
        XCTAssertEqual(store.fingerprints(for: "series")[0].samples, [
            PerceptualHashSample(time: 2, hash: 2),
            PerceptualHashSample(time: 4, hash: 3)
        ])
    }

    func testStaleFingerprintCannotReplaceNewerEpisodeSamples() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let newer = try makeFingerprint(
            seriesID: "series",
            episodeID: "episode",
            count: 3,
            sampledAt: 20
        )
        let stale = try makeFingerprint(
            seriesID: "series",
            episodeID: "episode",
            count: 2,
            sampledAt: 10
        )

        XCTAssertTrue(store.save(fingerprint: newer))
        XCTAssertFalse(store.save(fingerprint: stale))
        XCTAssertEqual(store.fingerprints(for: "series"), [newer])
    }

    func testStaleDisableAndResetCannotEraseNewerProfileOrFingerprints() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        let profile = try makeProfile(seriesID: "series", updatedAt: 100)
        let fingerprint = try makeFingerprint(seriesID: "series", episodeID: "episode", count: 2)
        XCTAssertTrue(store.save(profile: profile))
        XCTAssertTrue(store.save(fingerprint: fingerprint))

        XCTAssertFalse(store.disable(seriesID: "series", at: date(90)))
        XCTAssertFalse(store.reset(seriesID: "series", at: date(90)))
        XCTAssertEqual(store.profile(for: "series"), profile)
        XCTAssertEqual(store.fingerprints(for: "series"), [fingerprint])
    }

    func testResetRejectsDetectionThatStartedBeforeTheReset() throws {
        let store = makeStore(InMemorySkipPersistence())
        let detectionStartedAt = date(100)
        XCTAssertTrue(store.reset(seriesID: "series", at: date(101)))
        let staleDetection = try SeriesSkipProfile(
            validatingSeriesID: "series",
            intro: SkipIntroMarker(start: 5, end: 60),
            outroStartSecondsRemaining: nil,
            confidence: 0.9,
            agreeingEpisodeCount: 2,
            source: .learned,
            referenceDuration: 1_800,
            updatedAt: detectionStartedAt,
            disabled: false
        )

        XCTAssertFalse(store.save(profile: staleDetection))
        XCTAssertNil(store.profile(for: "series"))
    }

    func testPersistenceFailureKeepsLatestInMemoryStateAndCanRetry() throws {
        let persistence = InMemorySkipPersistence()
        persistence.failProfileWrites = true
        let store = makeStore(persistence)
        let profile = try makeProfile(seriesID: "series")

        XCTAssertTrue(store.save(profile: profile))
        XCTAssertEqual(store.profile(for: "series"), profile)
        XCTAssertTrue(store.hasPendingProfilePersistence)
        XCTAssertEqual(store.diagnostic, .writeFailed)
        XCTAssertNil(persistence.profileData)

        persistence.failProfileWrites = false
        XCTAssertTrue(store.retryPendingPersistence())
        XCTAssertFalse(store.hasPendingProfilePersistence)
        XCTAssertEqual(makeStore(persistence).profile(for: "series"), profile)
    }

    func testPersistenceContainsNoProviderOrMediaURLFields() throws {
        let persistence = InMemorySkipPersistence()
        let store = makeStore(persistence)
        XCTAssertTrue(store.save(profile: try makeProfile(seriesID: "series")))
        XCTAssertTrue(store.save(fingerprint: try makeFingerprint(seriesID: "series", episodeID: "episode", count: 2)))

        let persisted = String(data: persistence.profileData! + persistence.fingerprintData!, encoding: .utf8)!
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("url"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("providerResponse"))
    }

    private func makeStore(_ persistence: InMemorySkipPersistence) -> SkipMarkerStore {
        SkipMarkerStore(
            profilePersistence: persistence.profileAdapter,
            fingerprintPersistence: persistence.fingerprintAdapter
        )
    }

    private func makeProfile(
        seriesID: String,
        source: SkipMarkerSource = .learned,
        introEnd: Double = 60,
        updatedAt: TimeInterval = 100,
        agreeingEpisodeCount: Int = 2
    ) throws -> SeriesSkipProfile {
        try SeriesSkipProfile(
            validatingSeriesID: seriesID,
            intro: SkipIntroMarker(start: source == .userCorrected ? nil : 10, end: introEnd),
            outroStartSecondsRemaining: 45,
            confidence: source == .userCorrected ? 1 : 0.9,
            agreeingEpisodeCount: agreeingEpisodeCount,
            source: source,
            referenceDuration: 1_000,
            updatedAt: date(updatedAt),
            disabled: false
        )
    }

    private func makeFingerprint(
        seriesID: String,
        episodeID: String,
        count: Int,
        sampledAt: TimeInterval = 10
    ) throws -> EpisodeFingerprint {
        try EpisodeFingerprint(
            validatingSeriesID: seriesID,
            episodeID: episodeID,
            duration: 1_200,
            samples: (0..<count).map {
                PerceptualHashSample(time: Double($0 * 2) + sampledAt * 10, hash: UInt64($0))
            },
            sampledAt: date(sampledAt)
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}

private final class InMemorySkipPersistence {
    enum Failure: Error {
        case write
    }

    var profileData: Data?
    var fingerprintData: Data?
    var failProfileWrites = false
    var failFingerprintWrites = false

    var profileAdapter: SkipDataPersistence {
        SkipDataPersistence(
            load: { [weak self] in self?.profileData },
            save: { [weak self] data in
                guard let self else { return }
                if self.failProfileWrites { throw Failure.write }
                self.profileData = data
            }
        )
    }

    var fingerprintAdapter: SkipDataPersistence {
        SkipDataPersistence(
            load: { [weak self] in self?.fingerprintData },
            save: { [weak self] data in
                guard let self else { return }
                if self.failFingerprintWrites { throw Failure.write }
                self.fingerprintData = data
            }
        )
    }
}
