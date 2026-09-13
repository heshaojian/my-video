import AVFoundation
import SwiftUI
import UserNotifications

@main
struct MyVideoApp: App {
    init() {
        PlaybackAudioSessionCoordinator.shared.configure()
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

}

struct PlaybackAudioSessionConfiguration: Equatable, Sendable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    static let standard = PlaybackAudioSessionConfiguration(
        category: .playback,
        mode: .moviePlayback,
        options: []
    )
}

enum PlaybackInterruptionAction: Equatable, Sendable {
    case none
    case resume(rate: Float)
}

struct PlaybackInterruptionState: Equatable, Sendable {
    private var pendingResumeRate: Float?

    mutating func begin(wasPlaying: Bool, playbackRate: Float) {
        pendingResumeRate = wasPlaying ? max(0.5, playbackRate) : nil
    }

    mutating func end(systemSuggestsResume: Bool) -> PlaybackInterruptionAction {
        defer { pendingResumeRate = nil }
        guard systemSuggestsResume, let pendingResumeRate else {
            return .none
        }
        return .resume(rate: pendingResumeRate)
    }
}

@MainActor
final class PlaybackAudioSessionCoordinator: NSObject {
    static let shared = PlaybackAudioSessionCoordinator()

    private let audioSession = AVAudioSession.sharedInstance()
    private weak var player: AVPlayer?
    private var interruptionState = PlaybackInterruptionState()
    private var intendedPlaybackRate: Float?

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruptionNotification),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesResetNotification),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChangeNotification),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }

    func configure() {
        let configuration = PlaybackAudioSessionConfiguration.standard
        do {
            try audioSession.setCategory(
                configuration.category,
                mode: configuration.mode,
                options: configuration.options
            )
            try audioSession.setActive(true)
        } catch {
            NSLog("Failed to configure playback audio session: %@", error.localizedDescription)
        }
    }

    func attach(player: AVPlayer) {
        self.player = player
        configure()
    }

    func recordPlaybackState(isPlaying: Bool, rate: Float) {
        intendedPlaybackRate = isPlaying ? max(0.5, rate) : nil
    }

    func detach(player: AVPlayer) {
        guard self.player === player else {
            return
        }
        self.player = nil
        intendedPlaybackRate = nil
        interruptionState = PlaybackInterruptionState()
    }

    @objc private nonisolated func handleInterruptionNotification(_ notification: Notification) {
        let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
        }
    }

    @objc private nonisolated func handleMediaServicesResetNotification(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.configure()
        }
    }

    @objc private nonisolated func handleRouteChangeNotification(_ notification: Notification) {
        let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        Task { @MainActor [weak self] in
            guard
                let self,
                let reasonValue,
                AVAudioSession.RouteChangeReason(rawValue: reasonValue) != .categoryChange,
                self.player != nil
            else {
                return
            }
            self.configure()
        }
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            let rate = player?.rate ?? 0
            let resumeRate = intendedPlaybackRate ?? rate
            interruptionState.begin(wasPlaying: resumeRate > 0, playbackRate: resumeRate)
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            configure()
            if case .resume(let rate) = interruptionState.end(systemSuggestsResume: options.contains(.shouldResume)) {
                player?.playImmediately(atRate: rate)
            } else {
                intendedPlaybackRate = nil
            }
        @unknown default:
            break
        }
    }
}
