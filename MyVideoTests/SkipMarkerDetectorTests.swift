import XCTest
@testable import MyVideo

final class SkipMarkerDetectorTests: XCTestCase {
    func testDetectsAlignedIntroAndOutroAcrossTwoEpisodes() throws {
        let episodes = [
            try fingerprint(id: "e1", duration: 1_200, intro: 10...50, outroRemaining: 20...60),
            try fingerprint(id: "e2", duration: 1_230, intro: 14...54, outroRemaining: 24...64)
        ]

        let profile = try XCTUnwrap(SkipMarkerDetector().detect(
            seriesID: "series",
            fingerprints: episodes,
            detectedAt: date(100)
        ))

        XCTAssertEqual(profile.seriesID, "series")
        XCTAssertEqual(profile.source, .learned)
        XCTAssertEqual(profile.agreeingEpisodeCount, 2)
        XCTAssertGreaterThanOrEqual(profile.confidence, 0.85)
        XCTAssertEqual(profile.intro?.start ?? -1, 12, accuracy: 2.1)
        XCTAssertEqual(profile.intro?.end ?? -1, 54, accuracy: 2.1)
        XCTAssertEqual(profile.outroStartSecondsRemaining ?? -1, 62, accuracy: 2.1)
        XCTAssertEqual(profile.referenceDuration ?? -1, 1_215, accuracy: 0.1)
    }

