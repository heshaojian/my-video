import AVKit
import SwiftUI

enum CastSessionPhase: String, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case loading
    case playing
    case paused
    case failed
}

struct CastSessionSnapshot: Equatable, Sendable {
    let phase: CastSessionPhase
    let receiverName: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let position: Double
    let duration: Double
    let isMuted: Bool
    let isAdvertisement: Bool
    let errorMessage: String?

    init(
        phase: CastSessionPhase = .disconnected,
        receiverName: String = "",
        title: String = "",
        subtitle: String? = nil,
        artworkURL: URL? = nil,
        position: Double = 0,
        duration: Double = 0,
        isMuted: Bool = false,
        isAdvertisement: Bool = false,
        errorMessage: String? = nil
    ) {
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        let nonnegativePosition = position.isFinite ? max(0, position) : 0
        self.phase = phase
        self.receiverName = receiverName
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.duration = safeDuration
        self.position = safeDuration > 0 ? min(nonnegativePosition, safeDuration) : nonnegativePosition
        self.isMuted = isMuted
        self.isAdvertisement = isAdvertisement
        self.errorMessage = errorMessage
    }

    var isPlaying: Bool {
        phase == .playing
    }

    var hasError: Bool {
        phase == .failed || errorMessage != nil
    }

    var progress: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }
}

struct CastQueueEntry: Equatable, Sendable {
    let url: URL
    let isAdvertisement: Bool
    let startPosition: Double
    let contentType: String
}

struct CastPlaybackPlan: Equatable, Sendable {
    let entries: [CastQueueEntry]
    let title: String
    let subtitle: String?
    let artworkURL: URL?
}

@MainActor
protocol CastPlaybackManaging: AnyObject {
    var isCasting: Bool { get }

    func configure()
    func prepare(_ plan: CastPlaybackPlan, loadIfConnected: Bool)
    func updateProgramPosition(_ position: Double)
    func clear()
}

enum CastPlaybackPlanError: Error, Equatable {
    case missingProgram
}

struct CastMuteState: Equatable, Sendable {
    let previousMute: Bool?
    let desiredMute: Bool?

    init(previousMute: Bool? = nil, desiredMute: Bool? = nil) {
        self.previousMute = previousMute
        self.desiredMute = desiredMute
    }

    func transition(isAdvertisement: Bool, receiverIsMuted: Bool) -> CastMuteState {
        if isAdvertisement {
            return CastMuteState(
                previousMute: previousMute ?? receiverIsMuted,
                desiredMute: true
            )
        }
        return CastMuteState(
            previousMute: nil,
            desiredMute: previousMute
        )
    }
}

enum CastPlaybackPlanBuilder {
    static func make(
        item: MyVideoItem,
        playback: NativePlayback,
        programPosition: Double
    ) throws -> CastPlaybackPlan {
        let programEntries = playback.entries.filter { !$0.isAdvertisement }
        guard !programEntries.isEmpty else {
            throw CastPlaybackPlanError.missingProgram
        }
        let safePosition = programPosition.isFinite ? max(0, programPosition) : 0
        let entries = programEntries.map { entry in
            CastQueueEntry(
                url: entry.url,
                isAdvertisement: false,
                startPosition: safePosition,
                contentType: contentType(for: entry.url)
            )
        }
        return CastPlaybackPlan(
            entries: entries,
            title: item.title,
            subtitle: playback.selectedEpisode.map { "Episode \($0.title)" },
            artworkURL: item.thumbnailURL
        )
    }

    private static func contentType(for url: URL) -> String {
        url.pathExtension.lowercased() == "m3u8" ? "application/x-mpegURL" : "video/mp4"
    }
}

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = .systemCyan
        picker.isAccessibilityElement = true
        picker.accessibilityTraits = .button
        picker.accessibilityLabel = "AirPlay"
        picker.accessibilityIdentifier = "airPlayButton"
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

#if canImport(GoogleCast)
import GoogleCast

