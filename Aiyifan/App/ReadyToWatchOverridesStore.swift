import Foundation

struct ReadyPin: Codable, Equatable, Sendable {
    let titleID: String
    let episodeKey: String?
    let orderToken: String
    let modifiedAt: Date
}

struct ReadyDismissal: Codable, Equatable, Sendable {
    let titleID: String
    let episodeKey: String?
    let modifiedAt: Date
}

enum ReadyOverrideKind: String, Codable, Equatable, Hashable, Sendable {
    case pin
    case dismissal
}

struct ReadyOverrideTombstone: Codable, Equatable, Sendable {
    let kind: ReadyOverrideKind
    let titleID: String
    let episodeKey: String?
    let modifiedAt: Date
}

struct ReadyToWatchOverrides: Codable, Equatable, Sendable {
    fileprivate static let maximumOrderRank = 1_000_000
    fileprivate static let maximumOrderSuffixLength = 128
    let pins: [ReadyPin]
    let dismissals: [ReadyDismissal]
    let tombstones: [ReadyOverrideTombstone]

    init(
        pins: [ReadyPin] = [],
        dismissals: [ReadyDismissal] = [],
        tombstones: [ReadyOverrideTombstone] = []
    ) {
        self.pins = pins
        self.dismissals = dismissals
        self.tombstones = tombstones
    }

    func merging(_ other: ReadyToWatchOverrides) -> ReadyToWatchOverrides {
        let pinOperations = (pins + other.pins).map(OverrideOperation.pin)
            + (tombstones + other.tombstones)
                .filter { $0.kind == .pin }
                .map(OverrideOperation.tombstone)
        let dismissalOperations = (dismissals + other.dismissals).map(OverrideOperation.dismissal)
            + (tombstones + other.tombstones)
                .filter { $0.kind == .dismissal }
                .map(OverrideOperation.tombstone)
        let pinWinners = Self.winners(from: pinOperations)
        let dismissalWinners = Self.winners(from: dismissalOperations)

        let mergedPins = pinWinners.compactMap(\.pin).sorted {
            if $0.orderToken != $1.orderToken { return $0.orderToken < $1.orderToken }
            return $0.titleID < $1.titleID
        }
        let mergedDismissals = dismissalWinners.compactMap(\.dismissal).sorted {
            Self.identity(for: $0) < Self.identity(for: $1)
        }
        let mergedTombstones = (pinWinners + dismissalWinners).compactMap(\.tombstone).sorted {
            Self.identity(for: $0) < Self.identity(for: $1)
        }
        return ReadyToWatchOverrides(
            pins: mergedPins,
            dismissals: mergedDismissals,
            tombstones: mergedTombstones
        )
    }

    private enum OverrideOperation {
        case pin(ReadyPin)
        case dismissal(ReadyDismissal)
        case tombstone(ReadyOverrideTombstone)

        var identity: String {
            switch self {
            case let .pin(pin):
                "pin|\(pin.titleID)"
            case let .dismissal(dismissal):
                ReadyToWatchOverrides.identity(for: dismissal)
            case let .tombstone(tombstone):
                ReadyToWatchOverrides.identity(for: tombstone)
            }
        }

        var modifiedAt: Date {
            switch self {
            case let .pin(pin): pin.modifiedAt
            case let .dismissal(dismissal): dismissal.modifiedAt
            case let .tombstone(tombstone): tombstone.modifiedAt
            }
        }

        var stableTieBreak: String {
            switch self {
            case let .pin(pin):
                "active|\(pin.orderToken)|\(pin.episodeKey ?? "")"
            case let .dismissal(dismissal):
                "active|\(dismissal.episodeKey ?? "")"
            case .tombstone:
                "tombstone"
            }
        }

        var pin: ReadyPin? {
            guard case let .pin(value) = self else { return nil }
            return value
        }

        var dismissal: ReadyDismissal? {
            guard case let .dismissal(value) = self else { return nil }
            return value
        }

        var tombstone: ReadyOverrideTombstone? {
            guard case let .tombstone(value) = self else { return nil }
            return value
        }
    }

    private static func winners(from operations: [OverrideOperation]) -> [OverrideOperation] {
        let winners = operations.reduce(into: [String: OverrideOperation]()) { result, operation in
            guard isValid(operation) else { return }
            guard let current = result[operation.identity] else {
                result[operation.identity] = operation
                return
            }
            if operation.modifiedAt > current.modifiedAt ||
                (operation.modifiedAt == current.modifiedAt && operation.stableTieBreak > current.stableTieBreak) {
                result[operation.identity] = operation
            }
        }
        return winners.values.sorted { $0.identity < $1.identity }
    }

