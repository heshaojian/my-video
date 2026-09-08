import Foundation

struct SavedEpisodeUpdateState: Codable, Equatable, Sendable {
    static let maximumEpisodeCount = 100

    let episodes: [EpisodeSelection]
    let latestEpisodeKey: String
    let seenEpisodeKey: String?
    let detectedAt: Date?
    let lastObservedAt: Date?

    init(
        episodes: [EpisodeSelection],
        latestEpisodeKey: String,
        seenEpisodeKey: String?,
        detectedAt: Date?,
        lastObservedAt: Date?
    ) {
        var retainedEpisodes: [EpisodeSelection] = []
        var retainedKeys: Set<String> = []
        for episode in episodes {
            let key = episode.mediaKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, retainedKeys.insert(key).inserted else { continue }
            retainedEpisodes.append(EpisodeSelection(mediaKey: key, title: title.isEmpty ? key : title))
            if retainedEpisodes.count == Self.maximumEpisodeCount { break }
        }

        self.episodes = retainedEpisodes
        let normalizedLatestKey = latestEpisodeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latestEpisodeKey = normalizedLatestKey.isEmpty
            ? retainedEpisodes.first?.mediaKey ?? ""
            : normalizedLatestKey
        self.seenEpisodeKey = seenEpisodeKey?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.detectedAt = detectedAt
        self.lastObservedAt = lastObservedAt
    }

