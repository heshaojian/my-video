import AVFoundation
import MediaPlayer

@MainActor
final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()

    private var commandTargets: [(MPRemoteCommand, Any)] = []

    private init() {}

    func activate(
        player: AVPlayer,
        playPreviousEpisode: @escaping @MainActor () -> Void,
        playNextEpisode: @escaping @MainActor () -> Void
    ) {
        removeTargets()
        let center = MPRemoteCommandCenter.shared()
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [15]

        add(center.playCommand) { _ in player.play(); return .success }
        add(center.pauseCommand) { _ in player.pause(); return .success }
        add(center.togglePlayPauseCommand) { _ in
            player.timeControlStatus == .playing ? player.pause() : player.play()
            return .success
        }
        add(center.skipBackwardCommand) { _ in
            Self.seek(player, by: -15)
            return .success
        }
        add(center.skipForwardCommand) { _ in
            Self.seek(player, by: 15)
            return .success
        }
        add(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            player.seek(to: CMTime(seconds: max(0, event.positionTime), preferredTimescale: 600))
            return .success
        }
        add(center.previousTrackCommand) { _ in
            playPreviousEpisode()
            return .success
        }
        add(center.nextTrackCommand) { _ in
            playNextEpisode()
            return .success
        }
    }

    func update(_ snapshot: NowPlayingSnapshot, hasPrevious: Bool, hasNext: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.previousTrackCommand.isEnabled = hasPrevious
        center.nextTrackCommand.isEnabled = hasNext
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyAlbumTitle: snapshot.subtitle ?? "Aiyifan",
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? snapshot.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.rate
        ]
    }

    func clear() {
        removeTargets()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func add(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        let target = command.addTarget(handler: handler)
        commandTargets = commandTargets + [(command, target)]
    }

    private func removeTargets() {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets = []
    }

    private static func seek(_ player: AVPlayer, by interval: Double) {
        let current = player.currentTime().seconds
        let target = current.isFinite ? max(0, current + interval) : 0
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
}