    private static func isValid(_ operation: OverrideOperation) -> Bool {
        let titleID: String
        let episodeKey: String?
        let orderToken: String?
        switch operation {
        case let .pin(pin):
            titleID = pin.titleID
            episodeKey = pin.episodeKey
            orderToken = pin.orderToken
        case let .dismissal(dismissal):
            titleID = dismissal.titleID
            episodeKey = dismissal.episodeKey
            orderToken = nil
        case let .tombstone(tombstone):
            titleID = tombstone.titleID
            episodeKey = tombstone.episodeKey
            orderToken = nil
        }
        guard
            !titleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            operation.modifiedAt.timeIntervalSinceReferenceDate.isFinite
        else {
            return false
        }
        if let episodeKey, episodeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if let orderToken {
            guard isValidOrderToken(orderToken) else { return false }
        }
        return true
    }

    private static func isValidOrderToken(_ token: String) -> Bool {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            !parts[0].isEmpty,
            parts[0].count <= 8,
            parts[0].allSatisfy(\.isNumber),
            let rank = Int(parts[0]),
            (0...maximumOrderRank).contains(rank),
            !parts[1].isEmpty,
            parts[1].utf8.count <= maximumOrderSuffixLength,
            parts[1].unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            return false
        }
        return true
    }

    private static func identity(for dismissal: ReadyDismissal) -> String {
        "dismissal|\(dismissal.titleID)|\(dismissal.episodeKey ?? "<title>")"
    }

    private static func identity(for tombstone: ReadyOverrideTombstone) -> String {
        if tombstone.kind == .pin {
            return "pin|\(tombstone.titleID)"
        }
        return "dismissal|\(tombstone.titleID)|\(tombstone.episodeKey ?? "<title>")"
    }
}

struct ReadyToWatchOverridesPersistence {
    let load: () -> Data?
    let save: (Data) throws -> Void

    static func userDefaults(_ defaults: UserDefaults) -> ReadyToWatchOverridesPersistence {
        ReadyToWatchOverridesPersistence(
            load: { defaults.data(forKey: ReadyToWatchOverridesStore.storageKey) },
            save: { defaults.set($0, forKey: ReadyToWatchOverridesStore.storageKey) }
        )
    }
}

@MainActor
final class ReadyToWatchOverridesStore: ObservableObject {
    @Published private(set) var overrides: ReadyToWatchOverrides
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var hasPendingPersistence = false

    nonisolated static let storageKey = "aiyifanReadyToWatchOverrides"
    private static let storageVersion = 1

    private let persistence: ReadyToWatchOverridesPersistence
    private let tokenGenerator: () -> String
    private let encoder = JSONEncoder()

    init(
        defaults: UserDefaults = .standard,
        tokenGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        if ProcessInfo.processInfo.arguments.contains("-AiyifanResetSavedItems") {
            defaults.removeObject(forKey: Self.storageKey)
        }
        self.persistence = .userDefaults(defaults)
        self.tokenGenerator = tokenGenerator
        self.overrides = Self.restore(from: persistence.load())
    }

    init(
        persistence: ReadyToWatchOverridesPersistence,
        tokenGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.persistence = persistence
        self.tokenGenerator = tokenGenerator
        self.overrides = Self.restore(from: persistence.load())
    }

    func pin(titleID: String, episodeKey: String?, at date: Date = Date()) {
        guard let titleID = Self.normalized(titleID), let date = Self.valid(date) else { return }
        let episodeKey = Self.normalized(episodeKey)
        if let existing = overrides.pins.first(where: { $0.titleID == titleID }),
           existing.episodeKey == episodeKey {
            return
        }
        let suffix = tokenGenerator()
        guard let tokenSuffix = Self.validOrderSuffix(suffix) else { return }
        let currentMaximumRank = overrides.pins.compactMap { Self.rank(from: $0.orderToken) }.max() ?? -1
        guard currentMaximumRank < ReadyToWatchOverrides.maximumOrderRank else { return }
        let rank = currentMaximumRank + 1
        let pin = ReadyPin(
            titleID: titleID,
            episodeKey: episodeKey,
            orderToken: Self.orderToken(rank: rank, suffix: tokenSuffix),
            modifiedAt: date
        )
        let updated = ReadyToWatchOverrides(
            pins: [pin] + overrides.pins.filter { $0.titleID != titleID },
            dismissals: overrides.dismissals,
            tombstones: overrides.tombstones
        )
        replace(with: ReadyToWatchOverrides().merging(updated))
    }

    func unpin(titleID: String, at date: Date = Date()) {
        guard let titleID = Self.normalized(titleID), let date = Self.valid(date) else { return }
        let tombstone = ReadyOverrideTombstone(
            kind: .pin,
            titleID: titleID,
            episodeKey: nil,
            modifiedAt: date
        )
        let updated = ReadyToWatchOverrides(
            pins: overrides.pins,
            dismissals: overrides.dismissals,
            tombstones: [tombstone] + overrides.tombstones
        )
        replace(with: ReadyToWatchOverrides().merging(updated))
    }

