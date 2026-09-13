import Foundation

enum SkipOpportunityProjector {
    static func project(
        profile: SeriesSkipProfile?,
        playback: SkipPlaybackState,
        policy: SkipDetectionPolicy = .standard
    ) -> SkipOpportunity? {
        guard
            let profile,
            playback.isSerial,
            !playback.isAdvertisement,
            !playback.isLoading,
            !playback.isSeeking,
            playback.isSeekable,
            playback.position.isFinite,
            playback.duration.isFinite,
            playback.position >= 0,
            playback.position < playback.duration,
            isAccepted(profile, policy: policy),
            profile.isApplicable(to: playback.duration, policy: policy)
        else {
            return nil
        }

        if let introOpportunity = introOpportunity(
            profile: profile,
            playback: playback,
            policy: policy
        ) {
            return introOpportunity
        }
        return outroOpportunity(profile: profile, playback: playback)
    }

    private static func isAccepted(
        _ profile: SeriesSkipProfile,
        policy: SkipDetectionPolicy
    ) -> Bool {
        if profile.source == .userCorrected {
            return true
        }
        guard profile.confidence >= policy.minimumConfidence else {
            return false
        }
        return profile.source != .learned
            || profile.agreeingEpisodeCount >= policy.minimumAgreeingEpisodes
    }

    private static func introOpportunity(
        profile: SeriesSkipProfile,
        playback: SkipPlaybackState,
        policy: SkipDetectionPolicy
    ) -> SkipOpportunity? {
        guard let intro = profile.intro else {
            return nil
        }
        let presentationTime = intro.start ?? policy.defaultIntroPresentationTime
        let target = min(max(0, intro.end), playback.duration)
        guard
            playback.position >= presentationTime,
            playback.position < intro.end,
            target > playback.position
        else {
            return nil
        }
        return SkipOpportunity(kind: .intro, target: target)
    }

    private static func outroOpportunity(
        profile: SeriesSkipProfile,
        playback: SkipPlaybackState
    ) -> SkipOpportunity? {
        guard
            let secondsRemaining = profile.outroStartSecondsRemaining,
            secondsRemaining < playback.duration
        else {
            return nil
        }
        let presentationTime = max(0, playback.duration - secondsRemaining)
        guard playback.position >= presentationTime else {
            return nil
        }
        return SkipOpportunity(kind: .outro, target: playback.duration)
    }
}
