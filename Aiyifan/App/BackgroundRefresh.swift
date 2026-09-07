import BackgroundTasks
import Foundation

enum BackgroundRefreshScheduler {
    static let identifier = "com.john.aiyifan.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum BackgroundFeedRefresher {
    static func refresh() async {
        let result = await FeedRepository().refresh()
        guard result.totalFailureMessage == nil else {
            BackgroundRefreshScheduler.schedule()
            return
        }

        let batch = await MainActor.run { () -> NotificationBatch? in
            let settings = AppSettingsStore()
            guard settings.updateAlertsEnabled else {
                return nil
            }
            let savedItems = SavedItemsStore()
            let changed = savedItems.refreshUpdateMarkers(with: result.items)
            return NotificationBatch.make(
                items: changed,
                notificationsEnabled: { item in savedItems.notificationsEnabled(for: item) }
            )
        }
        if let batch {
            await NotificationCoordinator.shared.schedule(batch)
        }
        BackgroundRefreshScheduler.schedule()
    }
}
