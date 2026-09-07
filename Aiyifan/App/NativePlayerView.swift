import AVFoundation
import AVKit
import SwiftUI

enum PlaybackProgressPersistence: Equatable, Sendable {
    case none
    case periodic
    case final
}

struct PlaybackProgressState: Equatable, Sendable {
    private var wasPlaying = false

    mutating func update(isPlaying: Bool) -> PlaybackProgressPersistence {
        defer { wasPlaying = isPlaying }
        if isPlaying {
            return .periodic
        }
        return wasPlaying ? .final : .none
    }
}

struct PlayerPresentationState: Equatable, Sendable {
    private(set) var isFullScreenActive = false
    private(set) var isPictureInPictureActive = false

    var shouldStopOnDisappear: Bool {
        !isFullScreenActive && !isPictureInPictureActive
    }

    mutating func setFullScreenActive(_ active: Bool) {
        isFullScreenActive = active
    }

    mutating func setPictureInPictureActive(_ active: Bool) {
        isPictureInPictureActive = active
    }
}

@MainActor
final class NativePlayerViewModel: ObservableObject {
    let player = AVQueuePlayer()

    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var episodeTitle: String?
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var selectedEpisode: Episode?
    @Published private(set) var expectsEpisodes: Bool
    @Published private(set) var pendingResumePosition = 0.0
    @Published private(set) var preparedEntryCount = 0
    @Published private(set) var hasAppliedResume = false
    @Published private(set) var playbackRate: Float
    @Published private(set) var autoplayNext: Bool
    @Published private(set) var sleepTimer = SleepTimerState.off
    @Published private(set) var autoplayCountdown: Int?
    @Published private(set) var viewerMetrics: ViewerMetrics?

    private let item: AiyifanItem
    private let resolver: any NativePlaybackResolving
    private let playedItemsStore: PlayedItemsStore?
    private let castManager: any CastPlaybackManaging
    private let preferences: PlaybackPreferencesStore
    private var playbackItems: [AVPlayerItem] = []
    private var playbackEntries: [NativePlaybackEntry] = []
    private var loadTask: Task<Void, Never>?
    private var requestedEpisodeKey: String?
    private var lastRecordedPosition: Double?
    private var autoplayTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var progressState = PlaybackProgressState()
    private var presentationState = PlayerPresentationState()
    private var sessionStarted = false

    var nextEpisode: Episode? {
        EpisodeNavigator.next(in: episodes, current: selectedEpisode)
    }

    var previousEpisode: Episode? {
        EpisodeNavigator.previous(in: episodes, current: selectedEpisode)
    }

    var shouldShowEpisodeControl: Bool {
        expectsEpisodes || !episodes.isEmpty
    }

    var episodeControlTitle: String? {
        guard shouldShowEpisodeControl else {
            return nil
        }
        guard let selectedEpisode, !episodes.isEmpty else {
            return isLoading ? "Loading Episodes" : "Select Episode"
        }
        let selectedNumber = episodeNumber(in: selectedEpisode.title)
        let numericTotal = episodes.compactMap { episodeNumber(in: $0.title) }.max()
        let current = selectedNumber.map(String.init) ?? selectedEpisode.title
        let total = max(numericTotal ?? 0, episodes.count)
        return "Episode \(current)/\(total)"
    }

    private func episodeNumber(in title: String) -> Int? {
        EpisodeNumberParser.number(in: title)
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
        expectsEpisodes = item.isSerial == true || item.latestEpisodeKey != nil || initialEpisodeKey != nil
        requestedEpisodeKey = initialEpisodeKey
        self.resolver = resolver
        self.playedItemsStore = playedItemsStore
        self.castManager = castManager
        self.preferences = preferences
        playbackRate = preferences.playbackRate
        autoplayNext = preferences.autoplayNext
        player.defaultRate = preferences.playbackRate
    }

    func start(monitorPlayback: Bool = false) {
        guard !sessionStarted else {
            return
        }
        sessionStarted = true
        PlaybackAudioSessionCoordinator.shared.attach(player: player)
        NowPlayingCoordinator.shared.activate(
            player: player,
            playPreviousEpisode: { [weak self] in self?.playPreviousEpisode() },
            playNextEpisode: { [weak self] in self?.playNextEpisode() }
        )
        if monitorPlayback {
            monitorTask = Task { [weak self] in
                await self?.monitorPlayback()
            }
        }
        beginLoad()
    }

    func retry() {
        if sessionStarted {
            beginLoad()
        } else {
            start()
        }
    }

    private func beginLoad() {
        loadTask?.cancel()
        cancelAutoplay()
        loadTask = Task { [weak self] in
            await self?.prepareAndPlay()
        }
    }