    func testRequiresTwoDistinctEpisodesAndThirtySecondSequence() throws {
        let oneEpisode = try fingerprint(id: "e1", intro: 10...60)
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: [oneEpisode]))

        let short = [
            try fingerprint(id: "e1", intro: 10...38),
            try fingerprint(id: "e2", intro: 10...38)
        ]
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: short))
    }

    func testHonorsEightyFivePercentRatioAndTenBitDistanceBoundary() throws {
        let first = try fingerprint(id: "e1", intro: 10...50)
        var matchingSamples = try fingerprint(id: "e2", intro: 10...50).samples
        let introIndices = matchingSamples.indices.filter { (10...50).contains(Int(matchingSamples[$0].time)) }
        matchingSamples[introIndices[0]] = PerceptualHashSample(
            time: matchingSamples[introIndices[0]].time,
            hash: matchingSamples[introIndices[0]].hash ^ 0b11_1111_1111
        )
        for index in [introIndices[2], introIndices[7], introIndices[12]] {
            matchingSamples[index] = PerceptualHashSample(
                time: matchingSamples[index].time,
                hash: UInt64.max
            )
        }
        let boundary = try replacing(try fingerprint(id: "e2", intro: 10...50), samples: matchingSamples)

        let accepted = SkipMarkerDetector().detect(seriesID: "series", fingerprints: [first, boundary])
        XCTAssertNotNil(accepted?.intro)

        var rejectedSamples = matchingSamples
        rejectedSamples[introIndices[17]] = PerceptualHashSample(
            time: rejectedSamples[introIndices[17]].time,
            hash: UInt64.max
        )
        let rejected = try replacing(boundary, samples: rejectedSamples)
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: [first, rejected]))
    }

    func testRejectsTimingDisagreementBeyondTenSecondsAndSamplesOutsideWindows() throws {
        let shifted = [
            try fingerprint(id: "e1", intro: 10...50, outroRemaining: 20...60),
            try fingerprint(id: "e2", intro: 22...62, outroRemaining: 32...72)
        ]
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: shifted))

        let outside = [
            try fingerprint(id: "e1", intro: 500...540, outroRemaining: 370...410),
            try fingerprint(id: "e2", intro: 500...540, outroRemaining: 370...410)
        ]
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: outside))
    }

    func testDurationOutlierAndInvalidFingerprintsCannotPublishMarker() throws {
        let episodes = [
            try fingerprint(id: "e1", duration: 1_200, intro: 10...50),
            try fingerprint(id: "e2", duration: 1_210, intro: 10...50),
            try fingerprint(id: "special", duration: 500, intro: 10...50)
        ]

        let profile = try XCTUnwrap(
            SkipMarkerDetector().detect(seriesID: "series", fingerprints: episodes)
        )
        XCTAssertEqual(profile.agreeingEpisodeCount, 2)
        XCTAssertEqual(profile.referenceDuration ?? -1, 1_205, accuracy: 0.1)

        let mismatchedPair = [
            try fingerprint(id: "e1", duration: 1_200, intro: 10...50),
            try fingerprint(id: "special", duration: 500, intro: 10...50)
        ]
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: mismatchedPair))

        let invalid = EpisodeFingerprint(
            seriesID: "series",
            episodeID: "invalid",
            duration: .nan,
            samples: [PerceptualHashSample(time: 10, hash: 1)],
            sampledAt: date(1),
            schemaVersion: 1
        )
        XCTAssertNil(SkipMarkerDetector().detect(seriesID: "series", fingerprints: [invalid, invalid]))
    }

    func testConflictingEpisodeIsIgnoredAndAdditionalAgreementRaisesConfidence() throws {
        let first = try fingerprint(id: "e1", intro: 10...50)
        let second = try fingerprint(id: "e2", intro: 12...52)
        let conflict = try fingerprint(id: "e3", intro: 80...120, seed: 4_000)
        let twoEpisode = try XCTUnwrap(
            SkipMarkerDetector().detect(seriesID: "series", fingerprints: [first, second])
        )
        let withConflict = try XCTUnwrap(
            SkipMarkerDetector().detect(seriesID: "series", fingerprints: [first, second, conflict])
        )
        XCTAssertEqual(withConflict.agreeingEpisodeCount, 2)

        let thirdAgreement = try fingerprint(id: "e3", intro: 14...54)
        let threeEpisode = try XCTUnwrap(
            SkipMarkerDetector().detect(seriesID: "series", fingerprints: [first, second, thirdAgreement])
        )
        XCTAssertEqual(threeEpisode.agreeingEpisodeCount, 3)
        XCTAssertGreaterThan(threeEpisode.confidence, twoEpisode.confidence)
    }

    func testBoundsInputToThreeNewestEpisodesAndFiveHundredHashes() throws {
        let oldMatching = try fingerprint(id: "old", intro: 10...50, sampledAt: 1)
        let recentOne = try fingerprint(id: "new-1", intro: 90...130, seed: 8_000, sampledAt: 2)
        let recentTwo = try fingerprint(id: "new-2", intro: 180...220, seed: 16_000, sampledAt: 3)
        let recentThree = try fingerprint(id: "new-3", intro: 270...310, seed: 24_000, sampledAt: 4)

        XCTAssertNil(SkipMarkerDetector().detect(
            seriesID: "series",
            fingerprints: [oldMatching, recentOne, recentTwo, recentThree]
        ))
    }

    private func fingerprint(
        id: String,
        duration: Double = 1_200,
        intro: ClosedRange<Int>? = nil,
        outroRemaining: ClosedRange<Int>? = nil,
        seed: UInt64? = nil,
        sampledAt: TimeInterval = 1
    ) throws -> EpisodeFingerprint {
        let backgroundSeed = seed ?? id.utf8.enumerated().reduce(UInt64(10_000)) {
            $0 &+ UInt64($1.offset + 1) &* UInt64($1.element)
        }
        let samples = stride(from: 0, through: Int(duration), by: 2).map { time -> PerceptualHashSample in
            let hash: UInt64
            if let intro, intro.contains(time) {
                hash = sequenceHash(UInt64(time - intro.lowerBound) / 2, salt: 10)
            } else if let outroRemaining, outroRemaining.contains(Int(duration) - time) {
                hash = sequenceHash(
                    UInt64(outroRemaining.upperBound - (Int(duration) - time)) / 2,
                    salt: 1_000
                )
            } else {
                hash = sequenceHash(UInt64(time / 2), salt: backgroundSeed)
            }
            return PerceptualHashSample(time: Double(time), hash: hash)
        }
        return try EpisodeFingerprint(
            validatingSeriesID: "series",
            episodeID: id,
            duration: duration,
            samples: samples,
            sampledAt: date(sampledAt)
        )
    }

    private func replacing(
        _ fingerprint: EpisodeFingerprint,
        samples: [PerceptualHashSample]
    ) throws -> EpisodeFingerprint {
        try EpisodeFingerprint(
            validatingSeriesID: fingerprint.seriesID,
            episodeID: fingerprint.episodeID,
            duration: fingerprint.duration,
            samples: samples,
            sampledAt: fingerprint.sampledAt
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private func sequenceHash(_ index: UInt64, salt: UInt64) -> UInt64 {
        var value = index ^ (salt &* 0xD6E8_FEB8_6659_FD93) ^ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