@MainActor
final class GoogleCastManager: NSObject, ObservableObject, CastPlaybackManaging {
    static let shared = GoogleCastManager()

    @Published private(set) var snapshot = CastSessionSnapshot()

    var isCasting: Bool {
        snapshot.phase != .disconnected
    }

    private var isConfigured = false
    private var preparedPlan: CastPlaybackPlan?
    private var muteState = CastMuteState()
    private weak var mediaClient: GCKRemoteMediaClient?
    private let simulatesSession = ProcessInfo.processInfo.arguments.contains("-MyVideoSimulateCastSession")

    func configure() {
        guard !isConfigured else {
            return
        }
        if simulatesSession {
            snapshot = CastSessionSnapshot(
                phase: .paused,
                receiverName: "Living Room TV",
                title: "Fixture Series",
                subtitle: "Episode 04",
                artworkURL: URL(string: "https://images.example.com/poster.jpg"),
                position: 420,
                duration: 1_800
            )
            isConfigured = true
            return
        }
        if !GCKCastContext.isSharedInstanceInitialized() {
            let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
            let options = GCKCastOptions(discoveryCriteria: criteria)
            options.suspendSessionsWhenBackgrounded = false
            GCKCastContext.setSharedInstanceWith(options)
        }
        let sessionManager = GCKCastContext.sharedInstance().sessionManager
        sessionManager.add(self)
        isConfigured = true
        if let currentSession = sessionManager.currentSession, sessionManager.hasConnectedCastSession() {
            handleConnectedSession(currentSession, shouldLoad: false)
        }
    }

    func prepare(_ plan: CastPlaybackPlan, loadIfConnected: Bool) {
        preparedPlan = plan
        snapshot = snapshot(applying: plan)
        guard loadIfConnected, isCasting else {
            return
        }
        loadPreparedPlan()
    }

    func updateProgramPosition(_ position: Double) {
        guard !isCasting, position.isFinite, position >= 0, let plan = preparedPlan else {
            return
        }
        preparedPlan = CastPlaybackPlan(
            entries: plan.entries.map { entry in
                CastQueueEntry(
                    url: entry.url,
                    isAdvertisement: entry.isAdvertisement,
                    startPosition: entry.isAdvertisement ? 0 : position,
                    contentType: entry.contentType
                )
            },
            title: plan.title,
            subtitle: plan.subtitle,
            artworkURL: plan.artworkURL
        )
    }

    func clear() {
        if !isCasting {
            preparedPlan = nil
        }
    }

    func togglePlayback() {
        if simulatesSession {
            snapshot = replacingSnapshot(phase: snapshot.isPlaying ? .paused : .playing)
            return
        }
        if snapshot.isPlaying {
            mediaClient?.pause()
        } else {
            mediaClient?.play()
        }
    }

    func seek(to position: Double) {
        let safePosition = position.isFinite ? max(0, position) : 0
        let clampedPosition = snapshot.duration > 0 ? min(safePosition, snapshot.duration) : safePosition
        if simulatesSession {
            snapshot = replacingSnapshot(position: clampedPosition)
            return
        }
        let options = GCKMediaSeekOptions()
        options.interval = clampedPosition
        options.relative = false
        mediaClient?.seek(with: options)
    }

    func skip(by interval: Double) {
        seek(to: snapshot.position + interval)
    }

    func toggleMute() {
        guard !snapshot.isAdvertisement else {
            return
        }
        if simulatesSession {
            snapshot = replacingSnapshot(isMuted: !snapshot.isMuted)
            return
        }
        GCKCastContext.sharedInstance().sessionManager.currentSession?.setDeviceMuted(!snapshot.isMuted)
    }

    func retry() {
        snapshot = replacingSnapshot(phase: .loading, errorMessage: nil, preserveError: false)
        if simulatesSession {
            snapshot = replacingSnapshot(phase: .paused)
        } else {
            loadPreparedPlan()
        }
    }

    func stopCasting() {
        if simulatesSession {
            resetSession()
            return
        }
        _ = GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
    }

