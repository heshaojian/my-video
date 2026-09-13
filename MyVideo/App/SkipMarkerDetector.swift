import Foundation

struct SkipMarkerDetector {
    private enum Window {
        case intro
        case outro
    }

    private struct TimedHash {
        let coordinate: TimeInterval
        let hash: UInt64
    }

    private struct SequenceMatch {
        let first: ClosedRange<TimeInterval>
        let second: ClosedRange<TimeInterval>
        let ratio: Double
    }

    private struct PairCandidate {
        let episodeIDs: Set<String>
        let start: TimeInterval
        let end: TimeInterval
        let ratio: Double
    }

    private struct MarkerCandidate {
        let start: TimeInterval?
        let end: TimeInterval
        let confidence: Double
        let episodeIDs: Set<String>
    }

    private typealias Observation = (first: TimedHash, second: TimedHash, matches: Bool)

    private let policy: SkipDetectionPolicy

    init(policy: SkipDetectionPolicy = .standard) {
        self.policy = policy
    }

    func detect(
        seriesID: String,
        fingerprints: [EpisodeFingerprint],
        detectedAt: Date = Date()
    ) -> SeriesSkipProfile? {
        guard
            EpisodeFingerprint.isValidIdentifier(seriesID),
            detectedAt.timeIntervalSinceReferenceDate.isFinite
        else {
            return nil
        }

        let bounded = boundedFingerprints(seriesID: seriesID, fingerprints: fingerprints)
        let episodes = durationConsistentCluster(bounded)
        guard episodes.count >= policy.minimumAgreeingEpisodes else { return nil }

        let intro = detectMarker(in: episodes, window: .intro)
        let outro = detectMarker(in: episodes, window: .outro)
        let markers = [intro, outro].compactMap { $0 }
        guard !markers.isEmpty else { return nil }

        let confidence = markers.map(\.confidence).min() ?? 0
        let agreeingCount = markers.map { $0.episodeIDs.count }.max() ?? 0
        guard
            confidence >= policy.minimumConfidence,
            agreeingCount >= policy.minimumAgreeingEpisodes
        else {
            return nil
        }

        return try? SeriesSkipProfile(
            validatingSeriesID: seriesID,
            intro: intro.map { SkipIntroMarker(start: $0.start, end: $0.end) },
            outroStartSecondsRemaining: outro?.end,
            confidence: confidence,
            agreeingEpisodeCount: agreeingCount,
            source: .learned,
            referenceDuration: median(episodes.map(\.duration)),
            updatedAt: detectedAt,
            disabled: false
        )
    }

    private func boundedFingerprints(
        seriesID: String,
        fingerprints: [EpisodeFingerprint]
    ) -> [EpisodeFingerprint] {
        var newestByEpisode: [String: EpisodeFingerprint] = [:]
        for candidate in fingerprints where candidate.seriesID == seriesID {
            guard let validated = try? candidate.validated(policy: policy) else { continue }
            if let current = newestByEpisode[validated.episodeID],
               current.sampledAt >= validated.sampledAt {
                continue
            }
            newestByEpisode[validated.episodeID] = validated
        }

        return newestByEpisode.values
            .sorted {
                if $0.sampledAt != $1.sampledAt { return $0.sampledAt > $1.sampledAt }
                return $0.episodeID < $1.episodeID
            }
            .prefix(policy.maximumStoredEpisodesPerSeries)
            .map { fingerprint in
                EpisodeFingerprint(
                    seriesID: fingerprint.seriesID,
                    episodeID: fingerprint.episodeID,
                    duration: fingerprint.duration,
                    samples: Array(fingerprint.samples.prefix(policy.maximumHashesPerEpisode)),
                    sampledAt: fingerprint.sampledAt,
                    schemaVersion: fingerprint.schemaVersion
                )
            }
    }

    private func durationConsistentCluster(
        _ fingerprints: [EpisodeFingerprint]
    ) -> [EpisodeFingerprint] {
        let clusters = fingerprints.map { center in
            fingerprints.filter {
                abs($0.duration - center.duration) / center.duration
                    <= policy.maximumDurationVarianceRatio
            }
        }
        return clusters.max { left, right in
            if left.count != right.count { return left.count < right.count }
            let leftSpread = durationSpread(left)
            let rightSpread = durationSpread(right)
            if leftSpread != rightSpread { return leftSpread > rightSpread }
            return stableEpisodeKey(left) > stableEpisodeKey(right)
        } ?? []
    }

