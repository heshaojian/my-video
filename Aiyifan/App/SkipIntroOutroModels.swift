import Foundation

struct SkipDetectionPolicy: Equatable, Sendable {
    let sampleInterval: TimeInterval
    let introWindow: TimeInterval
    let outroWindow: TimeInterval
    let maximumHashDistance: Int
    let minimumSequenceDuration: TimeInterval
    let minimumMatchRatio: Double
    let markerAgreementTolerance: TimeInterval
    let minimumAgreeingEpisodes: Int
    let minimumConfidence: Double
    let maximumStoredEpisodesPerSeries: Int
    let maximumHashesPerEpisode: Int
    let maximumDurationVarianceRatio: Double
    let defaultIntroPresentationTime: TimeInterval
    let undoDuration: TimeInterval

    static let standard = SkipDetectionPolicy(
        sampleInterval: 2,
        introWindow: 8 * 60,
        outroWindow: 6 * 60,
        maximumHashDistance: 10,
        minimumSequenceDuration: 30,
        minimumMatchRatio: 0.85,
        markerAgreementTolerance: 10,
        minimumAgreeingEpisodes: 2,
        minimumConfidence: 0.85,
        maximumStoredEpisodesPerSeries: 3,
        maximumHashesPerEpisode: 500,
        maximumDurationVarianceRatio: 0.20,
        defaultIntroPresentationTime: 5,
        undoDuration: 8
    )
}

enum SkipMarkerSource: String, Codable, CaseIterable, Sendable {
    case provider
    case learned
    case userCorrected

    fileprivate var precedence: Int {
        switch self {
        case .learned: 0
        case .provider: 1
        case .userCorrected: 2
        }
    }
}

struct SkipIntroMarker: Codable, Equatable, Sendable {
    let start: TimeInterval?
    let end: TimeInterval
}

struct PerceptualHashSample: Codable, Equatable, Sendable {
    let time: TimeInterval
    let hash: UInt64
}

struct EpisodeFingerprint: Codable, Equatable, Sendable {
    let seriesID: String
    let episodeID: String
    let duration: TimeInterval
    let samples: [PerceptualHashSample]
    let sampledAt: Date
    let schemaVersion: Int
}

extension EpisodeFingerprint {
    init(
        validatingSeriesID seriesID: String,
        episodeID: String,
        duration: TimeInterval,
        samples: [PerceptualHashSample],
        sampledAt: Date,
        schemaVersion: Int = 1,
        policy: SkipDetectionPolicy = .standard
    ) throws {
        let candidate = EpisodeFingerprint(
            seriesID: seriesID,
            episodeID: episodeID,
            duration: duration,
            samples: samples,
            sampledAt: sampledAt,
            schemaVersion: schemaVersion
        )
        self = try candidate.validated(policy: policy)
    }

