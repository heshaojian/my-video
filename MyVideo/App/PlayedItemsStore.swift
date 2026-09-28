import Foundation

enum PlayedPositionFormatter {
    static func label(position: Double, duration: Double) -> String {
        "Paused at \(time(position)) / \(time(duration))"
    }

    private static func time(_ value: Double) -> String {
        let totalSeconds = value.isFinite ? max(0, Int(value.rounded(.down))) : 0
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct PlayedRecord: Codable, Equatable, Identifiable, Sendable {
    let item: MyVideoItem
    let episodeKey: String?
    let episodeTitle: String?
    let position: Double
    let duration: Double
    let lastPlayedAt: Date
    var completionOverride: Bool? = nil

    var id: String {
        "\(item.id)::\(episodeKey ?? "movie")"
    }

    var isCompleted: Bool {
        if let completionOverride {
            return completionOverride
        }
        return duration > 0 && position / duration >= 0.9
    }

    var resumePosition: Double {
        guard !isCompleted else {
            return 0
        }
        guard duration > 0 else {
            return max(0, position)
        }
        return min(max(0, position), duration)
    }
}

@MainActor
final class PlayedItemsStore: ObservableObject {
    @Published private(set) var items: [PlayedRecord]

    static let storageKey = "playedMyVideoItems"
    private static let storageVersion = 1

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if ProcessInfo.processInfo.arguments.contains("-MyVideoResetPlayedItems") {
            defaults.removeObject(forKey: Self.storageKey)
        }

        items = Self.restore(from: defaults, decoder: decoder)

        if ProcessInfo.processInfo.arguments.contains("-MyVideoSeedPlayedItems") {
            let item = MyVideoItem(listPath: "fixture-drama", title: "Fixture Series", isSerial: true)
            let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
            record(item: item, episode: episode, position: 40, duration: 100)
        }
    }

    func record(
        item: MyVideoItem,
        episode: Episode?,
        position: Double,
        duration: Double,
        playedAt: Date = Date()
    ) {
        let record = PlayedRecord(
            item: item,
            episodeKey: episode?.mediaKey,
            episodeTitle: EpisodeDisplayLabel.sanitized(
                episode?.title,
                excluding: episode.map { [$0.mediaKey] } ?? []
            ),
            position: position.isFinite ? position : 0,
            duration: duration.isFinite ? duration : 0,
            lastPlayedAt: playedAt
        )
        let updatedItems = ([record] + items.filter { $0.id != record.id })
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        replace(with: updatedItems)
    }

    func record(for item: MyVideoItem, episodeKey: String?) -> PlayedRecord? {
        let id = "\(item.id)::\(episodeKey ?? "movie")"
        return items.first { $0.id == id }
    }

    func remove(_ record: PlayedRecord) {
        replace(with: items.filter { $0.id != record.id })
    }

    func removeAll() {
        replace(with: [])
    }

    func markWatched(_ record: PlayedRecord) {
        replaceRecord(record, position: record.duration, completionOverride: true)
    }

    func markWatched(
        item: MyVideoItem,
        episode: Episode?,
        playedAt: Date = Date()
    ) {
        markWatched(
            item: item,
            episodeKey: episode?.mediaKey,
            episodeTitle: episode?.title,
            playedAt: playedAt
        )
    }

    func markWatched(
        item: MyVideoItem,
        episodeKey: String?,
        episodeTitle: String?,
        playedAt: Date = Date()
    ) {
        let record = PlayedRecord(
            item: item,
            episodeKey: episodeKey,
            episodeTitle: EpisodeDisplayLabel.sanitized(
                episodeTitle,
                excluding: episodeKey.map { [$0] } ?? []
            ),
            position: 0,
            duration: 0,
            lastPlayedAt: playedAt,
            completionOverride: true
        )
        replace(with: ([record] + items.filter { $0.id != record.id })
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt })
    }

    func markUnwatched(_ record: PlayedRecord) {
        replaceRecord(record, position: 0, completionOverride: nil)
    }

    func restart(_ record: PlayedRecord) {
        replaceRecord(record, position: 0, completionOverride: nil)
    }

    func removeAll(for item: MyVideoItem) {
        replace(with: items.filter { $0.item.id != item.id })
    }

    func mergeFromCloud(_ cloudItems: [PlayedRecord]) {
        let merged = CloudLibraryMerger.merge(
            local: CloudLibraryPayload(savedItems: [], playedItems: items),
            cloud: CloudLibraryPayload(savedItems: [], playedItems: cloudItems)
        )
        replace(with: merged.playedItems)
    }

    private func replaceRecord(
        _ record: PlayedRecord,
        position: Double,
        completionOverride: Bool?
    ) {
        let updated = PlayedRecord(
            item: record.item,
            episodeKey: record.episodeKey,
            episodeTitle: record.episodeTitle,
            position: position,
            duration: record.duration,
            lastPlayedAt: Date(),
            completionOverride: completionOverride
        )
        replace(with: ([updated] + items.filter { $0.id != record.id })
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt })
    }

    private func replace(with updatedItems: [PlayedRecord]) {
        items = updatedItems
        persist(updatedItems)
    }

    private func persist(_ records: [PlayedRecord]) {
        let recordObjects = records.compactMap { record -> Any? in
            guard
                let data = try? encoder.encode(record),
                let object = try? JSONSerialization.jsonObject(with: data)
            else {
                return nil
            }
            return object
        }
        let envelope: [String: Any] = [
            "version": Self.storageVersion,
            "records": recordObjects
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func restore(from defaults: UserDefaults, decoder: JSONDecoder) -> [PlayedRecord] {
        guard
            let data = defaults.data(forKey: storageKey),
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = envelope["version"] as? Int,
            version == storageVersion,
            let rawRecords = envelope["records"] as? [Any]
        else {
            return []
        }

        return rawRecords.compactMap { object in
            guard
                JSONSerialization.isValidJSONObject(object),
                let data = try? JSONSerialization.data(withJSONObject: object),
                let record = try? decoder.decode(PlayedRecord.self, from: data)
            else {
                return nil
            }
            return record
        }
        .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }
}
