import Foundation

enum ReadyToWatchSource: String, Codable, Equatable, Sendable {
    case manual
    case newEpisode
    case incomplete
}

struct ReadyToWatchUpdate: Codable, Equatable, Sendable {
    let itemID: String
    let episode: Episode
    let detectedAt: Date
}

struct ReadyToWatchEntry: Equatable, Identifiable, Sendable {
    let item: MyVideoItem
    let episodeKey: String?
    let episodeTitle: String?
    let source: ReadyToWatchSource
    let isNew: Bool
    let resumePosition: Double?
    let duration: Double?

    var id: String {
        item.id
    }
}

enum ReadyToWatchProjector {
    static func project(
        savedItems: [MyVideoItem],
        updates: [ReadyToWatchUpdate],
        playedRecords: [PlayedRecord],
        overrides: ReadyToWatchOverrides
    ) -> [ReadyToWatchEntry] {
        let savedByID = validSavedItems(savedItems)
        let normalizedOverrides = ReadyToWatchOverrides().merging(overrides)
        let updatesByTitle = newestUpdates(updates, savedByID: savedByID)
        let playedByTitle = newestIncompleteRecords(playedRecords, savedByID: savedByID)
        let pins = normalizedOverrides.pins
            .filter { savedByID[$0.titleID] != nil }
            .sorted(by: pinOrder)
        let pinnedTitleIDs = Set(pins.map(\.titleID))

        let manualEntries = pins.compactMap { pin -> ReadyToWatchEntry? in
            guard let item = savedByID[pin.titleID] else { return nil }
            let episodeKey = normalizedEpisodeKey(pin.episodeKey)
            let matchingUpdate = updatesByTitle[item.id].flatMap {
                normalizedEpisodeKey($0.episode.mediaKey) == episodeKey ? $0 : nil
            }
            let matchingRecord = newestMatchingRecord(
                in: playedRecords,
                item: item,
                episodeKey: episodeKey
            )
            return ReadyToWatchEntry(
                item: item,
                episodeKey: episodeKey,
                episodeTitle: matchingUpdate?.episode.title ?? matchingRecord?.episodeTitle,
                source: .manual,
                isNew: matchingUpdate != nil,
                resumePosition: validResumePosition(matchingRecord),
                duration: validDuration(matchingRecord)
            )
        }

        let automaticEntries = savedByID.values.compactMap { item -> RankedEntry? in
            guard !pinnedTitleIDs.contains(item.id) else { return nil }

            if let record = playedByTitle[item.id],
               !isDismissed(
                titleID: item.id,
                episodeKey: normalizedEpisodeKey(record.episodeKey),
                dismissals: normalizedOverrides.dismissals
               ) {
                return RankedEntry(
                    entry: ReadyToWatchEntry(
                        item: item,
                        episodeKey: normalizedEpisodeKey(record.episodeKey),
                        episodeTitle: normalizedText(record.episodeTitle),
                        source: .incomplete,
                        isNew: false,
                        resumePosition: record.resumePosition,
                        duration: record.duration
                    ),
                    date: record.lastPlayedAt
                )
            }

            if let update = updatesByTitle[item.id] {
                let episodeKey = normalizedEpisodeKey(update.episode.mediaKey)
                guard !isDismissed(
                    titleID: item.id,
                    episodeKey: episodeKey,
                    dismissals: normalizedOverrides.dismissals
                ) else {
                    return nil
                }
                return RankedEntry(
                    entry: ReadyToWatchEntry(
                        item: item,
                        episodeKey: episodeKey,
                        episodeTitle: normalizedText(update.episode.title),
                        source: .newEpisode,
                        isNew: true,
                        resumePosition: nil,
                        duration: nil
                    ),
                    date: update.detectedAt
                )
            }

            return nil
        }
        .sorted(by: automaticOrder)
        .map(\.entry)

        return manualEntries + automaticEntries
    }

    private struct RankedEntry {
        let entry: ReadyToWatchEntry
        let date: Date
    }

