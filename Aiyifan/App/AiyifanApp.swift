import AVFoundation
import SwiftUI

@main
struct AiyifanApp: App {
    init() {
        configureAudioSession()
        GoogleCastManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
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
