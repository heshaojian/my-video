import AVFoundation
import SwiftUI
import UserNotifications

@main
struct AiyifanApp: App {
    init() {
        configureAudioSession()
        GoogleCastManager.shared.configure()
        UNUserNotificationCenter.current().delegate = NotificationResponseRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
        }
        .backgroundTask(.appRefresh(BackgroundRefreshScheduler.identifier)) {
            await BackgroundFeedRefresher.refresh()
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("Failed to configure audio session: %@", error.localizedDescription)
        }
    }
}
