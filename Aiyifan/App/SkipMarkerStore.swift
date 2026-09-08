import Combine
import Foundation

struct SkipDataPersistence {
    let load: () throws -> Data?
    let save: (Data) throws -> Void
}

enum SkipStoreDiagnostic: Equatable {
    case invalidInput
    case invalidStoredData
    case unsupportedStoredVersion
    case readFailed
    case writeFailed
}

@MainActor
final class SkipMarkerStore: ObservableObject {
    @Published private(set) var profiles: [SeriesSkipProfile]
    @Published private(set) var allFingerprints: [EpisodeFingerprint]
    @Published private(set) var tombstones: [SkipProfileTombstone]
    @Published private(set) var diagnostic: SkipStoreDiagnostic?

    private struct ProfileEnvelope: Codable {
        let version: Int
        let profiles: [SeriesSkipProfile]
        let tombstones: [SkipProfileTombstone]
    }

    private struct FingerprintEnvelope: Codable {
        let version: Int
        let fingerprints: [EpisodeFingerprint]
    }

    private enum RestoreFailure {
        case invalidData
        case unsupportedVersion
        case readFailed

        var diagnostic: SkipStoreDiagnostic {
            switch self {
            case .invalidData: .invalidStoredData
            case .unsupportedVersion: .unsupportedStoredVersion
            case .readFailed: .readFailed
            }
        }
    }

    private static let profileStorageVersion = 1
    private static let fingerprintStorageVersion = 1
    private static let profileStorageKey = "aiyifanSkipProfilesV1"
    private static let fingerprintFilename = "skip-fingerprints-v1.json"

    private let profilePersistence: SkipDataPersistence
    private let fingerprintPersistence: SkipDataPersistence
    private let policy: SkipDetectionPolicy
    private let encoder: JSONEncoder

    private(set) var hasPendingProfilePersistence = false
    private(set) var hasPendingFingerprintPersistence = false