    private static func validSavedItems(_ items: [MyVideoItem]) -> [String: MyVideoItem] {
        items.reduce(into: [:]) { result, item in
            let itemID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemID.isEmpty, itemID == item.id, result[itemID] == nil else { return }
            result[itemID] = item
        }
    }

    private static func newestUpdates(
        _ updates: [ReadyToWatchUpdate],
        savedByID: [String: MyVideoItem]
    ) -> [String: ReadyToWatchUpdate] {
        updates.reduce(into: [:]) { result, update in
            guard
                savedByID[update.itemID] != nil,
                normalizedEpisodeKey(update.episode.mediaKey) != nil,
                update.detectedAt.timeIntervalSinceReferenceDate.isFinite
            else {
                return
            }
            guard let current = result[update.itemID] else {
                result[update.itemID] = update
                return
            }
            if update.detectedAt > current.detectedAt ||
                (update.detectedAt == current.detectedAt && update.episode.mediaKey < current.episode.mediaKey) {
                result[update.itemID] = update
            }
        }
    }

    private static func newestIncompleteRecords(
        _ records: [PlayedRecord],
        savedByID: [String: MyVideoItem]
    ) -> [String: PlayedRecord] {
        records.reduce(into: [:]) { result, record in
            guard let savedItem = savedByID[record.item.id], isValidIncomplete(record, item: savedItem) else {
                return
            }
            guard let current = result[savedItem.id] else {
                result[savedItem.id] = record
                return
            }
            if record.lastPlayedAt > current.lastPlayedAt ||
                (record.lastPlayedAt == current.lastPlayedAt && record.id < current.id) {
                result[savedItem.id] = record
            }
        }
    }

    private static func isValidIncomplete(_ record: PlayedRecord, item: MyVideoItem) -> Bool {
        guard
            record.position.isFinite,
            record.position > 0,
            record.duration.isFinite,
            record.duration > 0,
            record.lastPlayedAt.timeIntervalSinceReferenceDate.isFinite,
            !record.isCompleted
        else {
            return false
        }
        return item.isSerial != true || normalizedEpisodeKey(record.episodeKey) != nil
    }

    private static func isDismissed(
        titleID: String,
        episodeKey: String?,
        dismissals: [ReadyDismissal]
    ) -> Bool {
        dismissals.contains {
            $0.titleID == titleID && normalizedEpisodeKey($0.episodeKey) == episodeKey
        }
    }

    private static func newestMatchingRecord(
        in records: [PlayedRecord],
        item: MyVideoItem,
        episodeKey: String?
    ) -> PlayedRecord? {
        records
            .filter {
                $0.item.id == item.id &&
                    normalizedEpisodeKey($0.episodeKey) == episodeKey &&
                    isValidIncomplete($0, item: item)
            }
            .sorted {
                if $0.lastPlayedAt != $1.lastPlayedAt { return $0.lastPlayedAt > $1.lastPlayedAt }
                return $0.id < $1.id
            }
            .first
    }

    private static func pinOrder(_ lhs: ReadyPin, _ rhs: ReadyPin) -> Bool {
        if lhs.orderToken != rhs.orderToken {
            return lhs.orderToken < rhs.orderToken
        }
        return lhs.titleID < rhs.titleID
    }

    private static func automaticOrder(_ lhs: RankedEntry, _ rhs: RankedEntry) -> Bool {
        let lhsRank = sourceRank(lhs.entry.source)
        let rhsRank = sourceRank(rhs.entry.source)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.entry.item.id < rhs.entry.item.id
    }

    private static func sourceRank(_ source: ReadyToWatchSource) -> Int {
        switch source {
        case .manual: 0
        case .newEpisode: 1
        case .incomplete: 2
        }
    }

    private static func normalizedEpisodeKey(_ value: String?) -> String? {
        normalizedText(value)
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validResumePosition(_ record: PlayedRecord?) -> Double? {
        guard let record, isValidIncomplete(record, item: record.item) else { return nil }
        return record.resumePosition
    }

    private static func validDuration(_ record: PlayedRecord?) -> Double? {
        guard let record, isValidIncomplete(record, item: record.item) else { return nil }
        return record.duration
    }
}
