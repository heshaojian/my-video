import Foundation

struct SavedEpisodeSnapshot: Equatable, Sendable {
    let itemID: String
    let episodes: [EpisodeSelection]

    var episode: EpisodeSelection {
        episodes[0]
    }

    init?(itemID: String, episodes: [EpisodeSelection]) {
        guard !episodes.isEmpty else { return nil }
        self.itemID = itemID
        self.episodes = episodes
    }

    init(itemID: String, episode: EpisodeSelection) {
        self.itemID = itemID
        episodes = [episode]
    }
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

struct SavedUpdateMonitorResult: Equatable, Sendable {
    let updates: [SavedEpisodeUpdate]
    let completedCount: Int
    let requestedCount: Int
    let didRun: Bool

    var isComplete: Bool {
        didRun && completedCount == requestedCount
    }

    static let skipped = SavedUpdateMonitorResult(
        updates: [],
        completedCount: 0,
        requestedCount: 0,
        didRun: false
    )
}

protocol SavedEpisodeResolving: Sendable {
    func episodesForSavedUpdate(
        for item: AiyifanItem,
        expectedEpisodeKey: String?
    ) async throws -> [EpisodeSelection]?
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
        case cancelled
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
            resultLoop: while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                switch result {
                case let .completed(snapshot):
                    completedCount += 1
                    if let snapshot {
                        snapshots.append(snapshot)
                    }
                case .failed:
                    break
                case .cancelled:
                    group.cancelAll()
                    break resultLoop
                }
                if !Task.isCancelled, let item = iterator.next() {
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
                guard let episodes = try await resolver.episodesForSavedUpdate(
                    for: item,
                    expectedEpisodeKey: expectedEpisodeKey
                ), let snapshot = SavedEpisodeSnapshot(itemID: item.id, episodes: episodes) else {
                    return .completed(nil)
                }
                return .completed(snapshot)
            } catch is CancellationError {
                return .cancelled
            } catch let error as URLError where error.code == .cancelled {
                return .cancelled
            } catch {
                if Task.isCancelled { return .cancelled }
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
    ) async -> SavedUpdateMonitorResult {
        guard !isChecking else { return .skipped }
        let checkedAt = now()
        guard force || DailySavedUpdatePolicy.isDue(
            lastChecked: savedItemsStore.lastDirectUpdateCheck,
            now: checkedAt
        ) else {
            return .skipped
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
            checkedAt: result.isComplete ? checkedAt : nil,
            observedAt: checkedAt
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
        return SavedUpdateMonitorResult(
            updates: updates,
            completedCount: result.completedCount,
            requestedCount: result.requestedCount,
            didRun: true
        )
    }

    private static func makeDefaultResolver() -> any SavedEpisodeResolving {
        if ProcessInfo.processInfo.arguments.contains("-AiyifanUseFixtureFeed") {
            return FixtureNativePlaybackResolver()
        }
        return NativePlaybackResolver()
    }
}
