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
    @Published private(set) var qualityOptions: [PlaybackQualityOption] = []
    @Published private(set) var selectedQuality: PlaybackQualityOption?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackPosition = 0.0
    @Published private(set) var playbackDuration = 0.0
    @Published private(set) var isLoadingEpisodes = false
    @Published private(set) var episodeErrorMessage: String?
    @Published private(set) var skipOpportunity: SkipOpportunity?
    @Published private(set) var canUndoSkip = false

    let item: AiyifanItem
    var preparedPlayerItems: [AVPlayerItem] { playbackItems }

    private let resolver: any NativePlaybackResolving
    private let playedItemsStore: PlayedItemsStore?
    private let castManager: any CastPlaybackManaging
    private let preferences: PlaybackPreferencesStore
    private let qualityLoader: any PlaybackQualityLoading
    private let qualityPreferences: PlaybackQualityPreferenceStore
    private let skipMarkerStore: SkipMarkerStore
    private var playbackItems: [AVPlayerItem] = []
    private var playbackEntries: [NativePlaybackEntry] = []
    private var loadTask: Task<Void, Never>?
    private var qualityTask: Task<Void, Never>?
    private var episodeLoadTask: Task<Void, Never>?
    private var requestedEpisodeKey: String?
    private var lastRecordedPosition: Double?
    private var autoplayTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var undoSkipPosition: Double?
    private var undoSkipTask: Task<Void, Never>?
    private var fingerprintSampler: SkipFingerprintSampler?
    private var fingerprintCaptureTask: Task<Void, Never>?
    private var isApplicationActive = true
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

    var usesAutomaticQuality: Bool {
        !qualityPreferences.hasManualSelection
    }

    var manualQualityOptions: [PlaybackQualityOption] {
        qualityOptions.count > 1 ? qualityOptions : []
    }

    var qualityAvailabilityText: String {
        guard let onlyQuality = qualityOptions.first, qualityOptions.count == 1 else {
            return "Stream quality unavailable"
        }
        return "\(onlyQuality.title) only"
    }

    var supportsSkip: Bool {
        expectsEpisodes
    }

    var episodeControlTitle: String? {
        guard shouldShowEpisodeControl else {
            return nil
        }
        guard let selectedEpisode, !episodes.isEmpty else {
            if episodeErrorMessage != nil {
                return "Retry Episodes"
            }
            return isLoading || isLoadingEpisodes ? "Loading Episodes" : "Select Episode"
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
        preferences: PlaybackPreferencesStore = PlaybackPreferencesStore(),
        qualityLoader: any PlaybackQualityLoading = AVAssetPlaybackQualityLoader(),
        qualityPreferences: PlaybackQualityPreferenceStore = PlaybackQualityPreferenceStore(),
        skipMarkerStore: SkipMarkerStore = SkipMarkerStore()
    ) {
        self.item = item
        expectsEpisodes = SerialPlaybackIntent.infer(
            providerIsSerial: false,
            item: item,
            preferredEpisodeKey: initialEpisodeKey
        )
        requestedEpisodeKey = initialEpisodeKey
        self.resolver = resolver
        self.playedItemsStore = playedItemsStore
        self.castManager = castManager
        self.preferences = preferences
        self.qualityLoader = qualityLoader
        self.qualityPreferences = qualityPreferences
        self.skipMarkerStore = skipMarkerStore
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
        attachTimeObserver()
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
        qualityTask?.cancel()
        episodeLoadTask?.cancel()
        cancelAutoplay()
        loadTask = Task { [weak self] in
            await self?.prepareAndPlay()
        }
    }

    func stop() {
        persistProgress()
        finishFingerprintSampling()
        loadTask?.cancel()
        loadTask = nil
        qualityTask?.cancel()
        qualityTask = nil
        episodeLoadTask?.cancel()
        episodeLoadTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        detachTimeObserver()
        clearUndoSkip()
        fingerprintCaptureTask?.cancel()
        fingerprintCaptureTask = nil
        cancelAutoplay()
        player.pause()
        isPlaying = false
        playbackPosition = 0
        playbackDuration = 0
        player.removeAllItems()
        playbackItems = []
        playbackEntries = []
        qualityOptions = []
        selectedQuality = nil
        isLoadingEpisodes = false
        episodeErrorMessage = nil
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
        finishFingerprintSampling()
        requestedEpisodeKey = episode.mediaKey
        beginLoad()
    }

    func retryEpisodes() {
        beginEpisodeLoad()
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

    func play() {
        guard player.currentItem != nil, !castManager.isCasting else { return }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlaying(
            position: player.currentTime().seconds,
            duration: player.currentItem?.duration.seconds ?? 0
        )
    }

    func pause() {
        player.pause()
        isPlaying = false
        persistProgress()
        updateNowPlaying(
            position: player.currentTime().seconds,
            duration: player.currentItem?.duration.seconds ?? 0
        )
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func skipBackward10Seconds() {
        seekCurrentProgram(by: -10)
    }

    func skipForward10Seconds() {
        seekCurrentProgram(by: 10)
    }

    func seekCurrentProgram(to position: Double) {
        guard let currentItem = player.currentItem, !castManager.isCasting else { return }
        let duration = currentItem.duration.seconds
        let target: Double
        if duration.isFinite, duration > 0 {
            target = min(max(0, position), duration)
        } else {
            target = max(0, position)
        }
        guard target.isFinite else { return }
        cancelAutoplay()
        playbackPosition = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        castManager.updateProgramPosition(target)
        updateNowPlaying(position: target, duration: duration)
    }

    private func seekCurrentProgram(by interval: Double) {
        guard let currentItem = player.currentItem, !castManager.isCasting else {
            return
        }
        let current = currentItem.currentTime().seconds
        guard current.isFinite else {
            return
        }
        seekCurrentProgram(to: current + interval)
    }

    func performSkip() {
        guard let opportunity = skipOpportunity else { return }
        let origin = playbackPosition
        seekCurrentProgram(to: opportunity.target)
        undoSkipPosition = origin
        canUndoSkip = true
        undoSkipTask?.cancel()
        undoSkipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SkipDetectionPolicy.standard.undoDuration))
            guard !Task.isCancelled else { return }
            self?.clearUndoSkip()
        }
    }

    func undoSkip() {
        guard let origin = undoSkipPosition else { return }
        clearUndoSkip()
        seekCurrentProgram(to: origin)
    }

    func setIntroEndHere() {
        guard supportsSkip, playbackPosition > 0 else { return }
        _ = skipMarkerStore.setIntroEnd(
            seriesID: item.id,
            time: playbackPosition,
            referenceDuration: playbackDuration > 0 ? playbackDuration : nil
        )
        updateSkipOpportunity()
    }

    func setOutroStartHere() {
        guard supportsSkip, playbackDuration > playbackPosition else { return }
        _ = skipMarkerStore.setOutroStart(
            seriesID: item.id,
            secondsRemaining: playbackDuration - playbackPosition,
            referenceDuration: playbackDuration
        )
        updateSkipOpportunity()
    }

    func disableSkipForSeries() {
        guard supportsSkip else { return }
        _ = skipMarkerStore.disable(seriesID: item.id)
        clearUndoSkip()
        updateSkipOpportunity()
    }

    func resetLearnedSkipTiming() {
        guard supportsSkip else { return }
        _ = skipMarkerStore.reset(seriesID: item.id)
        clearUndoSkip()
        updateSkipOpportunity()
    }

    func setQuality(_ quality: PlaybackQualityOption) {
        guard let available = qualityOptions.first(where: { $0.id == quality.id }) else {
            return
        }
        qualityPreferences.setTargetHeight(available.tierHeight)
        selectedQuality = available
        playbackItems.forEach { apply(available, to: $0) }
    }

    func setAutomaticQuality() {
        qualityPreferences.setAutomatic()
        guard let automatic = PlaybackQualitySelector.select(
            from: qualityOptions,
            targetHeight: PlaybackQualityPreferenceStore.defaultTargetHeight,
            fallbackToHighest: true
        ) else {
            selectedQuality = nil
            playbackItems.forEach(applyInitialQualityPreference)
            return
        }
        selectedQuality = automatic
        playbackItems.forEach { apply(automatic, to: $0) }
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
        if active {
            pauseFingerprintSampling()
        }
    }

    func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        if !active {
            pauseFingerprintSampling()
        }
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
        qualityOptions = []
        selectedQuality = nil
        isLoadingEpisodes = false
        episodeErrorMessage = nil
        pendingResumePosition = 0
        lastRecordedPosition = nil
        progressState = PlaybackProgressState()
        hasAppliedResume = false
        preparedEntryCount = 0
        player.pause()
        isPlaying = false
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
            items.forEach(applyInitialQualityPreference)
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
                isPlaying = false
            } else {
                player.playImmediately(atRate: playbackRate)
                isPlaying = true
            }
            if let programURL = programEntries.first?.url {
                beginQualityLoad(for: programURL)
            }
            if expectsEpisodes, episodes.isEmpty {
                beginEpisodeLoad()
            }
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func beginEpisodeLoad() {
        guard let loader = resolver as? any EpisodePlaylistResolving else { return }
        episodeLoadTask?.cancel()
        isLoadingEpisodes = true
        episodeErrorMessage = nil
        let expectedEpisodeKey = selectedEpisode?.mediaKey
            ?? requestedEpisodeKey
            ?? item.latestEpisodeKey
        episodeLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedEpisodes = try await loader.loadEpisodes(
                    for: item,
                    expectedEpisodeKey: expectedEpisodeKey
                )
                try Task.checkCancellation()
                episodes = loadedEpisodes
                if let currentKey = selectedEpisode?.mediaKey,
                   let recoveredSelection = loadedEpisodes.first(where: { $0.mediaKey == currentKey }) {
                    selectedEpisode = recoveredSelection
                    episodeTitle = recoveredSelection.title
                }
                isLoadingEpisodes = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isLoadingEpisodes = false
                episodeErrorMessage = "The episode list could not be loaded."
            }
        }
    }

    private func beginQualityLoad(for url: URL) {
        qualityTask?.cancel()
        qualityTask = Task { [weak self] in
            guard let self else { return }
            do {
                let options = try await qualityLoader.loadOptions(for: url)
                try Task.checkCancellation()
                qualityOptions = options
                guard let quality = PlaybackQualitySelector.select(
                    from: options,
                    targetHeight: qualityPreferences.targetHeight,
                    fallbackToHighest: !qualityPreferences.hasManualSelection
                ) else {
                    selectedQuality = nil
                    return
                }
                selectedQuality = quality
                playbackItems.forEach { apply(quality, to: $0) }
            } catch {
                guard !Task.isCancelled else { return }
                qualityOptions = []
                selectedQuality = nil
            }
        }
    }

    private func apply(_ quality: PlaybackQualityOption, to item: AVPlayerItem) {
        item.preferredMaximumResolution = CGSize(
            width: quality.width,
            height: quality.height
        )
        item.preferredPeakBitRate = quality.peakBitRate ?? quality.averageBitRate ?? 0
    }

    private func applyInitialQualityPreference(to item: AVPlayerItem) {
        let height = qualityPreferences.targetHeight
        item.preferredMaximumResolution = CGSize(
            width: Int((Double(height) * 16 / 9).rounded()),
            height: height
        )
        item.preferredPeakBitRate = 0
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
            isPlaying = false
            return
        }

        isPlaying = player.timeControlStatus == .playing

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
        if position.isFinite, duration.isFinite, duration > 0 {
            isLoading = false
            errorMessage = nil
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
        isPlaying = false
        sleepTimer = .off
        cancelAutoplay()
    }

    private func attachTimeObserver() {
        detachTimeObserver()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updatePlaybackTimeline(position: time.seconds)
            }
        }
    }

    private func detachTimeObserver() {
        guard let timeObserver else {
            return
        }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func updatePlaybackTimeline(position: Double) {
        guard position.isFinite else {
            return
        }
        playbackPosition = max(0, position)
        let duration = player.currentItem?.duration.seconds ?? 0
        playbackDuration = duration.isFinite ? max(0, duration) : 0
        updateSkipOpportunity()
        captureFingerprintIfNeeded()
    }

    private func updateNowPlaying(position: Double, duration: Double) {
        let isPlaying = player.timeControlStatus == .playing
        playbackPosition = position.isFinite ? max(0, position) : playbackPosition
        playbackDuration = duration.isFinite ? max(0, duration) : playbackDuration
        updateSkipOpportunity()
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

    private func updateSkipOpportunity() {
        skipOpportunity = SkipOpportunityProjector.project(
            profile: skipMarkerStore.profile(for: item.id),
            playback: SkipPlaybackState(
                isSerial: supportsSkip,
                isAdvertisement: false,
                isLoading: isLoading,
                isSeeking: false,
                isSeekable: !castManager.isCasting,
                position: playbackPosition,
                duration: playbackDuration
            )
        )
    }

    private func clearUndoSkip() {
        undoSkipTask?.cancel()
        undoSkipTask = nil
        undoSkipPosition = nil
        canUndoSkip = false
    }

    private func captureFingerprintIfNeeded() {
        guard
            supportsSkip,
            let selectedEpisode,
            let currentItem = player.currentItem,
            playbackDuration > 0,
            fingerprintCaptureTask == nil,
            !skipMarkerStore.isDisabled(seriesID: item.id)
        else {
            return
        }

        if fingerprintSampler == nil {
            fingerprintSampler = SkipFingerprintSampler(
                seriesID: item.id,
                episodeID: selectedEpisode.mediaKey,
                duration: playbackDuration,
                playerItem: currentItem,
                hasher: DefaultSkipFrameHasher()
            )
        }

        let state = SkipSamplingRuntimeState(
            isProgram: true,
            isReadyToPlay: currentItem.status == .readyToPlay,
            isLoading: isLoading,
            isSeeking: false,
            isPictureInPictureActive: presentationState.isPictureInPictureActive,
            isPictureInPictureTransitioning: false,
            isCasting: castManager.isCasting,
            isAppSuspended: !isApplicationActive,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isUnderMemoryPressure: false
        )
        let position = playbackPosition
        fingerprintCaptureTask = Task { [weak self] in
            guard let self, let sampler = self.fingerprintSampler else { return }
            _ = await sampler.capture(at: position, state: state)
            self.fingerprintCaptureTask = nil
        }
    }

    private func pauseFingerprintSampling() {
        fingerprintCaptureTask?.cancel()
        fingerprintCaptureTask = nil
        fingerprintSampler?.updateRuntimeState(SkipSamplingRuntimeState(
            isProgram: true,
            isReadyToPlay: false,
            isLoading: true,
            isSeeking: false,
            isPictureInPictureActive: presentationState.isPictureInPictureActive,
            isPictureInPictureTransitioning: false,
            isCasting: castManager.isCasting,
            isAppSuspended: !isApplicationActive,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isUnderMemoryPressure: false
        ))
    }

    private func finishFingerprintSampling() {
        let hadCaptureInFlight = fingerprintCaptureTask != nil
        fingerprintCaptureTask?.cancel()
        fingerprintCaptureTask = nil
        guard let sampler = fingerprintSampler else { return }
        fingerprintSampler = nil
        if hadCaptureInFlight {
            sampler.cancel()
            return
        }
        guard let fingerprint = try? sampler.complete() else { return }
        _ = skipMarkerStore.save(fingerprint: fingerprint)
        let fingerprints = skipMarkerStore.fingerprints(for: item.id)
        let seriesID = item.id
        let detectionStartedAt = Date()
        let detection = Task.detached(priority: .utility) {
            SkipMarkerDetector().detect(
                seriesID: seriesID,
                fingerprints: fingerprints,
                detectedAt: detectionStartedAt
            )
        }
        Task { [weak self] in
            guard let self, let profile = await detection.value else { return }
            _ = self.skipMarkerStore.save(profile: profile)
            self.updateSkipOpportunity()
        }
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

    @ObservedObject private var viewModel: NativePlayerViewModel
    @StateObject private var castManager = GoogleCastManager.shared
    @State private var isShowingEpisodes = false
    @State private var isShowingFullScreenPlayer = false
    @State private var isShowingPlaybackChrome = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: NativePlayerViewModel,
        onClose: @escaping () -> Void,
        onOpenWebsite: @escaping () -> Void
    ) {
        self.item = viewModel.item
        self.onClose = onClose
        self.onOpenWebsite = onOpenWebsite
        self.viewModel = viewModel
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
                            if viewModel.episodes.isEmpty, viewModel.episodeErrorMessage != nil {
                                viewModel.retryEpisodes()
                            } else {
                                isShowingEpisodes = true
                            }
                        } label: {
                            Text(episodeTitle)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(minHeight: 44)
                        }
                        .disabled(viewModel.episodes.isEmpty && viewModel.episodeErrorMessage == nil)
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
                    onPictureInPictureChanged: viewModel.setPictureInPictureActive,
                    showsPlaybackControls: false
                )
                .ignoresSafeArea(edges: .bottom)
                .contentShape(Rectangle())
                .onTapGesture(perform: togglePlaybackChrome)

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
                    .padding(.trailing, 16)
                    .padding(.bottom, 108)
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

                if viewModel.errorMessage == nil, isShowingPlaybackChrome {
                    PlaybackChromeOverlay(
                        viewModel: viewModel,
                        isCasting: castManager.isCasting,
                        enterFullScreen: enterFullScreen
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
            .background(Color.black)
        }
        .background(Color.black)
        .accessibilityHidden(isShowingFullScreenPlayer)
        .onChange(of: scenePhase) { _, phase in
            viewModel.setApplicationActive(phase == .active)
            if phase != .active {
                viewModel.persistProgress()
            }
        }
        .onChange(of: castManager.isCasting) { _, isCasting in
            if isCasting {
                viewModel.persistProgress()
                viewModel.pause()
                viewModel.setApplicationActive(false)
            } else {
                viewModel.setApplicationActive(scenePhase == .active)
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
        .fullScreenCover(isPresented: $isShowingFullScreenPlayer) {
            FullScreenNativePlayerScreen(
                viewModel: viewModel,
                dismiss: exitFullScreen
            )
        }
    }

    private func closePlayer() {
        onClose()
    }

    private func togglePlaybackChrome() {
        guard viewModel.errorMessage == nil else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingPlaybackChrome.toggle()
        }
    }

    private func enterFullScreen() {
        viewModel.setFullScreenPresentationActive(true)
        isShowingPlaybackChrome = false
        isShowingFullScreenPlayer = true
    }

    private func exitFullScreen() {
        isShowingFullScreenPlayer = false
        viewModel.setFullScreenPresentationActive(false)
    }

    private func openWebsite() {
        viewModel.stop()
        onOpenWebsite()
    }

    private var playbackMenu: some View {
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

            Menu("Quality") {
                Button {
                    viewModel.setAutomaticQuality()
                } label: {
                    if viewModel.usesAutomaticQuality {
                        Label("Automatic (prefers 1080p)", systemImage: "checkmark")
                    } else {
                        Text("Automatic (prefers 1080p)")
                    }
                }
                .accessibilityIdentifier("automaticPlaybackQuality")

                if viewModel.manualQualityOptions.isEmpty {
                    Text(viewModel.qualityAvailabilityText)
                } else {
                    Divider()
                    ForEach(viewModel.manualQualityOptions) { quality in
                        Button {
                            viewModel.setQuality(quality)
                        } label: {
                            if !viewModel.usesAutomaticQuality,
                               quality.id == viewModel.selectedQuality?.id {
                                Label(quality.title, systemImage: "checkmark")
                            } else {
                                Text(quality.title)
                            }
                        }
                        .accessibilityIdentifier("playbackQuality-\(quality.tierHeight)")
                    }
                }
            }
            .accessibilityIdentifier("playbackQuality")

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

                if viewModel.supportsSkip {
                    Divider()

                    Button("Set Intro End Here", systemImage: "forward.end") {
                        viewModel.setIntroEndHere()
                    }
                    Button("Set Outro Start Here", systemImage: "backward.end") {
                        viewModel.setOutroStartHere()
                    }
                    Button("Disable Skip for This Series", systemImage: "nosign") {
                        viewModel.disableSkipForSeries()
                    }
                    Button("Reset Learned Timing", systemImage: "arrow.counterclockwise", role: .destructive) {
                        viewModel.resetLearnedSkipTiming()
                    }
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

private struct PlaybackChromeOverlay: View {
    @ObservedObject var viewModel: NativePlayerViewModel
    let isCasting: Bool
    let enterFullScreen: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                let videoFrame = videoFrame(in: proxy.size)
                centerTransportControls(in: videoFrame)
                topLeftFullScreenButton(in: videoFrame)

                VStack {
                    Spacer()

                    if viewModel.canUndoSkip || viewModel.skipOpportunity != nil {
                        Button(viewModel.canUndoSkip ? "Undo Skip" : skipButtonTitle) {
                            if viewModel.canUndoSkip {
                                viewModel.undoSkip()
                            } else {
                                viewModel.performSkip()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .foregroundStyle(.black)
                        .accessibilityIdentifier(viewModel.canUndoSkip ? "undoSkip" : "performSkip")
                        .padding(.bottom, 8)
                    }

                    bottomTimeline
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var skipButtonTitle: String {
        viewModel.skipOpportunity?.kind == .outro ? "Skip Outro" : "Skip Intro"
    }

    private var bottomTimeline: some View {
        HStack(spacing: 4) {
            if viewModel.shouldShowEpisodeControl {
                iconButton(
                    systemName: "backward.end.fill",
                    label: "Previous Episode",
                    identifier: "previousEpisode",
                    disabled: viewModel.previousEpisode == nil,
                    action: viewModel.playPreviousEpisode
                )
            }

            Text(timeLabel(viewModel.playbackPosition))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 42, alignment: .trailing)
                .accessibilityIdentifier("playbackElapsedTime")

            Slider(
                value: Binding(
                    get: { viewModel.playbackPosition },
                    set: { viewModel.seekCurrentProgram(to: $0) }
                ),
                in: 0...max(viewModel.playbackDuration, 1)
            )
            .tint(.white)
            .disabled(isCasting || viewModel.isLoading || viewModel.playbackDuration <= 0)
            .accessibilityLabel("Playback Timeline")
            .accessibilityIdentifier("playbackTimeline")

            Text(remainingTimeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(width: 52, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("playbackRemainingTime")

            if viewModel.shouldShowEpisodeControl {
                iconButton(
                    systemName: "forward.end.fill",
                    label: "Next Episode",
                    identifier: "nextEpisode",
                    disabled: viewModel.nextEpisode == nil,
                    action: viewModel.playNextEpisode
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.72))
        .clipShape(Capsule(style: .continuous))
    }

    private func topLeftFullScreenButton(in videoFrame: CGRect) -> some View {
        let buttonSize: CGFloat = 44
        let videoInset: CGFloat = 12
        return iconButton(
            systemName: "arrow.up.left.and.arrow.down.right",
            label: "Enter Full Screen",
            identifier: "enterFullScreen",
            disabled: false,
            action: enterFullScreen
        )
        .position(
            x: videoFrame.minX + videoInset + (buttonSize / 2),
            y: videoFrame.minY + videoInset + (buttonSize / 2)
        )
    }

    private func centerTransportControls(in videoFrame: CGRect) -> some View {
        return HStack(spacing: 28) {
            transportButton(
                systemName: "gobackward.10",
                label: "Rewind 10 seconds",
                identifier: "skipBackward10Seconds",
                size: 48,
                disabled: isCasting || viewModel.isLoading,
                action: viewModel.skipBackward10Seconds
            )

            transportButton(
                systemName: viewModel.isPlaying ? "pause.fill" : "play.fill",
                label: viewModel.isPlaying ? "Pause" : "Play",
                identifier: "toggleNativePlayback",
                size: 58,
                disabled: isCasting || viewModel.isLoading,
                action: viewModel.togglePlayback
            )

            transportButton(
                systemName: "goforward.10",
                label: "Forward 10 seconds",
                identifier: "skipForward10Seconds",
                size: 48,
                disabled: isCasting || viewModel.isLoading,
                action: viewModel.skipForward10Seconds
            )
        }
        .position(x: videoFrame.midX, y: videoFrame.midY)
        .padding(.horizontal, 16)
    }

    private func videoFrame(in availableSize: CGSize) -> CGRect {
        guard availableSize.width > 0, availableSize.height > 0 else {
            return CGRect(origin: .zero, size: availableSize)
        }
        let videoAspectRatio = 16.0 / 9.0
        let containerAspectRatio = availableSize.width / availableSize.height
        let videoSize: CGSize
        if containerAspectRatio > videoAspectRatio {
            videoSize = CGSize(
                width: availableSize.height * videoAspectRatio,
                height: availableSize.height
            )
        } else {
            videoSize = CGSize(
                width: availableSize.width,
                height: availableSize.width / videoAspectRatio
            )
        }
        return CGRect(
            x: (availableSize.width - videoSize.width) / 2,
            y: (availableSize.height - videoSize.height) / 2,
            width: videoSize.width,
            height: videoSize.height
        )
    }

    private var remainingTimeLabel: String {
        guard viewModel.playbackDuration > 0 else {
            return "-0:00"
        }
        let remaining = max(0, viewModel.playbackDuration - viewModel.playbackPosition)
        return "-\(timeLabel(remaining))"
    }

    private func timeLabel(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func iconButton(
        systemName: String,
        label: String,
        identifier: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(disabled ? Color.white.opacity(0.08) : Color.white.opacity(0.16))
                .clipShape(Circle())
        }
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func transportButton(
        systemName: String,
        label: String,
        identifier: String,
        size: CGFloat,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size == 58 ? 24 : 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(disabled ? 0.34 : 0.54))
                .clipShape(Circle())
        }
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
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

private struct FullScreenNativePlayerScreen: View {
    @ObservedObject var viewModel: NativePlayerViewModel
    let dismiss: () -> Void

    @State private var isShowingFullScreenChrome = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            NativePlayerController(
                player: viewModel.player,
                onFullScreenChanged: viewModel.setFullScreenPresentationActive,
                onPictureInPictureChanged: viewModel.setPictureInPictureActive,
                showsPlaybackControls: true
            )
            .ignoresSafeArea()

            if !isShowingFullScreenChrome {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: showFullScreenChrome)
                    .accessibilityHidden(true)
            }

            if isShowingFullScreenChrome {
                Button(action: dismiss) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.42))
                        .clipShape(Circle())
                }
                .padding(16)
                .accessibilityLabel("Exit Full Screen")
                .accessibilityIdentifier("exitFullScreen")
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .onDisappear {
            viewModel.setFullScreenPresentationActive(false)
        }
    }

    private func showFullScreenChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingFullScreenChrome = true
        }
    }
}

private struct NativePlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let onFullScreenChanged: (Bool) -> Void
    let onPictureInPictureChanged: (Bool) -> Void
    let showsPlaybackControls: Bool

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
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = showsPlaybackControls
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
