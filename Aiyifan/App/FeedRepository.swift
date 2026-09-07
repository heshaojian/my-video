import Foundation

struct FeedRefreshResult: Sendable {
    let items: [AiyifanCategory: [AiyifanItem]]
    let staleCategories: Set<AiyifanCategory>
    let refreshedAt: Date?
    let totalFailureMessage: String?

    var statusMessage: String? {
        guard !staleCategories.isEmpty else {
            return nil
        }
        return "Showing saved results for: \(staleCategories.map(\.title).sorted().joined(separator: ", "))"
    }
}

struct FeedCacheSnapshot: Codable, Sendable {
    let items: [String: [AiyifanItem]]
    let refreshedAt: Date
}

final class FeedCacheStore: @unchecked Sendable {
    private static let storageKey = "aiyifanFeedCacheV1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FeedCacheSnapshot? {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let snapshot = try? JSONDecoder().decode(FeedCacheSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    func save(_ items: [AiyifanCategory: [AiyifanItem]], refreshedAt: Date = Date()) {
        let rawItems = Dictionary(uniqueKeysWithValues: items.map { ($0.key.rawValue, $0.value) })
        let snapshot = FeedCacheSnapshot(items: rawItems, refreshedAt: refreshedAt)
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

actor FeedRepository {
    private let service: any AiyifanFeedServing
    private let cache: FeedCacheStore

    init(
        service: any AiyifanFeedServing = AiyifanFeedService(),
        cache: FeedCacheStore = FeedCacheStore()
    ) {
        self.service = service
        self.cache = cache
    }

    func refresh() async -> FeedRefreshResult {
        let cachedSnapshot = cache.load()
        let cachedItems = Self.categoryItems(from: cachedSnapshot)
        let service = service
        let fetched = await withTaskGroup(of: (AiyifanCategory, [AiyifanItem]?).self) { group in
            for category in AiyifanCategory.allCases {
                group.addTask {
                    do {
                        return (category, try await service.fetchLatest(category: category))
                    } catch {
                        return (category, nil)
                    }
                }
            }

            var values: [(AiyifanCategory, [AiyifanItem]?)] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        var combined: [AiyifanCategory: [AiyifanItem]] = [:]
        var stale: Set<AiyifanCategory> = []
        var successful: [AiyifanCategory: [AiyifanItem]] = [:]
        for (category, items) in fetched {
            if let items {
                combined[category] = items
                successful[category] = items
            } else if let cached = cachedItems[category] {
                combined[category] = cached
                stale.insert(category)
            }
        }

        let now = Date()
        if !successful.isEmpty {
            cache.save(combined, refreshedAt: now)
        }
        return FeedRefreshResult(
            items: combined,
            staleCategories: stale,
            refreshedAt: successful.isEmpty ? cachedSnapshot?.refreshedAt : now,
            totalFailureMessage: combined.isEmpty ? "Aiyifan could not refresh the latest titles. Check your connection and try again." : nil
        )
    }

    func clearCache() {
        cache.clear()
    }

    private static func categoryItems(from snapshot: FeedCacheSnapshot?) -> [AiyifanCategory: [AiyifanItem]] {
        guard let snapshot else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: snapshot.items.compactMap { key, value in
            AiyifanCategory(rawValue: key).map { ($0, value) }
        })
    }
}