    private func handleConnectedSession(_ session: GCKSession, shouldLoad: Bool) {
        mediaClient?.remove(self)
        mediaClient = session.remoteMediaClient
        mediaClient?.add(self)
        snapshot = replacingSnapshot(
            phase: .connected,
            receiverName: session.device.friendlyName ?? "Cast device",
            isMuted: session.currentDeviceMuted,
            errorMessage: nil,
            preserveError: false
        )
        if shouldLoad {
            loadPreparedPlan()
        }
    }

    private func loadPreparedPlan() {
        guard
            let plan = preparedPlan,
            let session = GCKCastContext.sharedInstance().sessionManager.currentSession,
            let client = session.remoteMediaClient
        else {
            return
        }

        snapshot = snapshot(applying: plan, phase: .loading, receiverName: session.device.friendlyName ?? "Cast device")
        snapshot = replacingSnapshot(
            phase: .loading,
            errorMessage: nil,
            preserveError: false
        )

        let queueItems = plan.entries.map { entry in
            let metadata = GCKMediaMetadata(metadataType: .movie)
            metadata.setString(entry.isAdvertisement ? "Advertisement" : plan.title, forKey: kGCKMetadataKeyTitle)
            if !entry.isAdvertisement, let subtitle = plan.subtitle {
                metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle)
            }
            if !entry.isAdvertisement, let artworkURL = plan.artworkURL {
                metadata.addImage(GCKImage(url: artworkURL, width: 600, height: 900))
            }

            let mediaBuilder = GCKMediaInformationBuilder(contentURL: entry.url)
            mediaBuilder.streamType = .buffered
            mediaBuilder.contentType = entry.contentType
            mediaBuilder.metadata = metadata

            let queueItemBuilder = GCKMediaQueueItemBuilder()
            queueItemBuilder.mediaInformation = mediaBuilder.build()
            queueItemBuilder.autoplay = true
            queueItemBuilder.startTime = entry.startPosition
            queueItemBuilder.customData = ["myvideoAdvertisement": entry.isAdvertisement]
            return queueItemBuilder.build()
        }

        let queueBuilder = GCKMediaQueueDataBuilder(queueType: .generic)
        queueBuilder.items = queueItems
        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.queueData = queueBuilder.build()
        requestBuilder.autoplay = true
        client.loadMedia(with: requestBuilder.build())
        applyMutePolicy(isAdvertisement: plan.entries.first?.isAdvertisement ?? false, session: session)
    }

    private func applyMutePolicy(isAdvertisement: Bool, session: GCKSession) {
        let nextState = muteState.transition(
            isAdvertisement: isAdvertisement,
            receiverIsMuted: session.currentDeviceMuted
        )
        muteState = nextState
        if let desiredMute = nextState.desiredMute, desiredMute != session.currentDeviceMuted {
            session.setDeviceMuted(desiredMute)
        }
        if let desiredMute = nextState.desiredMute {
            snapshot = replacingSnapshot(isMuted: desiredMute, isAdvertisement: isAdvertisement)
        } else {
            snapshot = replacingSnapshot(isAdvertisement: isAdvertisement)
        }
    }

    private func replacingSnapshot(
        phase: CastSessionPhase? = nil,
        receiverName: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        artworkURL: URL? = nil,
        position: Double? = nil,
        duration: Double? = nil,
        isMuted: Bool? = nil,
        isAdvertisement: Bool? = nil,
        errorMessage: String? = nil,
        preserveError: Bool = true
    ) -> CastSessionSnapshot {
        CastSessionSnapshot(
            phase: phase ?? snapshot.phase,
            receiverName: receiverName ?? snapshot.receiverName,
            title: title ?? snapshot.title,
            subtitle: subtitle ?? snapshot.subtitle,
            artworkURL: artworkURL ?? snapshot.artworkURL,
            position: position ?? snapshot.position,
            duration: duration ?? snapshot.duration,
            isMuted: isMuted ?? snapshot.isMuted,
            isAdvertisement: isAdvertisement ?? snapshot.isAdvertisement,
            errorMessage: preserveError ? snapshot.errorMessage : errorMessage
        )
    }

    private func snapshot(
        applying plan: CastPlaybackPlan,
        phase: CastSessionPhase? = nil,
        receiverName: String? = nil
    ) -> CastSessionSnapshot {
        CastSessionSnapshot(
            phase: phase ?? snapshot.phase,
            receiverName: receiverName ?? snapshot.receiverName,
            title: plan.title,
            subtitle: plan.subtitle,
            artworkURL: plan.artworkURL,
            position: snapshot.position,
            duration: snapshot.duration,
            isMuted: snapshot.isMuted,
            isAdvertisement: snapshot.isAdvertisement,
            errorMessage: snapshot.errorMessage
        )
    }

    private func resetSession() {
        mediaClient?.remove(self)
        mediaClient = nil
        snapshot = CastSessionSnapshot()
        muteState = CastMuteState()
    }
}