    func dismiss(titleID: String, episodeKey: String?, at date: Date = Date()) {
        guard let titleID = Self.normalized(titleID), let date = Self.valid(date) else { return }
        let episodeKey = Self.normalized(episodeKey)
        let dismissal = ReadyDismissal(titleID: titleID, episodeKey: episodeKey, modifiedAt: date)
        let updated = ReadyToWatchOverrides(
            pins: overrides.pins,
            dismissals: [dismissal] + overrides.dismissals,
            tombstones: overrides.tombstones
        )
        replace(with: ReadyToWatchOverrides().merging(updated))
    }

    func reorder(titleIDs: [String], at date: Date = Date()) {
        guard let date = Self.valid(date) else { return }
        let requested = titleIDs.compactMap(Self.normalized).reduce(into: [String]()) { result, titleID in
            if !result.contains(titleID) { result.append(titleID) }
        }
        let pinsByTitle = Dictionary(uniqueKeysWithValues: overrides.pins.map { ($0.titleID, $0) })
        let orderedIDs = requested.filter { pinsByTitle[$0] != nil }
            + overrides.pins.map(\.titleID).filter { !requested.contains($0) }
        guard orderedIDs != overrides.pins.map(\.titleID) else { return }
        let reordered = orderedIDs.enumerated().compactMap { index, titleID -> ReadyPin? in
            guard let pin = pinsByTitle[titleID] else { return nil }
            return ReadyPin(
                titleID: pin.titleID,
                episodeKey: pin.episodeKey,
                orderToken: Self.orderToken(rank: index, suffix: Self.suffix(from: pin.orderToken)),
                modifiedAt: date
            )
        }
        replace(with: ReadyToWatchOverrides(
            pins: reordered,
            dismissals: overrides.dismissals,
            tombstones: overrides.tombstones
        ))
    }

    func prune(savedTitleIDs: Set<String>, at date: Date = Date()) {
        guard let date = Self.valid(date) else { return }
        let saved = Set(savedTitleIDs.compactMap(Self.normalized))
        let removedPins = overrides.pins.filter { !saved.contains($0.titleID) }
        let removedDismissals = overrides.dismissals.filter { !saved.contains($0.titleID) }
        guard !removedPins.isEmpty || !removedDismissals.isEmpty else { return }
        let tombstones = removedPins.map {
            ReadyOverrideTombstone(kind: .pin, titleID: $0.titleID, episodeKey: nil, modifiedAt: date)
        } + removedDismissals.map {
            ReadyOverrideTombstone(
                kind: .dismissal,
                titleID: $0.titleID,
                episodeKey: $0.episodeKey,
                modifiedAt: date
            )
        }
        let updated = ReadyToWatchOverrides(
            pins: overrides.pins.filter { saved.contains($0.titleID) },
            dismissals: overrides.dismissals.filter { saved.contains($0.titleID) },
            tombstones: tombstones + overrides.tombstones
        )
        replace(with: ReadyToWatchOverrides().merging(updated))
    }

    func merge(_ incoming: ReadyToWatchOverrides) {
        replace(with: overrides.merging(incoming))
    }

    @discardableResult
    func retryPersistence() -> Bool {
        persist(overrides)
    }

    private struct Envelope: Codable {
        let version: Int
        let overrides: ReadyToWatchOverrides
    }

    private func replace(with updated: ReadyToWatchOverrides) {
        overrides = updated
        persist(updated)
    }

    @discardableResult
    private func persist(_ value: ReadyToWatchOverrides) -> Bool {
        do {
            let data = try encoder.encode(Envelope(version: Self.storageVersion, overrides: value))
            try persistence.save(data)
            hasPendingPersistence = false
            persistenceErrorMessage = nil
            return true
        } catch {
            hasPendingPersistence = true
            persistenceErrorMessage = "Ready to Watch changes could not be saved. Retry."
            return false
        }
    }

    private static func restore(from data: Data?) -> ReadyToWatchOverrides {
        guard
            let data,
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            envelope.version == storageVersion
        else {
            return ReadyToWatchOverrides()
        }
        return ReadyToWatchOverrides().merging(envelope.overrides)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validOrderSuffix(_ value: String) -> String? {
        guard
            let normalized = normalized(value),
            normalized.utf8.count <= ReadyToWatchOverrides.maximumOrderSuffixLength,
            normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            return nil
        }
        return normalized
    }

    private static func valid(_ date: Date) -> Date? {
        date.timeIntervalSinceReferenceDate.isFinite ? date : nil
    }

    private static func orderToken(rank: Int, suffix: String) -> String {
        String(format: "%08d:%@", rank, suffix)
    }

    private static func rank(from token: String) -> Int? {
        Int(token.split(separator: ":", maxSplits: 1).first ?? "")
    }

    private static func suffix(from token: String) -> String {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[1]) : token
    }
}
