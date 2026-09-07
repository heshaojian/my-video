import AVKit
import SwiftUI

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
        item: AiyifanItem,
        playback: NativePlayback,
        programPosition: Double
    ) throws -> CastPlaybackPlan {
        guard playback.entries.contains(where: { !$0.isAdvertisement }) else {
            throw CastPlaybackPlanError.missingProgram
        }
        let safePosition = programPosition.isFinite ? max(0, programPosition) : 0
        let entries = playback.entries.map { entry in
            CastQueueEntry(
                url: entry.url,
                isAdvertisement: entry.isAdvertisement,
                startPosition: entry.isAdvertisement ? 0 : safePosition,
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

    @Published private(set) var isCasting = false

    private var isConfigured = false
    private var preparedPlan: CastPlaybackPlan?
    private var muteState = CastMuteState()
    private weak var mediaClient: GCKRemoteMediaClient?

    func configure() {
        guard !isConfigured else {
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
        preparedPlan = nil
    }

    private func handleConnectedSession(_ session: GCKSession, shouldLoad: Bool) {
        mediaClient?.remove(self)
        mediaClient = session.remoteMediaClient
        mediaClient?.add(self)
        isCasting = true
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
            queueItemBuilder.customData = ["aiyifanAdvertisement": entry.isAdvertisement]
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
        mediaClient?.remove(self)
        mediaClient = nil
        isCasting = false
        muteState = CastMuteState()
    }
}

extension GoogleCastManager: @preconcurrency GCKRemoteMediaClientListener {
    func remoteMediaClient(
        _ client: GCKRemoteMediaClient,
        didUpdate mediaStatus: GCKMediaStatus?
    ) {
        guard
            let value = mediaStatus?.currentQueueItem?.customData as? [String: Any],
            let isAdvertisement = value["aiyifanAdvertisement"] as? Bool
        else {
            return
        }
        guard let session = GCKCastContext.sharedInstance().sessionManager.currentSession else {
            return
        }
        applyMutePolicy(isAdvertisement: isAdvertisement, session: session)
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
    let isCasting = false

    func configure() {}
    func prepare(_ plan: CastPlaybackPlan, loadIfConnected: Bool) {}
    func updateProgramPosition(_ position: Double) {}
    func clear() {}
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