extension GoogleCastManager: @preconcurrency GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        handleConnectedSession(session, shouldLoad: true)
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didResume session: GCKSession) {
        handleConnectedSession(session, shouldLoad: false)
    }

    func sessionManager(
        _ sessionManager: GCKSessionManager,
        didEnd session: GCKSession,
        withError error: (any Error)?
    ) {
        resetSession()
    }
}

extension GoogleCastManager: @preconcurrency GCKRemoteMediaClientListener {
    func remoteMediaClient(
        _ client: GCKRemoteMediaClient,
        didUpdate mediaStatus: GCKMediaStatus?
    ) {
        guard let mediaStatus else {
            return
        }
        let phase: CastSessionPhase
        switch mediaStatus.playerState {
        case .playing:
            phase = .playing
        case .paused:
            phase = .paused
        case .buffering, .loading:
            phase = .loading
        case .idle where mediaStatus.idleReason == .error:
            phase = .failed
        case .idle:
            phase = .connected
        default:
            phase = snapshot.phase
        }
        let errorMessage = phase == .failed ? "The Cast receiver could not play this video." : nil
        snapshot = replacingSnapshot(
            phase: phase,
            position: mediaStatus.streamPosition,
            duration: mediaStatus.mediaInformation?.streamDuration,
            isMuted: GCKCastContext.sharedInstance().sessionManager.currentSession?.currentDeviceMuted,
            errorMessage: errorMessage,
            preserveError: false
        )

        if
            let value = mediaStatus.currentQueueItem?.customData as? [String: Any],
            let isAdvertisement = value["myvideoAdvertisement"] as? Bool,
            let session = GCKCastContext.sharedInstance().sessionManager.currentSession
        {
            applyMutePolicy(isAdvertisement: isAdvertisement, session: session)
        }
    }
}

struct GoogleCastRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: .zero)
        button.tintColor = .white
        button.accessibilityLabel = "Google Cast"
        button.accessibilityIdentifier = "googleCastButton"
        return button
    }

    func updateUIView(_ button: GCKUICastButton, context: Context) {}
}
#else
@MainActor
final class GoogleCastManager: ObservableObject, CastPlaybackManaging {
    static let shared = GoogleCastManager()
    @Published private(set) var snapshot = CastSessionSnapshot()

    var isCasting: Bool {
        snapshot.phase != .disconnected
    }

    func configure() {}
    func prepare(_ plan: CastPlaybackPlan, loadIfConnected: Bool) {}
    func updateProgramPosition(_ position: Double) {}
    func clear() {}
    func togglePlayback() {}
    func seek(to position: Double) {}
    func skip(by interval: Double) {}
    func toggleMute() {}
    func retry() {}
    func stopCasting() {}
}

struct GoogleCastRouteButton: View {
    var body: some View {
        Button(action: {}) {
            Image(systemName: "tv.badge.wifi")
                .frame(width: 36, height: 36)
        }
        .disabled(true)
        .accessibilityLabel("Google Cast")
        .accessibilityIdentifier("googleCastButton")
    }
}
#endif