    func stop() {
        persistProgress()
        loadTask?.cancel()
        loadTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        cancelAutoplay()
        player.pause()
        player.removeAllItems()
        playbackItems = []
        playbackEntries = []
        preparedEntryCount = 0
        progressState = PlaybackProgressState()
        presentationState = PlayerPresentationState()
        sessionStarted = false
        castManager.clear()
        PlaybackAudioSessionCoordinator.shared.detach(player: player)
        NowPlayingCoordinator.shared.clear()
    }

    func selectEpisode(_ episode: Episode) {
        guard episode.mediaKey != selectedEpisode?.mediaKey else {
            return
        }
        persistProgress()
        requestedEpisodeKey = episode.mediaKey
        beginLoad()
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

    var shouldStopOnDisappear: Bool {
        presentationState.shouldStopOnDisappear
    }

    func setFullScreenPresentationActive(_ active: Bool) {
        presentationState.setFullScreenActive(active)
    }

    func setPictureInPictureActive(_ active: Bool) {
        presentationState.setPictureInPictureActive(active)
    }

    func handleScreenDisappear() {
        guard shouldStopOnDisappear else { return }
        stop()
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

    private func monitorPlayback() async {
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
        isLoading = true
        errorMessage = nil
        episodeTitle = nil
        episodes = []
        selectedEpisode = nil
        viewerMetrics = nil
        pendingResumePosition = 0
        lastRecordedPosition = nil
        progressState = PlaybackProgressState()
        hasAppliedResume = false
        preparedEntryCount = 0
        player.pause()
        player.removeAllItems()

        do {
            let playback = try await resolveWithRecovery()
            try Task.checkCancellation()
            episodes = playback.episodes
            expectsEpisodes = expectsEpisodes || !playback.episodes.isEmpty
            selectedEpisode = playback.selectedEpisode
            viewerMetrics = playback.metrics
            episodeTitle = playback.episodeTitle
            pendingResumePosition = playedItemsStore?
                .record(for: item, episodeKey: playback.selectedEpisode?.mediaKey)?
                .resumePosition ?? 0
            let programEntries = playback.entries.filter { !$0.isAdvertisement }
            guard !programEntries.isEmpty else {
                throw NativePlaybackError.unsupportedMedia
            }
            let playable = NativePlayback(
                entries: programEntries,
                episodes: playback.episodes,
                selectedEpisode: playback.selectedEpisode
            )
            let items = programEntries.map { AVPlayerItem(url: $0.url) }
            playbackEntries = programEntries
            preparedEntryCount = programEntries.count
            playbackItems = items
            if let castPlan = try? CastPlaybackPlanBuilder.make(
                item: item,
                playback: playable,
                programPosition: pendingResumePosition
            ) {
                castManager.prepare(castPlan, loadIfConnected: true)
            }
            for item in items {
                player.insert(item, after: nil)
            }
            player.defaultRate = playbackRate
            if !programEntries.isEmpty {
                handlePlaybackEntry(index: 0, position: 0, duration: 0, isPlaying: false)
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
                duration: currentItem.duration.seconds,
                isPlaying: player.timeControlStatus == .playing
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

    func handlePlaybackEntry(index: Int, position: Double, duration: Double, isPlaying: Bool) {
        guard playbackEntries.indices.contains(index) else {
            return
        }
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
        switch progressState.update(isPlaying: isPlaying) {
        case .none:
            break
        case .periodic:
            castManager.updateProgramPosition(position)
            recordProgress(position: position, duration: duration, force: false)
        case .final:
            castManager.updateProgramPosition(position)
            recordProgress(position: position, duration: duration, force: true)
        }
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
        let isPlaying = player.timeControlStatus == .playing
        PlaybackAudioSessionCoordinator.shared.recordPlaybackState(
            isPlaying: isPlaying,
            rate: playbackRate
        )
        NowPlayingCoordinator.shared.update(
            NowPlayingSnapshot(
                item: item,
                episodeTitle: episodeTitle,
                duration: duration,
                elapsed: position,
                playbackRate: playbackRate,
                isPlaying: isPlaying
            ),
            hasPrevious: previousEpisode != nil,
            hasNext: nextEpisode != nil
        )
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
    private let monitorsPlayback: Bool

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
        monitorsPlayback = !usesFixturePlayback
            || ProcessInfo.processInfo.arguments.contains("-AiyifanUsePlayableFixtureMedia")
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
            HStack(spacing: 8) {
                Button(action: closePlayer) {
                    Image(systemName: "chevron.backward")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to Library")
                .accessibilityIdentifier("closeNativePlayer")

                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                HStack(spacing: 2) {
                    if let episodeTitle = viewModel.episodeControlTitle {
                        Button {
                            isShowingEpisodes = true
                        } label: {
                            Text(episodeTitle)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(minHeight: 44)
                        }
                        .disabled(viewModel.episodes.isEmpty)
                        .accessibilityLabel("Episodes, \(episodeTitle)")
                        .accessibilityIdentifier("showEpisodes")

                    }

                    AirPlayRouteButton()
                        .frame(width: 44, height: 44)

                    GoogleCastRouteButton()
                        .frame(width: 44, height: 44)

                    playbackMenu
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Color.black)

            if let metrics = viewModel.viewerMetrics, !metrics.isEmpty {
                ViewerMetricsBar(metrics: metrics)
            }

            ZStack {
                NativePlayerController(
                    player: viewModel.player,
                    onFullScreenChanged: viewModel.setFullScreenPresentationActive,
                    onPictureInPictureChanged: viewModel.setPictureInPictureActive
                )
                    .ignoresSafeArea(edges: .bottom)

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
                            Button("Retry", action: viewModel.retry)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("retryNativePlayback")

                            Button("Open Website", action: openWebsite)
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
            viewModel.start(monitorPlayback: monitorsPlayback)
        }
        .onDisappear {
            viewModel.handleScreenDisappear()
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
                            Text(EpisodeDisplayFormatter.title(for: episode.title))
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

    private func closePlayer() {
        viewModel.stop()
        onClose()
    }

    private func openWebsite() {
        viewModel.stop()
        onOpenWebsite()
    }

    private var playbackMenu: some View {
        Menu {
            if viewModel.shouldShowEpisodeControl {
                Button(action: viewModel.playPreviousEpisode) {
                    Label("Previous Episode", systemImage: "backward.end.fill")
                }
                .disabled(viewModel.previousEpisode == nil)
                .accessibilityIdentifier("previousEpisode")

                Button(action: viewModel.playNextEpisode) {
                    Label("Next Episode", systemImage: "forward.end.fill")
                }
                .disabled(viewModel.nextEpisode == nil)
                .accessibilityIdentifier("nextEpisode")

                Divider()
            }

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

            if let timerLabel = viewModel.sleepTimer.remainingLabel() {
                Label(timerLabel, systemImage: "moon.zzz")
            }

            if viewModel.shouldShowEpisodeControl {
                Button {
                    viewModel.setAutoplayNext(!viewModel.autoplayNext)
                } label: {
                    Label(
                        viewModel.autoplayNext ? "Disable Autoplay Next" : "Enable Autoplay Next",
                        systemImage: viewModel.autoplayNext ? "autostartstop.slash" : "autostartstop"
                    )
                }
            }

            Divider()

            Button(action: openWebsite) {
                Label("Open Website", systemImage: "safari")
            }
            .accessibilityIdentifier("openWebsiteFallback")
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("playbackSettings")
    }
}

enum EpisodeDisplayFormatter {
    static func title(for providerTitle: String) -> String {
        providerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ViewerMetricsBar: View {
    let metrics: ViewerMetrics

    var body: some View {
        HStack(spacing: 0) {
            if let likes = metrics.likes {
                metric("hand.thumbsup.fill", value: CompactMetricFormatter.count(likes), label: "Likes", id: "viewerMetric-likes")
            }
            if let favorites = metrics.favorites {
                metric("bookmark.fill", value: CompactMetricFormatter.count(favorites), label: "Favorites", id: "viewerMetric-favorites")
            }
            if let score = metrics.score {
                metric("star.fill", value: CompactMetricFormatter.score(score), label: "Score", id: "viewerMetric-score")
            }
            if let views = metrics.views {
                metric("flame.fill", value: CompactMetricFormatter.count(views), label: "Views", id: "viewerMetric-views")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .foregroundStyle(.white.opacity(0.88))
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.12))
        }
    }

    private func metric(_ icon: String, value: String, label: String, id: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(label == "Score" ? .yellow : .secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityIdentifier(id)
    }
}

private struct NativePlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let onFullScreenChanged: (Bool) -> Void
    let onPictureInPictureChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFullScreenChanged: onFullScreenChanged,
            onPictureInPictureChanged: onPictureInPictureChanged
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
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

    final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate {
        private let onFullScreenChanged: (Bool) -> Void
        private let onPictureInPictureChanged: (Bool) -> Void

        init(
            onFullScreenChanged: @escaping (Bool) -> Void,
            onPictureInPictureChanged: @escaping (Bool) -> Void
        ) {
            self.onFullScreenChanged = onFullScreenChanged
            self.onPictureInPictureChanged = onPictureInPictureChanged
        }

        @MainActor func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            onFullScreenChanged(true)
        }

        @MainActor func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { [onFullScreenChanged] _ in
                if !coordinator.isCancelled {
                    onFullScreenChanged(false)
                }
            }
        }

        @MainActor func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            onPictureInPictureChanged(true)
        }

        @MainActor func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            onPictureInPictureChanged(false)
        }

        @MainActor func playerViewController(
            _ playerViewController: AVPlayerViewController,
            failedToStartPictureInPictureWithError error: any Error
        ) {
            onPictureInPictureChanged(false)
        }
    }
}
