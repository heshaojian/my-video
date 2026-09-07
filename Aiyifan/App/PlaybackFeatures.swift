import Foundation

@MainActor
final class PlaybackPreferencesStore: ObservableObject {
    static let supportedRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    @Published private(set) var playbackRate: Float
    @Published private(set) var autoplayNext: Bool

    private static let rateKey = "aiyifanPlaybackRate"
    private static let autoplayKey = "aiyifanAutoplayNext"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRate = defaults.float(forKey: Self.rateKey)
        playbackRate = Self.supportedRates.contains(storedRate) ? storedRate : 1
        autoplayNext = defaults.object(forKey: Self.autoplayKey) as? Bool ?? true
    }

    func setPlaybackRate(_ rate: Float) {
        guard Self.supportedRates.contains(rate) else {
            return
        }
        playbackRate = rate
        defaults.set(rate, forKey: Self.rateKey)
    }

    func setAutoplayNext(_ enabled: Bool) {
        autoplayNext = enabled
        defaults.set(enabled, forKey: Self.autoplayKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.rateKey)
        defaults.removeObject(forKey: Self.autoplayKey)
        playbackRate = 1
        autoplayNext = true
    }
}

enum SleepTimerOption: Equatable, Sendable {
    case off
    case minutes(Int)
    case endOfEpisode

    static let choices: [SleepTimerOption] = [
        .off, .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfEpisode
    ]

    var title: String {
        switch self {
        case .off: "Off"
        case .minutes(let value): "\(value) min"
        case .endOfEpisode: "End of Episode"
        }
    }
}

struct SleepTimerState: Equatable, Sendable {
    let option: SleepTimerOption
    let deadline: Date?

    static let off = SleepTimerState(option: .off, deadline: nil)

    static func starting(_ option: SleepTimerOption, now: Date = Date()) -> SleepTimerState {
        switch option {
        case .minutes(let value):
            return SleepTimerState(option: option, deadline: now.addingTimeInterval(Double(value * 60)))
        case .off, .endOfEpisode:
            return SleepTimerState(option: option, deadline: nil)
        }
    }

    func shouldPause(now: Date = Date(), programCompleted: Bool = false) -> Bool {
        switch option {
        case .off:
            return false
        case .minutes:
            return deadline.map { now >= $0 } ?? false
        case .endOfEpisode:
            return programCompleted
        }
    }

    func remainingLabel(now: Date = Date()) -> String? {
        switch option {
        case .off:
            return nil
        case .endOfEpisode:
            return "End of Episode"
        case .minutes:
            let seconds = max(0, Int((deadline?.timeIntervalSince(now) ?? 0).rounded(.down)))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }
}

struct NowPlayingSnapshot: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let duration: Double
    let elapsed: Double
    let rate: Float
    let isPlaying: Bool

    init(
        item: AiyifanItem,
        episodeTitle: String?,
        duration: Double,
        elapsed: Double,
        playbackRate: Float,
        isPlaying: Bool
    ) {
        title = item.title
        subtitle = episodeTitle.map { "Episode \($0)" }
        artworkURL = item.thumbnailURL
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        rate = playbackRate
        self.isPlaying = isPlaying
    }
}

enum PlaybackRecoveryPolicy {
    static func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt == 0 else {
            return false
        }
        if error is NativePlaybackError {
            return false
        }
        guard let urlError = error as? URLError else {
            return false
        }
        return [
            .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable
        ].contains(urlError.code)
    }
}