    convenience init(
        defaults: UserDefaults = .standard,
        fingerprintFileURL: URL? = nil,
        policy: SkipDetectionPolicy = .standard
    ) {
        let profilePersistence = SkipDataPersistence(
            load: { defaults.data(forKey: Self.profileStorageKey) },
            save: { defaults.set($0, forKey: Self.profileStorageKey) }
        )
        let fileURL = fingerprintFileURL ?? Self.defaultFingerprintFileURL()
        let fingerprintPersistence = SkipDataPersistence(
            load: {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }
                return try Data(contentsOf: fileURL)
            },
            save: { data in
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var storedFileURL = fileURL
                try storedFileURL.setResourceValues(values)
            }
        )
        self.init(
            profilePersistence: profilePersistence,
            fingerprintPersistence: fingerprintPersistence,
            policy: policy
        )
    }

    init(
        profilePersistence: SkipDataPersistence,
        fingerprintPersistence: SkipDataPersistence,
        policy: SkipDetectionPolicy = .standard
    ) {
        self.profilePersistence = profilePersistence
        self.fingerprintPersistence = fingerprintPersistence
        self.policy = policy
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let profileRestore = Self.restoreProfiles(from: profilePersistence, policy: policy)
        let fingerprintRestore = Self.restoreFingerprints(from: fingerprintPersistence, policy: policy)
        profiles = profileRestore.value?.profiles ?? []
        tombstones = profileRestore.value?.tombstones ?? []
        allFingerprints = fingerprintRestore.value ?? []
        diagnostic = profileRestore.failure?.diagnostic ?? fingerprintRestore.failure?.diagnostic
    }

    func profile(for seriesID: String) -> SeriesSkipProfile? {
        guard let profile = profiles.first(where: { $0.seriesID == seriesID }) else {
            return nil
        }
        guard let tombstone = latestTombstone(for: seriesID) else {
            return profile
        }
        if profile.updatedAt > tombstone.updatedAt {
            return profile
        }
        if profile.updatedAt == tombstone.updatedAt,
           tombstone.kind == .disable,
           profile.disabled {
            return profile
        }
        return nil
    }

    func fingerprints(for seriesID: String) -> [EpisodeFingerprint] {
        allFingerprints.filter { $0.seriesID == seriesID }
    }

    func isDisabled(seriesID: String) -> Bool {
        if let profile = profile(for: seriesID) {
            return profile.disabled
        }
        return latestTombstone(for: seriesID)?.kind == .disable
    }

    @discardableResult
    func save(profile candidate: SeriesSkipProfile) -> Bool {
        let profile: SeriesSkipProfile
        do {
            profile = try Self.validatedProfile(candidate)
        } catch {
            diagnostic = .invalidInput
            return false
        }

        if let tombstone = latestTombstone(for: profile.seriesID),
           tombstone.updatedAt >= profile.updatedAt {
            return false
        }

        if let existing = profiles.first(where: { $0.seriesID == profile.seriesID }) {
            let merged = SeriesSkipProfile.merged(local: existing, incoming: profile)
            guard merged != existing else {
                return false
            }
            profiles = sortedProfiles([merged] + profiles.filter { $0.seriesID != profile.seriesID })
        } else {
            profiles = sortedProfiles([profile] + profiles)
        }
        persistProfiles()
        return true
    }

    @discardableResult
    func save(fingerprint candidate: EpisodeFingerprint) -> Bool {
        guard !isDisabled(seriesID: candidate.seriesID) else {
            return false
        }
        let fingerprint: EpisodeFingerprint
        do {
            fingerprint = try candidate.validated(policy: policy)
        } catch {
            diagnostic = .invalidInput
            return false
        }

        if let tombstone = latestTombstone(for: fingerprint.seriesID),
           tombstone.updatedAt >= fingerprint.sampledAt {
            return false
        }
        if let existing = allFingerprints.first(where: {
            $0.seriesID == fingerprint.seriesID && $0.episodeID == fingerprint.episodeID
        }), existing.sampledAt >= fingerprint.sampledAt {
            return false
        }

        let replaced = [fingerprint] + allFingerprints.filter {
            !($0.seriesID == fingerprint.seriesID && $0.episodeID == fingerprint.episodeID)
        }
        allFingerprints = Self.prunedFingerprints(replaced, policy: policy)
        persistFingerprints()
        return true
    }

    @discardableResult
    func setIntroEnd(
        seriesID: String,
        time: TimeInterval,
        referenceDuration: TimeInterval?,
        at date: Date = Date()
    ) -> Bool {
        let current = profile(for: seriesID)
        return saveCorrection(
            seriesID: seriesID,
            intro: SkipIntroMarker(start: nil, end: time),
            outroStartSecondsRemaining: current?.outroStartSecondsRemaining,
            referenceDuration: referenceDuration ?? current?.referenceDuration,
            at: date
        )
    }

    @discardableResult
    func setOutroStart(
        seriesID: String,
        secondsRemaining: TimeInterval,
        referenceDuration: TimeInterval?,
        at date: Date = Date()
    ) -> Bool {
        let current = profile(for: seriesID)
        return saveCorrection(
            seriesID: seriesID,
            intro: current?.intro,
            outroStartSecondsRemaining: secondsRemaining,
            referenceDuration: referenceDuration ?? current?.referenceDuration,
            at: date
        )
    }

    @discardableResult
    func disable(seriesID: String, at date: Date = Date()) -> Bool {
        guard Self.validOperation(seriesID: seriesID, date: date) else {
            diagnostic = .invalidInput
            return false
        }
        let tombstone = SkipProfileTombstone(seriesID: seriesID, kind: .disable, updatedAt: date)
        guard operation(tombstone, isNotOlderThanStateFor: seriesID) else {
            return false
        }
        tombstones = replacingTombstone(tombstone)
        if let current = profiles.first(where: { $0.seriesID == seriesID }) {
            let disabled = SeriesSkipProfile(
                seriesID: current.seriesID,
                intro: current.intro,
                outroStartSecondsRemaining: current.outroStartSecondsRemaining,
                confidence: current.confidence,
                agreeingEpisodeCount: current.agreeingEpisodeCount,
                source: current.source,
                referenceDuration: current.referenceDuration,
                updatedAt: date,
                disabled: true,
                schemaVersion: 1
            )
            profiles = sortedProfiles([disabled] + profiles.filter { $0.seriesID != seriesID })
        }
        allFingerprints = allFingerprints.filter { $0.seriesID != seriesID }
        persistProfiles()
        persistFingerprints()
        return true
    }

    @discardableResult
    func reset(seriesID: String, at date: Date = Date()) -> Bool {
        guard Self.validOperation(seriesID: seriesID, date: date) else {
            diagnostic = .invalidInput
            return false
        }
        let tombstone = SkipProfileTombstone(seriesID: seriesID, kind: .reset, updatedAt: date)
        guard operation(tombstone, isNotOlderThanStateFor: seriesID) else {
            return false
        }
        profiles = profiles.filter { $0.seriesID != seriesID }
        allFingerprints = allFingerprints.filter { $0.seriesID != seriesID }
        tombstones = replacingTombstone(tombstone)
        persistProfiles()
        persistFingerprints()
        return true
    }

    @discardableResult
    func retryPendingPersistence() -> Bool {
        if hasPendingProfilePersistence {
            persistProfiles()
        }
        if hasPendingFingerprintPersistence {
            persistFingerprints()
        }
        return !hasPendingProfilePersistence && !hasPendingFingerprintPersistence
    }

    func mergeFromCloud(
        profiles incomingProfiles: [SeriesSkipProfile],
        tombstones incomingTombstones: [SkipProfileTombstone]
    ) {
        let validTombstones = incomingTombstones.filter(Self.isValidTombstone)
        for tombstone in validTombstones {
            let selected = latestTombstone(for: tombstone.seriesID)
                .map { Self.preferredTombstone($0, tombstone) } ?? tombstone
            tombstones = replacingTombstone(tombstone)
            if selected == tombstone {
                allFingerprints = allFingerprints.filter {
                    $0.seriesID != tombstone.seriesID || $0.sampledAt > tombstone.updatedAt
                }
            }
        }
        for profile in incomingProfiles {
            _ = save(profile: profile)
        }
        profiles = profiles.filter { profile in
            guard let tombstone = latestTombstone(for: profile.seriesID) else {
                return true
            }
            return Self.profile(profile, survives: tombstone)
        }
        persistProfiles()
        persistFingerprints()
    }

    private func saveCorrection(
        seriesID: String,
        intro: SkipIntroMarker?,
        outroStartSecondsRemaining: TimeInterval?,
        referenceDuration: TimeInterval?,
        at date: Date
    ) -> Bool {
        do {
            let profile = try SeriesSkipProfile(
                validatingSeriesID: seriesID,
                intro: intro,
                outroStartSecondsRemaining: outroStartSecondsRemaining,
                confidence: 1,
                agreeingEpisodeCount: 1,
                source: .userCorrected,
                referenceDuration: referenceDuration,
                updatedAt: date,
                disabled: false
            )
            return save(profile: profile)
        } catch {
            diagnostic = .invalidInput
            return false
        }
    }

    private func persistProfiles() {
        let envelope = ProfileEnvelope(
            version: Self.profileStorageVersion,
            profiles: profiles,
            tombstones: tombstones
        )
        do {
            try profilePersistence.save(encoder.encode(envelope))
            hasPendingProfilePersistence = false
            clearWriteDiagnosticIfResolved()
        } catch {
            hasPendingProfilePersistence = true
            diagnostic = .writeFailed
        }
    }

    private func persistFingerprints() {
        let envelope = FingerprintEnvelope(
            version: Self.fingerprintStorageVersion,
            fingerprints: allFingerprints
        )
        do {
            try fingerprintPersistence.save(encoder.encode(envelope))
            hasPendingFingerprintPersistence = false
            clearWriteDiagnosticIfResolved()
        } catch {
            hasPendingFingerprintPersistence = true
            diagnostic = .writeFailed
        }
    }

    private func clearWriteDiagnosticIfResolved() {
        if !hasPendingProfilePersistence,
           !hasPendingFingerprintPersistence,
           diagnostic == .writeFailed {
            diagnostic = nil
        }
    }

    private func latestTombstone(for seriesID: String) -> SkipProfileTombstone? {
        tombstones.first { $0.seriesID == seriesID }
    }

    private func operation(
        _ operation: SkipProfileTombstone,
        isNotOlderThanStateFor seriesID: String
    ) -> Bool {
        let profileDate = profiles.first { $0.seriesID == seriesID }?.updatedAt ?? .distantPast
        let fingerprintDate = allFingerprints
            .filter { $0.seriesID == seriesID }
            .map(\.sampledAt)
            .max() ?? .distantPast
        guard operation.updatedAt >= max(profileDate, fingerprintDate) else {
            return false
        }
        guard let existing = latestTombstone(for: seriesID) else {
            return true
        }
        return Self.preferredTombstone(existing, operation) == operation
    }

    private func replacingTombstone(_ tombstone: SkipProfileTombstone) -> [SkipProfileTombstone] {
        let selected = latestTombstone(for: tombstone.seriesID)
            .map { Self.preferredTombstone($0, tombstone) } ?? tombstone
        return ([selected] + tombstones.filter { $0.seriesID != tombstone.seriesID })
            .sorted { lhs, rhs in
                if lhs.seriesID != rhs.seriesID { return lhs.seriesID < rhs.seriesID }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func sortedProfiles(_ values: [SeriesSkipProfile]) -> [SeriesSkipProfile] {
        values.sorted { $0.seriesID < $1.seriesID }
    }

    private static func validatedProfile(_ profile: SeriesSkipProfile) throws -> SeriesSkipProfile {
        try profile.validate()
        guard profile.disabled || profile.intro != nil || profile.outroStartSecondsRemaining != nil else {
            throw SkipModelValidationError.invalidProfile
        }
        return try SeriesSkipProfile(
            validatingSeriesID: profile.seriesID,
            intro: profile.intro,
            outroStartSecondsRemaining: profile.outroStartSecondsRemaining,
            confidence: profile.confidence,
            agreeingEpisodeCount: profile.agreeingEpisodeCount,
            source: profile.source,
            referenceDuration: profile.referenceDuration,
            updatedAt: profile.updatedAt,
            disabled: profile.disabled,
            schemaVersion: profile.schemaVersion
        )
    }

    private static func prunedFingerprints(
        _ fingerprints: [EpisodeFingerprint],
        policy: SkipDetectionPolicy
    ) -> [EpisodeFingerprint] {
        Dictionary(grouping: fingerprints, by: \EpisodeFingerprint.seriesID)
            .values
            .flatMap { seriesFingerprints in
                seriesFingerprints.sorted { lhs, rhs in
                    if lhs.sampledAt != rhs.sampledAt { return lhs.sampledAt > rhs.sampledAt }
                    return lhs.episodeID < rhs.episodeID
                }
                .prefix(policy.maximumStoredEpisodesPerSeries)
            }
            .sorted { lhs, rhs in
                if lhs.seriesID != rhs.seriesID { return lhs.seriesID < rhs.seriesID }
                if lhs.sampledAt != rhs.sampledAt { return lhs.sampledAt > rhs.sampledAt }
                return lhs.episodeID < rhs.episodeID
            }
    }

    private static func restoreProfiles(
        from persistence: SkipDataPersistence,
        policy: SkipDetectionPolicy
    ) -> (value: (profiles: [SeriesSkipProfile], tombstones: [SkipProfileTombstone])?, failure: RestoreFailure?) {
        let data: Data
        do {
            guard let loaded = try persistence.load() else {
                return (([], []), nil)
            }
            data = loaded
        } catch {
            return (nil, .readFailed)
        }
        guard let version = envelopeVersion(in: data) else {
            return (nil, .invalidData)
        }
        guard version == profileStorageVersion else {
            return (nil, version > profileStorageVersion ? .unsupportedVersion : .invalidData)
        }
        guard let envelope = try? JSONDecoder().decode(ProfileEnvelope.self, from: data) else {
            return (nil, .invalidData)
        }

        let validProfiles = envelope.profiles.compactMap { try? validatedProfile($0) }
        let validTombstones = envelope.tombstones.filter(isValidTombstone)
        let values = resolvedProfiles(validProfiles, tombstones: validTombstones)
        let failure: RestoreFailure? = values.count == envelope.profiles.count
            && validTombstones.count == envelope.tombstones.count ? nil : .invalidData
        return ((values, sortedTombstones(validTombstones)), failure)
    }

    private static func restoreFingerprints(
        from persistence: SkipDataPersistence,
        policy: SkipDetectionPolicy
    ) -> (value: [EpisodeFingerprint]?, failure: RestoreFailure?) {
        let data: Data
        do {
            guard let loaded = try persistence.load() else {
                return ([], nil)
            }
            data = loaded
        } catch {
            return (nil, .readFailed)
        }
        guard let version = envelopeVersion(in: data) else {
            return (nil, .invalidData)
        }
        guard version == fingerprintStorageVersion else {
            return (nil, version > fingerprintStorageVersion ? .unsupportedVersion : .invalidData)
        }
        guard let envelope = try? JSONDecoder().decode(FingerprintEnvelope.self, from: data) else {
            return (nil, .invalidData)
        }
        let valid = envelope.fingerprints.compactMap { try? $0.validated(policy: policy) }
        let failure: RestoreFailure? = valid.count == envelope.fingerprints.count ? nil : .invalidData
        return (prunedFingerprints(valid, policy: policy), failure)
    }

    private static func envelopeVersion(in data: Data) -> Int? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["version"] as? Int
        else {
            return nil
        }
        return version
    }

    private static func resolvedProfiles(
        _ profiles: [SeriesSkipProfile],
        tombstones: [SkipProfileTombstone]
    ) -> [SeriesSkipProfile] {
        Dictionary(grouping: profiles, by: \SeriesSkipProfile.seriesID)
            .compactMap { seriesID, candidates in
                guard let merged = candidates.reduce(nil, { current, candidate in
                    current.map { SeriesSkipProfile.merged(local: $0, incoming: candidate) } ?? candidate
                }) else {
                    return nil
                }
                let tombstone = tombstones
                    .filter { $0.seriesID == seriesID }
                    .reduce(nil as SkipProfileTombstone?) { current, candidate in
                        current.map { preferredTombstone($0, candidate) } ?? candidate
                    }
                guard let tombstone else {
                    return merged
                }
                return profile(merged, survives: tombstone) ? merged : nil
            }
            .sorted { $0.seriesID < $1.seriesID }
    }

    private static func sortedTombstones(_ tombstones: [SkipProfileTombstone]) -> [SkipProfileTombstone] {
        Dictionary(grouping: tombstones, by: \SkipProfileTombstone.seriesID)
            .compactMap { _, values in
                values.reduce(nil as SkipProfileTombstone?) { current, candidate in
                    current.map { preferredTombstone($0, candidate) } ?? candidate
                }
            }
            .sorted { $0.seriesID < $1.seriesID }
    }

    private static func preferredTombstone(
        _ lhs: SkipProfileTombstone,
        _ rhs: SkipProfileTombstone
    ) -> SkipProfileTombstone {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        if lhs.kind == rhs.kind {
            return lhs
        }
        return lhs.kind == .reset ? lhs : rhs
    }

    private static func profile(
        _ profile: SeriesSkipProfile,
        survives tombstone: SkipProfileTombstone
    ) -> Bool {
        if profile.updatedAt > tombstone.updatedAt {
            return true
        }
        return profile.updatedAt == tombstone.updatedAt
            && tombstone.kind == .disable
            && profile.disabled
    }

    private static func isValidTombstone(_ tombstone: SkipProfileTombstone) -> Bool {
        EpisodeFingerprint.isValidIdentifier(tombstone.seriesID)
            && tombstone.updatedAt.timeIntervalSinceReferenceDate.isFinite
    }

    private static func validOperation(seriesID: String, date: Date) -> Bool {
        EpisodeFingerprint.isValidIdentifier(seriesID)
            && date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func defaultFingerprintFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Aiyifan", isDirectory: true)
            .appendingPathComponent(fingerprintFilename, isDirectory: false)
    }
}
