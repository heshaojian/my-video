import Foundation

@MainActor
final class SavedItemsStore: ObservableObject {
    @Published private(set) var items: [AiyifanItem]
    @Published private(set) var newUpdateItemIDs: Set<String> = []

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
            notificationPreferences: metadata.notificationPreferences
        )
        persistMetadata()
        updateNewItemIDs()
        return changedItems
    }

    func hasNewUpdate(_ item: AiyifanItem) -> Bool {
        newUpdateItemIDs.contains(item.id)
    }

    func markUpdateSeen(_ item: AiyifanItem) {
        guard let marker = metadata.markers[item.id] else {
            return
        }
        var seenMarkers = metadata.seenMarkers
        seenMarkers[item.id] = marker
        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: seenMarkers,
            notificationPreferences: metadata.notificationPreferences
        )
        persistMetadata()
        updateNewItemIDs()
    }

    func notificationsEnabled(for item: AiyifanItem) -> Bool {
        metadata.notificationPreferences[item.id] ?? true
    }

    func setNotificationsEnabled(_ enabled: Bool, for item: AiyifanItem) {
        var preferences = metadata.notificationPreferences
        preferences[item.id] = enabled
        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: metadata.seenMarkers,
            notificationPreferences: preferences
        )
        persistMetadata()
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
            guard let marker = metadata.markers[itemID] else {
                return false
            }
            return metadata.seenMarkers[itemID] != marker
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

    init(
        markers: [String: String] = [:],
        seenMarkers: [String: String] = [:],
        notificationPreferences: [String: Bool] = [:]
    ) {
        self.markers = markers
        self.seenMarkers = seenMarkers
        self.notificationPreferences = notificationPreferences
    }

    func removing(itemID: String) -> SavedItemsMetadata {
        SavedItemsMetadata(
            markers: markers.filter { $0.key != itemID },
            seenMarkers: seenMarkers.filter { $0.key != itemID },
            notificationPreferences: notificationPreferences.filter { $0.key != itemID }
        )
    }
}