    private func detectMarker(
        in episodes: [EpisodeFingerprint],
        window: Window
    ) -> MarkerCandidate? {
        var pairs: [PairCandidate] = []
        for firstIndex in episodes.indices {
            for secondIndex in episodes.indices where secondIndex > firstIndex {
                guard let match = bestSequenceMatch(
                    first: samples(for: episodes[firstIndex], window: window),
                    second: samples(for: episodes[secondIndex], window: window)
                ) else {
                    continue
                }

                let introEndPadding: TimeInterval
                switch window {
                case .intro: introEndPadding = policy.sampleInterval
                case .outro: introEndPadding = 0
                }
                pairs.append(PairCandidate(
                    episodeIDs: [episodes[firstIndex].episodeID, episodes[secondIndex].episodeID],
                    start: average(match.first.lowerBound, match.second.lowerBound),
                    end: average(match.first.upperBound, match.second.upperBound) + introEndPadding,
                    ratio: match.ratio
                ))
            }
        }
        guard !pairs.isEmpty else { return nil }

        let clusters = pairs.map { seed in
            pairs.filter { abs($0.end - seed.end) <= policy.markerAgreementTolerance }
        }
        guard let best = clusters.max(by: { isLowerRank($0, than: $1) }) else { return nil }
        let episodeIDs = best.reduce(into: Set<String>()) { result, pair in
            result.formUnion(pair.episodeIDs)
        }
        guard episodeIDs.count >= policy.minimumAgreeingEpisodes else { return nil }

        let ratio = best.map(\.ratio).reduce(0, +) / Double(best.count)
        let confidence = min(
            1,
            policy.minimumConfidence
                + max(0, ratio - policy.minimumMatchRatio) * 0.5
                + Double(episodeIDs.count - policy.minimumAgreeingEpisodes) * 0.025
        )
        guard confidence >= policy.minimumConfidence else { return nil }

        let markerStart: TimeInterval?
        switch window {
        case .intro: markerStart = median(best.map(\.start))
        case .outro: markerStart = nil
        }
        return MarkerCandidate(
            start: markerStart,
            end: median(best.map(\.end)),
            confidence: confidence,
            episodeIDs: episodeIDs
        )
    }

    private func samples(
        for fingerprint: EpisodeFingerprint,
        window: Window
    ) -> [TimedHash] {
        fingerprint.samples.compactMap { sample in
            let coordinate: TimeInterval
            let limit: TimeInterval
            switch window {
            case .intro:
                coordinate = sample.time
                limit = min(policy.introWindow, fingerprint.duration)
            case .outro:
                coordinate = fingerprint.duration - sample.time
                limit = min(policy.outroWindow, fingerprint.duration)
            }
            guard coordinate >= 0, coordinate <= limit else { return nil }
            return TimedHash(coordinate: coordinate, hash: sample.hash)
        }
        .sorted { $0.coordinate < $1.coordinate }
    }

    private func bestSequenceMatch(
        first: [TimedHash],
        second: [TimedHash]
    ) -> SequenceMatch? {
        guard first.count >= 2, second.count >= 2 else { return nil }
        let offsets = Set(first.flatMap { left in
            second.compactMap { right -> Int? in
                let difference = right.coordinate - left.coordinate
                guard abs(difference) <= policy.markerAgreementTolerance else { return nil }
                return Int(difference.rounded())
            }
        })

        var best: SequenceMatch?
        for offset in offsets.sorted() {
            let observations = alignedObservations(
                first: first,
                second: second,
                offset: TimeInterval(offset)
            )
            for segment in contiguousSegments(observations) {
                var matchPrefix = [Int](repeating: 0, count: segment.count + 1)
                for index in segment.indices {
                    matchPrefix[index + 1] = matchPrefix[index] + (segment[index].matches ? 1 : 0)
                }
                for startIndex in segment.indices where segment[startIndex].matches {
                    for endIndex in segment.indices where endIndex > startIndex && segment[endIndex].matches {
                        let span = segment[endIndex].first.coordinate - segment[startIndex].first.coordinate
                        guard span >= policy.minimumSequenceDuration else { continue }
                        let matchCount = matchPrefix[endIndex + 1] - matchPrefix[startIndex]
                        let count = endIndex - startIndex + 1
                        let ratio = Double(matchCount) / Double(count)
                        guard ratio >= policy.minimumMatchRatio else { continue }

                        let candidate = SequenceMatch(
                            first: segment[startIndex].first.coordinate...segment[endIndex].first.coordinate,
                            second: segment[startIndex].second.coordinate...segment[endIndex].second.coordinate,
                            ratio: ratio
                        )
                        if isBetter(candidate, than: best) { best = candidate }
                    }
                }
            }
        }
        return best
    }