    func markingLatestSeen() -> SavedEpisodeUpdateState {
        SavedEpisodeUpdateState(
            episodes: episodes,
            latestEpisodeKey: latestEpisodeKey,
            seenEpisodeKey: latestEpisodeKey,
            detectedAt: detectedAt,
            lastObservedAt: lastObservedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case episodes
        case latestEpisodeKey
        case seenEpisodeKey
        case detectedAt
        case lastObservedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            episodes: try container.decodeIfPresent([EpisodeSelection].self, forKey: .episodes) ?? [],
            latestEpisodeKey: try container.decodeIfPresent(String.self, forKey: .latestEpisodeKey) ?? "",
            seenEpisodeKey: try container.decodeIfPresent(String.self, forKey: .seenEpisodeKey),
            detectedAt: try container.decodeIfPresent(Date.self, forKey: .detectedAt),
            lastObservedAt: try container.decodeIfPresent(Date.self, forKey: .lastObservedAt)
        )
    }
}

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
            items = Self.sanitizedItems(decodedItems)
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
        guard Self.isValidItem(item) else { return }
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
            episodeUpdateStates: metadata.episodeUpdateStates,
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
        var episodeUpdateStates = metadata.episodeUpdateStates
        if let state = episodeUpdateStates[item.id] {
            episodeUpdateStates[item.id] = state.markingLatestSeen()
        }
        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: seenMarkers,
            notificationPreferences: metadata.notificationPreferences,
            episodeMarkers: metadata.episodeMarkers,
            seenEpisodeMarkers: seenEpisodeMarkers,
            episodeUpdateStates: episodeUpdateStates,
            lastDirectUpdateCheck: metadata.lastDirectUpdateCheck
        )
        persistMetadata()
        updateNewItemIDs()
    }

    func markEpisodeUpdateSeen(_ item: AiyifanItem, episodeKey: String?) {
        guard
            let episodeKey = episodeKey?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            let state = metadata.episodeUpdateStates[item.id],
            state.latestEpisodeKey == episodeKey
        else {
            return
        }
        var seenEpisodeMarkers = metadata.seenEpisodeMarkers
        seenEpisodeMarkers[item.id] = episodeKey
        var episodeUpdateStates = metadata.episodeUpdateStates
        episodeUpdateStates[item.id] = state.markingLatestSeen()
        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: metadata.seenMarkers,
            notificationPreferences: metadata.notificationPreferences,
            episodeMarkers: metadata.episodeMarkers,
            seenEpisodeMarkers: seenEpisodeMarkers,
            episodeUpdateStates: episodeUpdateStates,
            lastDirectUpdateCheck: metadata.lastDirectUpdateCheck
        )
        persistMetadata()
        updateNewItemIDs()
    }

    func notificationsEnabled(for item: AiyifanItem) -> Bool {
        metadata.notificationPreferences[item.id] ?? true
    }

    func checkedEpisodeKey(for item: AiyifanItem) -> String? {
        metadata.episodeUpdateStates[item.id]?.latestEpisodeKey
            ?? metadata.episodeMarkers[item.id]
    }

    func episodeUpdateState(for item: AiyifanItem) -> SavedEpisodeUpdateState? {
        metadata.episodeUpdateStates[item.id]
    }

    var readyToWatchUpdates: [ReadyToWatchUpdate] {
        items.compactMap { item in
            guard
                let state = metadata.episodeUpdateStates[item.id],
                state.seenEpisodeKey != state.latestEpisodeKey,
                let episode = state.episodes.first(where: { $0.mediaKey == state.latestEpisodeKey }),
                let detectedAt = state.detectedAt
            else {
                return nil
            }
            return ReadyToWatchUpdate(
                itemID: item.id,
                episode: Episode(
                    mediaKey: episode.mediaKey,
                    title: episode.title,
                    updateDate: nil
                ),
                detectedAt: detectedAt
            )
        }
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
            episodeUpdateStates: metadata.episodeUpdateStates,
            lastDirectUpdateCheck: metadata.lastDirectUpdateCheck
        )
        persistMetadata()
    }

    @discardableResult
    func recordEpisodeChecks(
        _ snapshots: [SavedEpisodeSnapshot],
        checkedAt: Date?,
        observedAt: Date? = nil
    ) -> [SavedEpisodeUpdate] {
        var episodeMarkers = metadata.episodeMarkers
        var seenEpisodeMarkers = metadata.seenEpisodeMarkers
        var episodeUpdateStates = metadata.episodeUpdateStates
        var updates: [SavedEpisodeUpdate] = []
        let savedByID = items.reduce(into: [String: AiyifanItem]()) { result, item in
            if result[item.id] == nil { result[item.id] = item }
        }
        let observationDate = observedAt ?? checkedAt ?? Date()

        for snapshot in snapshots {
            guard let item = savedByID[snapshot.itemID] else { continue }
            let key = snapshot.episode.mediaKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let previousState = episodeUpdateStates[item.id]
            let previousKey = previousState?.latestEpisodeKey ?? episodeMarkers[item.id]
            if let previous = previousKey {
                if previous != key {
                    updates.append(SavedEpisodeUpdate(item: item, episode: snapshot.episode))
                }
            } else {
                seenEpisodeMarkers[item.id] = key
            }
            let seenKey = previousKey == nil ? key : previousState?.seenEpisodeKey ?? seenEpisodeMarkers[item.id]
            episodeUpdateStates[item.id] = SavedEpisodeUpdateState(
                episodes: snapshot.episodes,
                latestEpisodeKey: key,
                seenEpisodeKey: seenKey,
                detectedAt: previousKey == key ? previousState?.detectedAt : observationDate,
                lastObservedAt: observationDate
            )
            episodeMarkers[item.id] = key
        }

        metadata = SavedItemsMetadata(
            markers: metadata.markers,
            seenMarkers: metadata.seenMarkers,
            notificationPreferences: metadata.notificationPreferences,
            episodeMarkers: episodeMarkers,
            seenEpisodeMarkers: seenEpisodeMarkers,
            episodeUpdateStates: episodeUpdateStates,
            lastDirectUpdateCheck: checkedAt ?? metadata.lastDirectUpdateCheck
        )
        lastDirectUpdateCheck = metadata.lastDirectUpdateCheck
        persistMetadata()
        updateNewItemIDs()
        return updates
    }

    func mergeFromCloud(_ cloudItems: [AiyifanItem]) {
        let merged = Self.sanitizedItems(items + cloudItems)
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
            let episodeChanged = metadata.episodeUpdateStates[itemID].map {
                $0.seenEpisodeKey != $0.latestEpisodeKey
            } ?? metadata.episodeMarkers[itemID].map {
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

    private static func sanitizedItems(_ candidates: [AiyifanItem]) -> [AiyifanItem] {
        candidates.reduce(into: [AiyifanItem]()) { result, item in
            guard isValidItem(item), !result.contains(where: { $0.id == item.id }) else { return }
            result.append(item)
        }
    }

    private static func isValidItem(_ item: AiyifanItem) -> Bool {
        let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty
            && id == item.id
            && id.utf8.count <= 512
            && id.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct SavedItemsMetadata: Codable {
    let markers: [String: String]
    let seenMarkers: [String: String]
    let notificationPreferences: [String: Bool]
    let episodeMarkers: [String: String]
    let seenEpisodeMarkers: [String: String]
    let episodeUpdateStates: [String: SavedEpisodeUpdateState]
    let lastDirectUpdateCheck: Date?

    init(
        markers: [String: String] = [:],
        seenMarkers: [String: String] = [:],
        notificationPreferences: [String: Bool] = [:],
        episodeMarkers: [String: String] = [:],
        seenEpisodeMarkers: [String: String] = [:],
        episodeUpdateStates: [String: SavedEpisodeUpdateState] = [:],
        lastDirectUpdateCheck: Date? = nil
    ) {
        self.markers = markers
        self.seenMarkers = seenMarkers
        self.notificationPreferences = notificationPreferences
        self.episodeMarkers = episodeMarkers
        self.seenEpisodeMarkers = seenEpisodeMarkers
        self.episodeUpdateStates = episodeUpdateStates
        self.lastDirectUpdateCheck = lastDirectUpdateCheck
    }

    func removing(itemID: String) -> SavedItemsMetadata {
        SavedItemsMetadata(
            markers: markers.filter { $0.key != itemID },
            seenMarkers: seenMarkers.filter { $0.key != itemID },
            notificationPreferences: notificationPreferences.filter { $0.key != itemID },
            episodeMarkers: episodeMarkers.filter { $0.key != itemID },
            seenEpisodeMarkers: seenEpisodeMarkers.filter { $0.key != itemID },
            episodeUpdateStates: episodeUpdateStates.filter { $0.key != itemID },
            lastDirectUpdateCheck: lastDirectUpdateCheck
        )
    }

    private enum CodingKeys: String, CodingKey {
        case markers
        case seenMarkers
        case notificationPreferences
        case episodeMarkers
        case seenEpisodeMarkers
        case episodeUpdateStates
        case lastDirectUpdateCheck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markers = try container.decodeIfPresent([String: String].self, forKey: .markers) ?? [:]
        seenMarkers = try container.decodeIfPresent([String: String].self, forKey: .seenMarkers) ?? [:]
        notificationPreferences = try container.decodeIfPresent([String: Bool].self, forKey: .notificationPreferences) ?? [:]
        episodeMarkers = try container.decodeIfPresent([String: String].self, forKey: .episodeMarkers) ?? [:]
        seenEpisodeMarkers = try container.decodeIfPresent([String: String].self, forKey: .seenEpisodeMarkers) ?? [:]
        var decodedStates = try container.decodeIfPresent(
            [String: SavedEpisodeUpdateState].self,
            forKey: .episodeUpdateStates
        ) ?? [:]
        for (itemID, latestKey) in episodeMarkers where decodedStates[itemID] == nil {
            decodedStates[itemID] = SavedEpisodeUpdateState(
                episodes: [EpisodeSelection(mediaKey: latestKey, title: latestKey)],
                latestEpisodeKey: latestKey,
                seenEpisodeKey: seenEpisodeMarkers[itemID],
                detectedAt: nil,
                lastObservedAt: nil
            )
        }
        episodeUpdateStates = decodedStates
        lastDirectUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastDirectUpdateCheck)
    }
}
