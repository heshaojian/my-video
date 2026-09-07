import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class NativePlayerViewModel: ObservableObject {
    let player = AVQueuePlayer()

    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPlayingAdvertisement = false
    @Published private(set) var episodeTitle: String?

    private let item: AiyifanItem
    private let resolver: any NativePlaybackResolving
    private var playbackItems: [AVPlayerItem] = []
    private var advertisementCount = 0
    private var loadTask: Task<Void, Never>?

    init(item: AiyifanItem, resolver: any NativePlaybackResolving = NativePlaybackResolver()) {
        self.item = item
        self.resolver = resolver
    }

    func start() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.prepareAndPlay()
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player.pause()
        player.removeAllItems()
        playbackItems = []
    }

    func monitorPlayback() async {
        while !Task.isCancelled {
            updatePlaybackState()

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    private func prepareAndPlay() async {
        isLoading = true
        errorMessage = nil
        isPlayingAdvertisement = false
        episodeTitle = nil
        player.pause()
        player.removeAllItems()

        do {
            let playback = try await resolver.resolve(item: item)
            try Task.checkCancellation()
            episodeTitle = playback.episodeTitle
            let items = playback.entries.map { AVPlayerItem(url: $0.url) }
            advertisementCount = playback.entries.prefix(while: \.isAdvertisement).count
            playbackItems = items
            for item in items {
                player.insert(item, after: nil)
            }
            player.play()
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updatePlaybackState() {
        guard let currentItem = player.currentItem else {
            return
        }

        if let currentIndex = playbackItems.firstIndex(where: { $0 === currentItem }) {
            isPlayingAdvertisement = currentIndex < advertisementCount
        }

        switch currentItem.status {
        case .readyToPlay:
            isLoading = false
            errorMessage = nil
        case .failed:
            isLoading = false
            errorMessage = currentItem.error?.localizedDescription ?? "This video could not be played."
        case .unknown:
            isLoading = true
        @unknown default:
            isLoading = false
            errorMessage = "This video uses an unsupported playback format."
        }
    }
}

struct NativePlayerScreen: View {
    let item: AiyifanItem
    let onClose: () -> Void
    let onOpenWebsite: () -> Void

    @StateObject private var viewModel: NativePlayerViewModel

    init(item: AiyifanItem, onClose: @escaping () -> Void, onOpenWebsite: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        self.onOpenWebsite = onOpenWebsite
        _viewModel = StateObject(wrappedValue: NativePlayerViewModel(item: item))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "chevron.backward")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Back to Library")
                .accessibilityIdentifier("closeNativePlayer")

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)

                    if let episodeTitle = viewModel.episodeTitle {
                        Text("Episode \(episodeTitle)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .accessibilityIdentifier("currentEpisodeLabel")
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.black)

            ZStack {
                NativePlayerController(player: viewModel.player)
                    .ignoresSafeArea(edges: .bottom)

                if viewModel.isPlayingAdvertisement && viewModel.errorMessage == nil {
                    Text("Advertisement")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(12)
                        .accessibilityIdentifier("advertisementLabel")
                }

                if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 34))

                        Text("Playback unavailable")
                            .font(.headline)

                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Retry", action: viewModel.start)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("retryNativePlayback")

                            Button("Open Website", action: onOpenWebsite)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("openWebsiteFallback")
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 360)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding()
                } else if viewModel.isLoading {
                    ProgressView("Loading video")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .background(Color.black)
        }
        .background(Color.black)
        .task {
            viewModel.start()
            await viewModel.monitorPlayback()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

private struct NativePlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.view.accessibilityIdentifier = "nativePlayer"
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
