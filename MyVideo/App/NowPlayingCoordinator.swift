import AVFoundation
import MediaPlayer
import UIKit

enum NowPlayingMetadataBuilder {
    static func values(for snapshot: NowPlayingSnapshot) -> [String: Any] {
        [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyAlbumTitle: snapshot.subtitle ?? "MyVideo",
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? snapshot.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
    }
}

enum NowPlayingArtworkBuilder {
    static func make(from image: UIImage?) -> MPMediaItemArtwork? {
        guard let image else {
            return nil
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

@MainActor
final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()

    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

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
        var values = NowPlayingMetadataBuilder.values(for: snapshot)
        let fallbackArtwork = artwork ?? NowPlayingArtworkBuilder.make(from: UIImage(named: "BrandMark"))
        if let fallbackArtwork {
            values[MPMediaItemPropertyArtwork] = fallbackArtwork
        }
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = values
        infoCenter.playbackState = snapshot.isPlaying ? .playing : .paused
        loadArtworkIfNeeded(from: snapshot.artworkURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkURL = nil
        artwork = nil
        removeTargets()
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
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

    private func loadArtworkIfNeeded(from url: URL?) {
        guard artworkURL != url else {
            return
        }
        artworkTask?.cancel()
        artworkURL = url
        artwork = NowPlayingArtworkBuilder.make(from: UIImage(named: "BrandMark"))
        guard let url else {
            return
        }
        artworkTask = Task { [weak self] in
            guard
                let (data, response) = try? await URLSession.shared.data(from: url),
                !Task.isCancelled,
                (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                let image = UIImage(data: data),
                let remoteArtwork = NowPlayingArtworkBuilder.make(from: image)
            else {
                return
            }
            guard let self, self.artworkURL == url else {
                return
            }
            self.artwork = remoteArtwork
            var values = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            values[MPMediaItemPropertyArtwork] = remoteArtwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = values
        }
    }

}
