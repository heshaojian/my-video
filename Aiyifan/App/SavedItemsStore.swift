import Foundation

@MainActor
final class SavedItemsStore: ObservableObject {
    @Published private(set) var items: [AiyifanItem]
    @Published private(set) var newUpdateItemIDs: Set<String> = []
    @Published private(set) var lastDirectUpdateCheck: Date?

    private static let storageKey = "savedAiyifanItems"
    private static let metadataStorageKey = "savedAiyifanMetadata"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private var metadata: SavedItemsMetadata

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if ProcessInfo.processInfo.arguments.contains("-AiyifanResetSavedItems") {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.metadataStorageKey)
        }

        if let data = defaults.data(forKey: Self.storageKey),
           let decodedItems = try? JSONDecoder().decode([AiyifanItem].self, from: data) {
            items = decodedItems
        } else {
            items = []
        }

        if let data = defaults.data(forKey: Self.metadataStorageKey),
           let decoded = try? JSONDecoder().decode(SavedItemsMetadata.self, from: data) {
            metadata = decoded
        } else {
            metadata = SavedItemsMetadata()
        }
        lastDirectUpdateCheck = metadata.lastDirectUpdateCheck
        updateNewItemIDs()
    }

    func contains(_ item: AiyifanItem) -> Bool {
        items.contains { $0.id == item.id }
    }

    func toggle(_ item: AiyifanItem) {
        let updatedItems: [AiyifanItem]

        if contains(item) {
            updatedItems = items.filter { $0.id != item.id }
            metadata = metadata.removing(itemID: item.id)
        } else {
            updatedItems = [item] + items
        }

        items = updatedItems
        persist(updatedItems)
        persistMetadata()
        updateNewItemIDs()
    }

    @discardableResult
    func refreshUpdateMarkers(with feeds: [AiyifanCategory: [AiyifanItem]]) -> [AiyifanItem] {
        let refreshedItems = feeds.values.flatMap { $0 }
        var updatedMarkers = metadata.markers
        var updatedSeenMarkers = metadata.seenMarkers
        var changedItems: [AiyifanItem] = []

        for item in refreshedItems where contains(item) {
            let key = Self.updateKey(for: item)
            let previousKey = updatedMarkers[item.id]
            if previousKey == nil {
                updatedSeenMarkers[item.id] = key
            } else if previousKey != key, !key.isEmpty {
                changedItems.append(item)
            }
            updatedMarkers[item.id] = key
        }

        metadata = SavedItemsMetadata(
            markers: updatedMarkers,
            seenMarkers: updatedSeenMarkers,
            notificationPreferences: metadata.notificationPreferences,
            episodeMarkers: metadata.episodeMarkers,
            seenEpisodeMarkers: metadata.seenEpisodeMarkers,
            lastDirectUpdateCheck: metadata.lastDirectUpdateCheck
        )
        persistMetadata()
        updateNewItemIDs()
        return changedItems
    }

    func hasNewUpdate(_ item: AiyifanItem) -> Bool {
        newUpdateItemIDs.contains(item.id)
    }

    func markUpdateSeen(_ item: AiyifanItem) {
        var seenMarkers = metadata.seenMarkers
        if let marker = metadata.markers[item.id] {
            seenMarkers[item.id] = marker
        }
        var seenEpisodeMarkers = metadata.seenEpisodeMarkers
        if let marker = metadata.episodeMarkers[item.id] {
            seenEpisodeMarkers[item.id] = marker
        }
        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: seenMarkers,
            notificationPreferences: metadata.notificationPreferences,
            episodeMarkers: metadata.episodeMarkers,
            seenEpisodeMarkers: seenEpisodeMarkers,
            lastDirectUpdateCheck: metadata.lastDirectUpdateCheck
        )
        persistMetadata()
        updateNewItemIDs()
    }

    func notificationsEnabled(for item: AiyifanItem) -> Bool {
        metadata.notificationPreferences[item.id] ?? true
    }

    func checkedEpisodeKey(for item: AiyifanItem) -> String? {
        metadata.episodeMarkers[item.id]
    }

    func setNotificationsEnabled(_ enabled: Bool, for item: AiyifanItem) {
        var preferences = metadata.notificationPreferences
        preferences[item.id] = enabled
        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: metadata.seenMarkers,
            notificationPreferences: preferences,
            episodeMarkers: metadata.episodeMarkers,
            seenEpisodeMarkers: metadata.seenEpisodeMarkers,
            lastDirectUpdateCheck: metadata.lastDirectUpdateCheck
        )
        persistMetadata()
    }

    @discardableResult
    func recordEpisodeChecks(
        _ snapshots: [SavedEpisodeSnapshot],
        checkedAt: Date?
    ) -> [SavedEpisodeUpdate] {
        var episodeMarkers = metadata.episodeMarkers
        var seenEpisodeMarkers = metadata.seenEpisodeMarkers
        var updates: [SavedEpisodeUpdate] = []
        let savedByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for snapshot in snapshots {
            guard let item = savedByID[snapshot.itemID] else { continue }
            let key = snapshot.episode.mediaKey
            guard !key.isEmpty else { continue }
            if let previous = episodeMarkers[item.id] {
                if previous != key {
                    updates.append(SavedEpisodeUpdate(item: item, episode: snapshot.episode))
                }
            } else {
                seenEpisodeMarkers[item.id] = key
            }
            episodeMarkers[item.id] = key
        }

        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: metadata.seenMarkers,
            notificationPreferences: metadata.notificationPreferences,
            episodeMarkers: episodeMarkers,
            seenEpisodeMarkers: seenEpisodeMarkers,
            lastDirectUpdateCheck: checkedAt ?? metadata.lastDirectUpdateCheck
        )
        lastDirectUpdateCheck = metadata.lastDirectUpdateCheck
        persistMetadata()
        updateNewItemIDs()
        return updates
    }

    func mergeFromCloud(_ cloudItems: [AiyifanItem]) {
        let merged = (items + cloudItems).reduce(into: [AiyifanItem]()) { result, item in
            if !result.contains(where: { $0.id == item.id }) {
                result.append(item)
            }
        }
        items = merged
        persist(merged)
        updateNewItemIDs()
    }

    private func persist(_ items: [AiyifanItem]) {
        guard let data = try? encoder.encode(items) else {
            return
        }

        defaults.set(data, forKey: Self.storageKey)
    }

    private func persistMetadata() {
        guard let data = try? encoder.encode(metadata) else {
            return
        }
        defaults.set(data, forKey: Self.metadataStorageKey)
    }

    private func updateNewItemIDs() {
        let savedIDs = Set(items.map(\.id))
        newUpdateItemIDs = Set(savedIDs.filter { itemID in
            let feedChanged = metadata.markers[itemID].map { metadata.seenMarkers[itemID] != $0 } ?? false
            let episodeChanged = metadata.episodeMarkers[itemID].map {
                metadata.seenEpisodeMarkers[itemID] != $0
            } ?? false
            return feedChanged || episodeChanged
        })
    }

    private static func updateKey(for item: AiyifanItem) -> String {
        [item.subTitle, item.addTime]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }
}

