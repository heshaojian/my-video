import BackgroundTasks
import Foundation

enum BackgroundRefreshScheduler {
    static let identifier = "com.john.myvideo.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: DailySavedUpdatePolicy.interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum BackgroundFeedRefresher {
    @MainActor
    static func refresh() async {
        let settings = AppSettingsStore()
        let savedItems = SavedItemsStore()
        let checkResult = await SavedUpdateChecker.check(
            items: savedItems.items,
            expectedEpisodeKeys: Dictionary(uniqueKeysWithValues: savedItems.items.compactMap { item in
                savedItems.checkedEpisodeKey(for: item).map { (item.id, $0) }
            })
        )
        let episodeUpdates = savedItems.recordEpisodeChecks(
            checkResult.snapshots,
            checkedAt: checkResult.isComplete ? Date() : nil
        )

        if settings.updateAlertsEnabled,
           let batch = NotificationBatch.make(
            episodeUpdates: episodeUpdates,
            notificationsEnabled: { savedItems.notificationsEnabled(for: $0) }
           ) {
            await NotificationCoordinator.shared.schedule(batch)
        }

        let result = await FeedRepository().refresh()
        if result.totalFailureMessage == nil, settings.updateAlertsEnabled {
            let directUpdateIDs = Set(episodeUpdates.map(\.item.id))
            let changed = savedItems.refreshUpdateMarkers(with: result.items)
                .filter { !directUpdateIDs.contains($0.id) }
            if let batch = NotificationBatch.make(
                items: changed,
                notificationsEnabled: { savedItems.notificationsEnabled(for: $0) }
            ) {
                await NotificationCoordinator.shared.schedule(batch)
            }
        }

        if result.totalFailureMessage == nil, !settings.updateAlertsEnabled {
            _ = savedItems.refreshUpdateMarkers(with: result.items)
        }
        BackgroundRefreshScheduler.schedule()
    }
}