    private func alignedObservations(
        first: [TimedHash],
        second: [TimedHash],
        offset: TimeInterval
    ) -> [Observation] {
        guard !second.isEmpty else { return [] }
        var rightIndex = 0
        return first.compactMap { left in
            let target = left.coordinate + offset
            while rightIndex + 1 < second.count,
                  abs(second[rightIndex + 1].coordinate - target) < abs(second[rightIndex].coordinate - target) {
                rightIndex += 1
            }
            let right = second[rightIndex]
            guard abs(right.coordinate - target) <= policy.sampleInterval / 2 else {
                return nil
            }
            return (
                first: left,
                second: right,
                matches: PerceptualFrameHasher.hammingDistance(left.hash, right.hash)
                    <= policy.maximumHashDistance
            )
        }
    }

    private func contiguousSegments(_ observations: [Observation]) -> [[Observation]] {
        var segments: [[Observation]] = []
        for observation in observations {
            guard var current = segments.popLast() else {
                segments.append([observation])
                continue
            }
            let previous = current[current.count - 1]
            let maximumGap = policy.sampleInterval * 1.5
            if observation.first.coordinate - previous.first.coordinate <= maximumGap,
               observation.second.coordinate - previous.second.coordinate <= maximumGap {
                current.append(observation)
                segments.append(current)
            } else {
                segments.append(current)
                segments.append([observation])
            }
        }
        return segments
    }

    private func isBetter(_ candidate: SequenceMatch, than current: SequenceMatch?) -> Bool {
        guard let current else { return true }
        let candidateSpan = candidate.first.upperBound - candidate.first.lowerBound
        let currentSpan = current.first.upperBound - current.first.lowerBound
        if candidateSpan != currentSpan { return candidateSpan > currentSpan }
        if candidate.ratio != current.ratio { return candidate.ratio > current.ratio }
        return candidate.first.lowerBound < current.first.lowerBound
    }

    private func isLowerRank(_ left: [PairCandidate], than right: [PairCandidate]) -> Bool {
        let leftEpisodes = episodeCount(left)
        let rightEpisodes = episodeCount(right)
        if leftEpisodes != rightEpisodes { return leftEpisodes < rightEpisodes }
        if left.count != right.count { return left.count < right.count }
        return averageRatio(left) < averageRatio(right)
    }

    private func episodeCount(_ pairs: [PairCandidate]) -> Int {
        pairs.reduce(into: Set<String>()) { result, pair in
            result.formUnion(pair.episodeIDs)
        }.count
    }

    private func averageRatio(_ pairs: [PairCandidate]) -> Double {
        pairs.map(\.ratio).reduce(0, +) / Double(max(pairs.count, 1))
    }

    private func durationSpread(_ episodes: [EpisodeFingerprint]) -> TimeInterval {
        guard
            let minimum = episodes.map(\.duration).min(),
            let maximum = episodes.map(\.duration).max()
        else {
            return .infinity
        }
        return maximum - minimum
    }

    private func stableEpisodeKey(_ episodes: [EpisodeFingerprint]) -> String {
        episodes.map(\.episodeID).sorted().joined(separator: "|")
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? average(sorted[middle - 1], sorted[middle])
            : sorted[middle]
    }

    private func average(_ first: TimeInterval, _ second: TimeInterval) -> TimeInterval {
        first + (second - first) / 2
    }
}
