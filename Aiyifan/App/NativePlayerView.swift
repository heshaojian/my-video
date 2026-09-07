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
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var selectedEpisode: Episode?
    @Published private(set) var pendingResumePosition = 0.0
    @Published private(set) var preparedEntryCount = 0
    @Published private(set) var hasAppliedResume = false
    @Published private(set) var playbackRate: Float
    @Published private(set) var autoplayNext: Bool
    @Published private(set) var sleepTimer = SleepTimerState.off
    @Published private(set) var autoplayCountdown: Int?

    private let item: AiyifanItem
    private let resolver: any NativePlaybackResolving
    private let playedItemsStore: PlayedItemsStore?
    private let castManager: any CastPlaybackManaging
    private let preferences: PlaybackPreferencesStore
    private var playbackItems: [AVPlayerItem] = []
    private var playbackEntries: [NativePlaybackEntry] = []
    private var loadTask: Task<Void, Never>?
    private var requestedEpisodeKey: String?
    private var muteStateBeforeAdvertisement: Bool?
    private var lastRecordedPosition: Double?
    private var autoplayTask: Task<Void, Never>?

    var nextEpisode: Episode? {
        EpisodeNavigator.next(in: episodes, current: selectedEpisode)
    }

    var previousEpisode: Episode? {
        EpisodeNavigator.previous(in: episodes, current: selectedEpisode)
    }

    init(
        item: AiyifanItem,
        initialEpisodeKey: String? = nil,
        resolver: any NativePlaybackResolving = NativePlaybackResolver(),
        playedItemsStore: PlayedItemsStore? = nil,
        castManager: any CastPlaybackManaging = GoogleCastManager.shared,
        preferences: PlaybackPreferencesStore = PlaybackPreferencesStore()
    ) {
        self.item = item
        requestedEpisodeKey = initialEpisodeKey
        self.resolver = resolver
        self.playedItemsStore = playedItemsStore
        self.castManager = castManager
        self.preferences = preferences
        playbackRate = preferences.playbackRate
        autoplayNext = preferences.autoplayNext
        player.defaultRate = preferences.playbackRate
    }

    func start() {
        loadTask?.cancel()
        cancelAutoplay()
        NowPlayingCoordinator.shared.activate(
            player: player,
            playPreviousEpisode: { [weak self] in self?.playPreviousEpisode() },
            playNextEpisode: { [weak self] in self?.playNextEpisode() }
        )
        loadTask = Task { [weak self] in
            await self?.prepareAndPlay()
        }
    }

    func stop() {
        persistProgress()
        loadTask?.cancel()
        loadTask = nil
        cancelAutoplay()
        restoreSoundAfterAdvertisement()
        player.pause()
        player.removeAllItems()
        playbackItems = []
        playbackEntries = []
        preparedEntryCount = 0
        castManager.clear()
        NowPlayingCoordinator.shared.clear()
    }

    func selectEpisode(_ episode: Episode) {
        guard episode.mediaKey != selectedEpisode?.mediaKey else {
            return
        }
        persistProgress()
        requestedEpisodeKey = episode.mediaKey
        start()
    }

    func playNextEpisode() {
        guard let nextEpisode else {
            return
        }
        selectEpisode(nextEpisode)
    }

    func playPreviousEpisode() {
        guard let previousEpisode else {
            return
        }
        selectEpisode(previousEpisode)
    }

    func setPlaybackRate(_ rate: Float) {
        preferences.setPlaybackRate(rate)
        playbackRate = preferences.playbackRate
        player.defaultRate = playbackRate
        if player.timeControlStatus == .playing {
            player.playImmediately(atRate: playbackRate)
        }
        updateNowPlaying(position: player.currentTime().seconds, duration: player.currentItem?.duration.seconds ?? 0)
    }

    func setAutoplayNext(_ enabled: Bool) {
        preferences.setAutoplayNext(enabled)
        autoplayNext = enabled
        if !enabled {
            cancelAutoplay()
        }
    }

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimer = SleepTimerState.starting(option)
    }

    func cancelAutoplay() {
        autoplayTask?.cancel()
        autoplayTask = nil
        autoplayCountdown = nil
    }

    func persistProgress() {
        guard
            let currentItem = player.currentItem,
            let index = playbackItems.firstIndex(where: { $0 === currentItem }),
            playbackEntries.indices.contains(index),
            !playbackEntries[index].isAdvertisement
        else {
            return
        }
        recordProgress(
            position: currentItem.currentTime().seconds,
            duration: currentItem.duration.seconds,
            force: true
        )
    }

    func monitorPlayback() async {
        while !Task.isCancelled {
            updatePlaybackState()

            if sleepTimer.shouldPause() {
                pauseForSleepTimer()
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    private func prepareAndPlay() async {
        restoreSoundAfterAdvertisement()
        isLoading = true
        errorMessage = nil
        isPlayingAdvertisement = false
        episodeTitle = nil
        episodes = []
        selectedEpisode = nil
        pendingResumePosition = 0
        lastRecordedPosition = nil
        hasAppliedResume = false
        preparedEntryCount = 0
        player.pause()
        player.removeAllItems()

        do {
            let playback = try await resolveWithRecovery()
            try Task.checkCancellation()
            episodes = playback.episodes
            selectedEpisode = playback.selectedEpisode
            episodeTitle = playback.episodeTitle
            pendingResumePosition = playedItemsStore?
                .record(for: item, episodeKey: playback.selectedEpisode?.mediaKey)?
                .resumePosition ?? 0
            let items = playback.entries.map { AVPlayerItem(url: $0.url) }
            playbackEntries = playback.entries
            preparedEntryCount = playback.entries.count
            playbackItems = items
            if let castPlan = try? CastPlaybackPlanBuilder.make(
                item: item,
                playback: playback,
                programPosition: pendingResumePosition
            ) {
                castManager.prepare(castPlan, loadIfConnected: true)
            }
            for item in items {
                player.insert(item, after: nil)
            }
            player.defaultRate = playbackRate
            if !playback.entries.isEmpty {
                handlePlaybackEntry(index: 0, position: 0, duration: playback.entries[0].isAdvertisement ? 1 : 0)
            }
            if castManager.isCasting {
                player.pause()
            } else {
                player.playImmediately(atRate: playbackRate)
            }
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resolveWithRecovery() async throws -> NativePlayback {
        var attempt = 0
        while true {
            do {
                return try await resolver.resolve(item: item, preferredEpisodeKey: requestedEpisodeKey)
            } catch {
                guard PlaybackRecoveryPolicy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }
                attempt += 1
                try await Task.sleep(for: .milliseconds(500))
                try Task.checkCancellation()
            }
        }
    }

    private func updatePlaybackState() {
        guard let currentItem = player.currentItem else {
            return
        }

        if let currentIndex = playbackItems.firstIndex(where: { $0 === currentItem }) {
            handlePlaybackEntry(
                index: currentIndex,
                position: currentItem.currentTime().seconds,
                duration: currentItem.duration.seconds
            )
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

    func handlePlaybackEntry(index: Int, position: Double, duration: Double) {
        guard playbackEntries.indices.contains(index) else {
            return
        }
        let isAdvertisement = playbackEntries[index].isAdvertisement
        isPlayingAdvertisement = isAdvertisement

        if isAdvertisement {
            if muteStateBeforeAdvertisement == nil {
                muteStateBeforeAdvertisement = player.isMuted
            }
            player.isMuted = true
            return
        }

        restoreSoundAfterAdvertisement()
        if !hasAppliedResume, pendingResumePosition > 0 {
            if position + 0.5 >= pendingResumePosition {
                hasAppliedResume = true
            } else {
                guard player.currentItem?.status == .readyToPlay else {
                    return
                }
                hasAppliedResume = true
                castManager.updateProgramPosition(pendingResumePosition)
                player.seek(to: CMTime(seconds: pendingResumePosition, preferredTimescale: 600))
                return
            }
        }
        hasAppliedResume = true
        castManager.updateProgramPosition(position)
        recordProgress(position: position, duration: duration, force: false)
        let programCompleted = duration.isFinite && duration > 0 && position / duration >= 0.99
        updateNowPlaying(position: position, duration: duration)
        if sleepTimer.shouldPause(programCompleted: programCompleted) {
            pauseForSleepTimer()
        } else if programCompleted {
            scheduleAutoplayIfNeeded()
        }
    }

    private func scheduleAutoplayIfNeeded() {
        guard autoplayNext, nextEpisode != nil, autoplayTask == nil else {
            return
        }
        autoplayTask = Task { [weak self] in
            for remaining in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                self?.autoplayCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            self?.autoplayTask = nil
            self?.autoplayCountdown = nil
            self?.playNextEpisode()
        }
    }

    private func pauseForSleepTimer() {
        player.pause()
        sleepTimer = .off
        cancelAutoplay()
    }

    private func updateNowPlaying(position: Double, duration: Double) {
        guard !isPlayingAdvertisement else {
            return
        }
        NowPlayingCoordinator.shared.update(
            NowPlayingSnapshot(
                item: item,
                episodeTitle: episodeTitle,
                duration: duration,
                elapsed: position,
                playbackRate: playbackRate,
                isPlaying: player.timeControlStatus == .playing
            ),
            hasPrevious: previousEpisode != nil,
            hasNext: nextEpisode != nil
        )
    }

    private func restoreSoundAfterAdvertisement() {
        guard let muteStateBeforeAdvertisement else {
            return
        }
        player.isMuted = muteStateBeforeAdvertisement
        self.muteStateBeforeAdvertisement = nil
    }

    private func recordProgress(position: Double, duration: Double, force: Bool) {
        guard
            position.isFinite,
            duration.isFinite,
            position >= 0,
            duration > 0
        else {
            return
        }
        if !force, let lastRecordedPosition, abs(position - lastRecordedPosition) < 10 {
            return
        }
        playedItemsStore?.record(
            item: item,
            episode: selectedEpisode,
            position: position,
            duration: duration
        )
        lastRecordedPosition = position
    }
}

struct NativePlayerScreen: View {
    let item: AiyifanItem
    let onClose: () -> Void
    let onOpenWebsite: () -> Void

    @StateObject private var viewModel: NativePlayerViewModel
    @StateObject private var castManager = GoogleCastManager.shared
    @State private var isShowingEpisodes = false
    @Environment(\.scenePhase) private var scenePhase
    private let usesFixturePlayback: Bool

    init(
        item: AiyifanItem,
        initialEpisodeKey: String? = nil,
        playedItemsStore: PlayedItemsStore,
        onClose: @escaping () -> Void,
        onOpenWebsite: @escaping () -> Void
    ) {
        self.item = item
        self.onClose = onClose
        self.onOpenWebsite = onOpenWebsite
        let usesFixturePlayback = ProcessInfo.processInfo.arguments.contains("-AiyifanUseFixtureFeed")
        self.usesFixturePlayback = usesFixturePlayback
        let resolver: any NativePlaybackResolving = usesFixturePlayback
            ? FixtureNativePlaybackResolver()
            : NativePlaybackResolver()
        _viewModel = StateObject(wrappedValue: NativePlayerViewModel(
            item: item,
            initialEpisodeKey: initialEpisodeKey,
            resolver: resolver,
            playedItemsStore: playedItemsStore
        ))
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

                AirPlayRouteButton()
                    .frame(width: 36, height: 36)

                GoogleCastRouteButton()
                    .frame(width: 36, height: 36)

                Button(action: onOpenWebsite) {
                    Image(systemName: "safari")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Open Website")
                .accessibilityIdentifier("openWebsiteFallback")
                .help("Open Website")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.black)

            HStack(spacing: 8) {
                if !viewModel.episodes.isEmpty {
                    Button(action: viewModel.playPreviousEpisode) {
                        Image(systemName: "backward.end.fill")
                            .frame(width: 36, height: 36)
                    }
                    .disabled(viewModel.previousEpisode == nil)
                    .accessibilityLabel("Previous Episode")
                    .accessibilityIdentifier("previousEpisode")

                    Button {
                        isShowingEpisodes = true
                    } label: {
                        Image(systemName: "list.number")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Episodes")
                    .accessibilityIdentifier("showEpisodes")

                    Button(action: viewModel.playNextEpisode) {
                        Image(systemName: "forward.end.fill")
                            .frame(width: 36, height: 36)
                    }
                    .disabled(viewModel.nextEpisode == nil)
                    .accessibilityLabel("Next Episode")
                    .accessibilityIdentifier("nextEpisode")
                }

                Spacer()

                if let timerLabel = viewModel.sleepTimer.remainingLabel() {
                    Label(timerLabel, systemImage: "moon.zzz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }

                Menu {
                    Menu("Speed") {
                        ForEach(PlaybackPreferencesStore.supportedRates, id: \.self) { rate in
                            Button {
                                viewModel.setPlaybackRate(rate)
                            } label: {
                                if rate == viewModel.playbackRate {
                                    Label("\(rate.formatted())x", systemImage: "checkmark")
                                } else {
                                    Text("\(rate.formatted())x")
                                }
                            }
                        }
                    }

                    Menu("Sleep Timer") {
                        ForEach(Array(SleepTimerOption.choices.enumerated()), id: \.offset) { _, option in
                            Button(option.title) { viewModel.setSleepTimer(option) }
                        }
                    }

                    if !viewModel.episodes.isEmpty {
                        Button {
                            viewModel.setAutoplayNext(!viewModel.autoplayNext)
                        } label: {
                            Label(
                                viewModel.autoplayNext ? "Disable Autoplay Next" : "Enable Autoplay Next",
                                systemImage: viewModel.autoplayNext ? "autostartstop.slash" : "autostartstop"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Playback Settings")
                .accessibilityIdentifier("playbackSettings")
            }
            .padding(.horizontal, 10)
            .foregroundStyle(.white)
            .background(Color.black)

            ZStack {
                NativePlayerController(player: viewModel.player)
                    .ignoresSafeArea(edges: .bottom)

                if viewModel.isPlayingAdvertisement && viewModel.errorMessage == nil {
                    Text("Advertisement · Muted")
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

                if let countdown = viewModel.autoplayCountdown {
                    Button {
                        viewModel.cancelAutoplay()
                    } label: {
                        Label("Next episode in \(countdown)s", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(16)
                    .accessibilityIdentifier("cancelAutoplay")
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
                                .accessibilityIdentifier("openWebsiteFallbackError")
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
            if !usesFixturePlayback {
                await viewModel.monitorPlayback()
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.persistProgress()
            }
        }
        .onChange(of: castManager.isCasting) { _, isCasting in
            if isCasting {
                viewModel.persistProgress()
                viewModel.player.pause()
            }
        }
        .sheet(isPresented: $isShowingEpisodes) {
            NavigationStack {
                List(viewModel.episodes) { episode in
                    Button {
                        viewModel.selectEpisode(episode)
                        isShowingEpisodes = false
                    } label: {
                        HStack {
                            Text("Episode \(episode.title)")
                            Spacer()
                            if episode.id == viewModel.selectedEpisode?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("episodeRow-\(episode.id)")
                }
                .navigationTitle("Episodes")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
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
