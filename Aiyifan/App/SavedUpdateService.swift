import Foundation

struct SavedEpisodeSnapshot: Equatable, Sendable {
    let itemID: String
    let episode: EpisodeSelection
}

struct SavedEpisodeUpdate: Equatable, Sendable {
    let item: AiyifanItem
    let episode: EpisodeSelection
}

struct SavedUpdateCheckResult: Equatable, Sendable {
    let snapshots: [SavedEpisodeSnapshot]
    let completedCount: Int
    let requestedCount: Int

    var isComplete: Bool { completedCount == requestedCount }
}

protocol SavedEpisodeResolving: Sendable {
    func latestEpisode(for item: AiyifanItem, expectedEpisodeKey: String?) async throws -> EpisodeSelection?
}

enum DailySavedUpdatePolicy {
    static let interval: TimeInterval = 24 * 60 * 60

    static func isDue(lastChecked: Date?, now: Date = Date()) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= interval
    }
}

enum SavedUpdateChecker {
    private enum Outcome: Sendable {
        case completed(SavedEpisodeSnapshot?)
        case failed
    }

    static func check(
        items: [AiyifanItem],
        expectedEpisodeKeys: [String: String] = [:],
        resolver: any SavedEpisodeResolving = NativePlaybackResolver(),
        maximumConcurrentChecks: Int = 3
    ) async -> SavedUpdateCheckResult {
        guard !items.isEmpty else {
            return SavedUpdateCheckResult(snapshots: [], completedCount: 0, requestedCount: 0)
        }
        let concurrency = min(max(1, maximumConcurrentChecks), items.count)

        return await withTaskGroup(of: Outcome.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<concurrency {
                guard let item = iterator.next() else { break }
                addCheck(
                    for: item,
                    expectedEpisodeKey: expectedEpisodeKeys[item.id],
                    resolver: resolver,
                    to: &group
                )
            }

            var snapshots: [SavedEpisodeSnapshot] = []
            var completedCount = 0
            while let result = await group.next() {
                switch result {
                case let .completed(snapshot):
                    completedCount += 1
                    if let snapshot {
                        snapshots.append(snapshot)
                    }
                case .failed:
                    break
                }
                if let item = iterator.next() {
                    addCheck(
                        for: item,
                        expectedEpisodeKey: expectedEpisodeKeys[item.id],
                        resolver: resolver,
                        to: &group
                    )
                }
            }
            return SavedUpdateCheckResult(
                snapshots: snapshots.sorted { $0.itemID < $1.itemID },
                completedCount: completedCount,
                requestedCount: items.count
            )
        }
    }

    private static func addCheck(
        for item: AiyifanItem,
        expectedEpisodeKey: String?,
        resolver: any SavedEpisodeResolving,
        to group: inout TaskGroup<Outcome>
    ) {
        group.addTask {
            do {
                guard let episode = try await resolver.latestEpisode(
                    for: item,
                    expectedEpisodeKey: expectedEpisodeKey
                ) else {
                    return .completed(nil)
                }
                return .completed(SavedEpisodeSnapshot(itemID: item.id, episode: episode))
            } catch {
                return .failed
            }
        }
    }
}

@MainActor
final class SavedUpdateMonitor: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage: String?

    private let resolver: any SavedEpisodeResolving
    private let now: @Sendable () -> Date

    init(
        resolver: (any SavedEpisodeResolving)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.resolver = resolver ?? Self.makeDefaultResolver()
        self.now = now
    }

    @discardableResult
    func check(
        savedItemsStore: SavedItemsStore,
        settings: AppSettingsStore,
        force: Bool = false
    ) async -> [SavedEpisodeUpdate] {
        guard !isChecking else { return [] }
        let checkedAt = now()
        guard force || DailySavedUpdatePolicy.isDue(
            lastChecked: savedItemsStore.lastDirectUpdateCheck,
            now: checkedAt
        ) else {
            return []
        }

        isChecking = true
        statusMessage = nil
        defer { isChecking = false }
        let result = await SavedUpdateChecker.check(
            items: savedItemsStore.items,
            expectedEpisodeKeys: Dictionary(uniqueKeysWithValues: savedItemsStore.items.compactMap { item in
                savedItemsStore.checkedEpisodeKey(for: item).map { (item.id, $0) }
            }),
            resolver: resolver
        )
        let updates = savedItemsStore.recordEpisodeChecks(
            result.snapshots,
            checkedAt: result.isComplete ? checkedAt : nil
        )
        statusMessage = result.isComplete
            ? "All saved titles checked"
            : "Checked \(result.completedCount) of \(result.requestedCount) saved titles"
        if settings.updateAlertsEnabled,
           let batch = NotificationBatch.make(
            episodeUpdates: updates,
            notificationsEnabled: { savedItemsStore.notificationsEnabled(for: $0) }
           ) {
            await NotificationCoordinator.shared.schedule(batch)
        }
        return updates
    }

    private static func makeDefaultResolver() -> any SavedEpisodeResolving {
        if ProcessInfo.processInfo.arguments.contains("-AiyifanUseFixtureFeed") {
            return FixtureNativePlaybackResolver()
        }
        return NativePlaybackResolver()
    }
}