private struct SavedItemsMetadata: Codable {
    let markers: [String: String]
    let seenMarkers: [String: String]
    let notificationPreferences: [String: Bool]
    let episodeMarkers: [String: String]
    let seenEpisodeMarkers: [String: String]
    let lastDirectUpdateCheck: Date?

    init(
        markers: [String: String] = [:],
        seenMarkers: [String: String] = [:],
        notificationPreferences: [String: Bool] = [:],
        episodeMarkers: [String: String] = [:],
        seenEpisodeMarkers: [String: String] = [:],
        lastDirectUpdateCheck: Date? = nil
    ) {
        self.markers = markers
        self.seenMarkers = seenMarkers
        self.notificationPreferences = notificationPreferences
        self.episodeMarkers = episodeMarkers
        self.seenEpisodeMarkers = seenEpisodeMarkers
        self.lastDirectUpdateCheck = lastDirectUpdateCheck
    }

    func removing(itemID: String) -> SavedItemsMetadata {
        SavedItemsMetadata(
            markers: markers.filter { $0.key != itemID },
            seenMarkers: seenMarkers.filter { $0.key != itemID },
            notificationPreferences: notificationPreferences.filter { $0.key != itemID },
            episodeMarkers: episodeMarkers.filter { $0.key != itemID },
            seenEpisodeMarkers: seenEpisodeMarkers.filter { $0.key != itemID },
            lastDirectUpdateCheck: lastDirectUpdateCheck
        )
    }

    private enum CodingKeys: String, CodingKey {
        case markers
        case seenMarkers
        case notificationPreferences
        case episodeMarkers
        case seenEpisodeMarkers
        case lastDirectUpdateCheck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markers = try container.decodeIfPresent([String: String].self, forKey: .markers) ?? [:]
        seenMarkers = try container.decodeIfPresent([String: String].self, forKey: .seenMarkers) ?? [:]
        notificationPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .notificationPreferences) ?? [:]
        episodeMarkers = try container.decodeIfPresent([String: String].self, forKey: .episodeMarkers) ?? [:]
        seenEpisodeMarkers = try container.decodeIfPresent([String: String].self, forKey: .seenEpisodeMarkers) ?? [:]
        lastDirectUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastDirectUpdateCheck)
    }
}