    func validated(policy: SkipDetectionPolicy = .standard) throws -> EpisodeFingerprint {
        guard
            Self.isValidIdentifier(seriesID),
            Self.isValidIdentifier(episodeID),
            duration.isFinite,
            duration > 0,
            duration <= 24 * 60 * 60,
            sampledAt.timeIntervalSinceReferenceDate.isFinite,
            schemaVersion == 1
        else {
            throw SkipModelValidationError.invalidFingerprint
        }

        var samplesByTime: [TimeInterval: PerceptualHashSample] = [:]
        for sample in samples where sample.time.isFinite && sample.time >= 0 && sample.time <= duration {
            samplesByTime[sample.time] = sample
        }
        let sortedSamples = samplesByTime.values.sorted { $0.time < $1.time }
        let normalizedSamples: [PerceptualHashSample]
        if sortedSamples.count <= policy.maximumHashesPerEpisode {
            normalizedSamples = sortedSamples
        } else {
            let headCount = (policy.maximumHashesPerEpisode + 1) / 2
            let tailCount = policy.maximumHashesPerEpisode - headCount
            normalizedSamples = Array(sortedSamples.prefix(headCount))
                + Array(sortedSamples.suffix(tailCount))
        }

        guard !normalizedSamples.isEmpty else {
            throw SkipModelValidationError.invalidFingerprint
        }

        return EpisodeFingerprint(
            seriesID: seriesID.trimmingCharacters(in: .whitespacesAndNewlines),
            episodeID: episodeID.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            samples: normalizedSamples,
            sampledAt: sampledAt,
            schemaVersion: 1
        )
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.utf8.count <= 512
            && trimmed.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

struct SeriesSkipProfile: Codable, Equatable, Sendable {
    let seriesID: String
    let intro: SkipIntroMarker?
    let outroStartSecondsRemaining: TimeInterval?
    let confidence: Double
    let agreeingEpisodeCount: Int
    let source: SkipMarkerSource
    let referenceDuration: TimeInterval?
    let updatedAt: Date
    let disabled: Bool
    let schemaVersion: Int
}

extension SeriesSkipProfile {
    init(
        validatingSeriesID seriesID: String,
        intro: SkipIntroMarker?,
        outroStartSecondsRemaining: TimeInterval?,
        confidence: Double,
        agreeingEpisodeCount: Int,
        source: SkipMarkerSource,
        referenceDuration: TimeInterval?,
        updatedAt: Date,
        disabled: Bool,
        schemaVersion: Int = 1
    ) throws {
        let candidate = SeriesSkipProfile(
            seriesID: seriesID,
            intro: intro,
            outroStartSecondsRemaining: outroStartSecondsRemaining,
            confidence: confidence,
            agreeingEpisodeCount: agreeingEpisodeCount,
            source: source,
            referenceDuration: referenceDuration,
            updatedAt: updatedAt,
            disabled: disabled,
            schemaVersion: schemaVersion
        )
        try candidate.validate()
        self = candidate.normalized
    }

    func validate() throws {
        guard
            EpisodeFingerprint.isValidIdentifier(seriesID),
            confidence.isFinite,
            (0...1).contains(confidence),
            agreeingEpisodeCount >= 0,
            agreeingEpisodeCount <= 100_000,
            updatedAt.timeIntervalSinceReferenceDate.isFinite,
            schemaVersion == 1
        else {
            throw SkipModelValidationError.invalidProfile
        }

        if let intro {
            guard
                intro.end.isFinite,
                intro.end > 0,
                intro.end <= 24 * 60 * 60
            else {
                throw SkipModelValidationError.invalidProfile
            }
            if let start = intro.start {
                guard start.isFinite, start >= 0, start < intro.end else {
                    throw SkipModelValidationError.invalidProfile
                }
            }
        }

        if let outroStartSecondsRemaining {
            guard
                outroStartSecondsRemaining.isFinite,
                outroStartSecondsRemaining > 0,
                outroStartSecondsRemaining <= 24 * 60 * 60
            else {
                throw SkipModelValidationError.invalidProfile
            }
        }

        if let referenceDuration {
            guard
                referenceDuration.isFinite,
                referenceDuration > 0,
                referenceDuration <= 24 * 60 * 60
            else {
                throw SkipModelValidationError.invalidProfile
            }
        }
    }

    func isApplicable(
        to duration: TimeInterval,
        policy: SkipDetectionPolicy = .standard
    ) -> Bool {
        guard !disabled, duration.isFinite, duration > 0 else {
            return false
        }
        guard source != .userCorrected, let referenceDuration else {
            return true
        }
        return abs(duration - referenceDuration) / referenceDuration
            <= policy.maximumDurationVarianceRatio
    }

    static func merged(
        local: SeriesSkipProfile,
        incoming: SeriesSkipProfile
    ) -> SeriesSkipProfile {
        guard local.seriesID == incoming.seriesID else {
            return local
        }
        if local.source == .userCorrected, incoming.source != .userCorrected {
            return local
        }
        if incoming.source == .userCorrected, local.source != .userCorrected {
            return incoming
        }
        if local.updatedAt != incoming.updatedAt {
            return local.updatedAt > incoming.updatedAt ? local : incoming
        }
        if local.source.precedence != incoming.source.precedence {
            return local.source.precedence > incoming.source.precedence ? local : incoming
        }
        return local.stableMergeKey >= incoming.stableMergeKey ? local : incoming
    }

    private var normalized: SeriesSkipProfile {
        SeriesSkipProfile(
            seriesID: seriesID.trimmingCharacters(in: .whitespacesAndNewlines),
            intro: intro,
            outroStartSecondsRemaining: outroStartSecondsRemaining,
            confidence: confidence,
            agreeingEpisodeCount: agreeingEpisodeCount,
            source: source,
            referenceDuration: referenceDuration,
            updatedAt: updatedAt,
            disabled: disabled,
            schemaVersion: 1
        )
    }

    private var stableMergeKey: String {
        [
            source.rawValue,
            String(confidence),
            String(agreeingEpisodeCount),
            String(intro?.start ?? -1),
            String(intro?.end ?? -1),
            String(outroStartSecondsRemaining ?? -1),
            String(referenceDuration ?? -1),
            disabled ? "1" : "0"
        ].joined(separator: "|")
    }
}

enum SkipProfileOperationKind: String, Codable, Sendable {
    case disable
    case reset
}

struct SkipProfileTombstone: Codable, Equatable, Sendable {
    let seriesID: String
    let kind: SkipProfileOperationKind
    let updatedAt: Date
}

struct SkipPlaybackState: Equatable, Sendable {
    let isSerial: Bool
    let isAdvertisement: Bool
    let isLoading: Bool
    let isSeeking: Bool
    let isSeekable: Bool
    let position: TimeInterval
    let duration: TimeInterval
}

struct SkipOpportunity: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case intro
        case outro
    }

    let kind: Kind
    let target: TimeInterval
}

enum SkipModelValidationError: Error, Equatable {
    case invalidProfile
    case invalidFingerprint
}
