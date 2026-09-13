import XCTest
@testable import MyVideo

final class SkipOpportunityProjectorTests: XCTestCase {
    func testLearnedIntroAppearsOnlyInsideConfiguredWindow() throws {
        let profile = try profile(
            intro: SkipIntroMarker(start: 12, end: 72),
            source: .learned
        )

        XCTAssertNil(project(profile, position: 11.999))
        XCTAssertEqual(project(profile, position: 12)?.kind, .intro)
        XCTAssertEqual(project(profile, position: 12)?.target, 72)
        XCTAssertEqual(project(profile, position: 71.999)?.kind, .intro)
        XCTAssertNil(project(profile, position: 72))
    }

    func testCorrectedIntroWithoutStartAppearsFiveSecondsAfterProgramStart() throws {
        let profile = try profile(
            intro: SkipIntroMarker(start: nil, end: 61),
            source: .userCorrected
        )

        XCTAssertNil(project(profile, position: 4.999))
        XCTAssertEqual(project(profile, position: 5)?.target, 61)
    }

    func testOutroUsesSecondsRemainingAndTargetsProgramCompletion() throws {
        let profile = try self.profile(outroStartSecondsRemaining: 45)

        XCTAssertNil(project(profile, position: 954.999, duration: 1_000))
        XCTAssertEqual(
            project(profile, position: 955, duration: 1_000),
            SkipOpportunity(kind: .outro, target: 1_000)
        )
        XCTAssertNil(project(profile, position: 1_000, duration: 1_000))
    }

    func testIntroTargetIsClampedToDurationAndNeverMovesBackward() throws {
        let beyondDuration = try profile(
            intro: SkipIntroMarker(start: nil, end: 500),
            referenceDuration: nil
        )
        XCTAssertEqual(project(beyondDuration, position: 10, duration: 120)?.target, 120)

        let beforePosition = try profile(
            intro: SkipIntroMarker(start: nil, end: 8),
            referenceDuration: nil
        )
        XCTAssertNil(project(beforePosition, position: 10, duration: 120))
    }

    func testUnsupportedPlaybackStatesNeverPublishAnOpportunity() throws {
        let profile = try self.profile(
            intro: SkipIntroMarker(start: nil, end: 60),
            outroStartSecondsRemaining: 30
        )
        let baseline = SkipPlaybackState(
            isSerial: true,
            isAdvertisement: false,
            isLoading: false,
            isSeeking: false,
            isSeekable: true,
            position: 10,
            duration: 100
        )

        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, isSerial: false)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, isAdvertisement: true)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, isLoading: true)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, isSeeking: true)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, isSeekable: false)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, position: .nan)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, duration: .infinity)))
        XCTAssertNil(SkipOpportunityProjector.project(profile: profile, playback: replacing(baseline, duration: 0)))
    }

    func testDisabledLowConfidenceAndDurationOutlierProfilesAreHidden() throws {
        let disabled = try profile(intro: SkipIntroMarker(start: nil, end: 60), disabled: true)
        XCTAssertNil(project(disabled, position: 10))

        let lowConfidence = try profile(
            intro: SkipIntroMarker(start: nil, end: 60),
            confidence: 0.84
        )
        XCTAssertNil(project(lowConfidence, position: 10))

        let learned = try profile(
            intro: SkipIntroMarker(start: nil, end: 60),
            referenceDuration: 1_000
        )
        XCTAssertNotNil(project(learned, position: 10, duration: 800))
        XCTAssertNil(project(learned, position: 10, duration: 799.9))

        let corrected = try profile(
            intro: SkipIntroMarker(start: nil, end: 60),
            source: .userCorrected,
            referenceDuration: 1_000
        )
        XCTAssertNotNil(project(corrected, position: 10, duration: 500))
    }

    func testUserCorrectionDoesNotRequireLearnedConfidenceOrEpisodeAgreement() throws {
        let corrected = try profile(
            intro: SkipIntroMarker(start: nil, end: 60),
            source: .userCorrected,
            confidence: 0.2
        )

        XCTAssertEqual(project(corrected, position: 10)?.kind, .intro)
    }

    func testLearnedMarkerRequiresTwoAgreeingEpisodes() throws {
        let profile = try SeriesSkipProfile(
            validatingSeriesID: "series-1",
            intro: SkipIntroMarker(start: 10, end: 60),
            outroStartSecondsRemaining: nil,
            confidence: 0.95,
            agreeingEpisodeCount: 1,
            source: .learned,
            referenceDuration: 1_000,
            updatedAt: Date(timeIntervalSince1970: 100),
            disabled: false
        )

        XCTAssertNil(project(profile, position: 20))
    }

    func testOutroLongerThanProgramIsRejectedInsteadOfShowingAtStart() throws {
        let profile = try self.profile(
            outroStartSecondsRemaining: 150,
            source: .userCorrected,
            referenceDuration: nil
        )

        XCTAssertNil(project(profile, position: 10, duration: 100))
    }

    func testIntroWinsWhenIntroAndOutroWindowsOverlap() throws {
        let profile = try self.profile(
            intro: SkipIntroMarker(start: nil, end: 80),
            outroStartSecondsRemaining: 50,
            referenceDuration: 100
        )

        XCTAssertEqual(project(profile, position: 60, duration: 100)?.kind, .intro)
    }

    private func project(
        _ profile: SeriesSkipProfile,
        position: Double,
        duration: Double = 1_000
    ) -> SkipOpportunity? {
        SkipOpportunityProjector.project(
            profile: profile,
            playback: SkipPlaybackState(
                isSerial: true,
                isAdvertisement: false,
                isLoading: false,
                isSeeking: false,
                isSeekable: true,
                position: position,
                duration: duration
            )
        )
    }

    private func profile(
        intro: SkipIntroMarker? = nil,
        outroStartSecondsRemaining: Double? = nil,
        source: SkipMarkerSource = .learned,
        confidence: Double = 0.9,
        referenceDuration: Double? = 1_000,
        disabled: Bool = false
    ) throws -> SeriesSkipProfile {
        try SeriesSkipProfile(
            validatingSeriesID: "series-1",
            intro: intro,
            outroStartSecondsRemaining: outroStartSecondsRemaining,
            confidence: confidence,
            agreeingEpisodeCount: source == .userCorrected ? 1 : 2,
            source: source,
            referenceDuration: referenceDuration,
            updatedAt: Date(timeIntervalSince1970: 100),
            disabled: disabled
        )
    }

    private func replacing(
        _ state: SkipPlaybackState,
        isSerial: Bool? = nil,
        isAdvertisement: Bool? = nil,
        isLoading: Bool? = nil,
        isSeeking: Bool? = nil,
        isSeekable: Bool? = nil,
        position: Double? = nil,
        duration: Double? = nil
    ) -> SkipPlaybackState {
        SkipPlaybackState(
            isSerial: isSerial ?? state.isSerial,
            isAdvertisement: isAdvertisement ?? state.isAdvertisement,
            isLoading: isLoading ?? state.isLoading,
            isSeeking: isSeeking ?? state.isSeeking,
            isSeekable: isSeekable ?? state.isSeekable,
            position: position ?? state.position,
            duration: duration ?? state.duration
        )
    }
}
