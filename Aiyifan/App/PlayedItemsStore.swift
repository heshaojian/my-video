import Foundation

struct PlayedRecord: Codable, Equatable, Identifiable, Sendable {
    let item: AiyifanItem
    let episodeKey: String?
    let episodeTitle: String?
    let position: Double
    let duration: Double
    let lastPlayedAt: Date

    var id: String {
        "\(item.id)::\(episodeKey ?? "movie")"
    }

    var isCompleted: Bool {
        duration > 0 && position / duration >= 0.9
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

    static let storageKey = "playedAiyifanItems"
    private static let storageVersion = 1

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if ProcessInfo.processInfo.arguments.contains("-AiyifanResetPlayedItems") {
            defaults.removeObject(forKey: Self.storageKey)
        }

        items = Self.restore(from: defaults, decoder: decoder)

        if ProcessInfo.processInfo.arguments.contains("-AiyifanSeedPlayedItems") {
            let item = AiyifanItem(listPath: "fixture-电视剧", title: "Fixture 电视剧")
            let episode = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
            record(item: item, episode: episode, position: 40, duration: 100)
        }
    }

    func record(
        item: AiyifanItem,
        episode: Episode?,
        position: Double,
        duration: Double,
        playedAt: Date = Date()
    ) {
        let record = PlayedRecord(
            item: item,
            episodeKey: episode?.mediaKey,
            episodeTitle: episode?.title,
            position: position.isFinite ? position : 0,
            duration: duration.isFinite ? duration : 0,
            lastPlayedAt: playedAt
        )
        let updatedItems = ([record] + items.filter { $0.id != record.id })
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        replace(with: updatedItems)
    }

    func record(for item: AiyifanItem, episodeKey: String?) -> PlayedRecord? {
        let id = "\(item.id)::\(episodeKey ?? "movie")"
        return items.first { $0.id == id }
    }

    func remove(_ record: PlayedRecord) {
        replace(with: items.filter { $0.id != record.id })
    }

    func removeAll() {
        replace(with: [])
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
