@preconcurrency import AVFoundation
import CoreVideo
import Foundation

enum SkipSamplingPauseReason: Equatable, Sendable {
    case notProgram
    case notReady
    case loading
    case seeking
    case pictureInPicture
    case casting
    case suspended
    case lowPower
    case memoryPressure
}

protocol SkipSamplingStateProviding: Sendable {
    var skipSamplingState: SkipSamplingRuntimeState { get }
}

struct SkipSamplingRuntimeState: Equatable, Sendable, SkipSamplingStateProviding {
    let isProgram: Bool
    let isReadyToPlay: Bool
    let isLoading: Bool
    let isSeeking: Bool
    let isPictureInPictureActive: Bool
    let isPictureInPictureTransitioning: Bool
    let isCasting: Bool
    let isAppSuspended: Bool
    let isLowPowerModeEnabled: Bool
    let isUnderMemoryPressure: Bool

    var skipSamplingState: SkipSamplingRuntimeState { self }

    var pauseReason: SkipSamplingPauseReason? {
        if !isProgram { return .notProgram }
        if !isReadyToPlay { return .notReady }
        if isLoading { return .loading }
        if isSeeking { return .seeking }
        if isPictureInPictureActive || isPictureInPictureTransitioning {
            return .pictureInPicture
        }
        if isCasting { return .casting }
        if isAppSuspended { return .suspended }
        if isLowPowerModeEnabled { return .lowPower }
        if isUnderMemoryPressure { return .memoryPressure }
        return nil
    }
}

struct SkipVideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

protocol SkipFrameHashing: Sendable {
    func hash(_ frame: SkipVideoFrame) async throws -> UInt64
}

@MainActor
protocol SkipVideoFrameProviding: AnyObject {
    func attachIfNeeded()
    func copyFrame(at time: CMTime) -> SkipVideoFrame?
    func detach()
}

struct SkipFingerprintBatch: Equatable, Sendable {
    let samples: [PerceptualHashSample]
}

enum SkipFingerprintSamplerOutput: Equatable, Sendable {
    case batch(SkipFingerprintBatch)
}

@MainActor
final class SkipFingerprintSampler {
    private let seriesID: String
    private let episodeID: String
    private let duration: TimeInterval
    private let frameProvider: any SkipVideoFrameProviding
    private let hasher: any SkipFrameHashing
    private let policy: SkipDetectionPolicy

    private var samples: [PerceptualHashSample] = []
    private var generation: UInt64 = 0
    private var inFlightTask: Task<UInt64, Error>?
    private var isCancelled = false

    init(
        seriesID: String,
        episodeID: String,
        duration: TimeInterval,
        frameProvider: any SkipVideoFrameProviding,
        hasher: any SkipFrameHashing,
        policy: SkipDetectionPolicy = .standard
    ) {
        self.seriesID = seriesID
        self.episodeID = episodeID
        self.duration = duration
        self.frameProvider = frameProvider
        self.hasher = hasher
        self.policy = policy
    }

    convenience init(
        seriesID: String,
        episodeID: String,
        duration: TimeInterval,
        playerItem: AVPlayerItem,
        hasher: any SkipFrameHashing,
        policy: SkipDetectionPolicy = .standard
    ) {
        self.init(
            seriesID: seriesID,
            episodeID: episodeID,
            duration: duration,
            frameProvider: AVPlayerItemSkipVideoFrameProvider(playerItem: playerItem),
            hasher: hasher,
            policy: policy
        )
    }

    func capture(
        at position: TimeInterval,
        state: any SkipSamplingStateProviding
    ) async -> SkipFingerprintSamplerOutput? {
        let runtimeState = state.skipSamplingState
        guard runtimeState.pauseReason == nil else {
            updateRuntimeState(runtimeState)
            return nil
        }
        guard
            !isCancelled,
            inFlightTask == nil,
            samples.count < policy.maximumHashesPerEpisode,
            shouldSample(at: position)
        else {
            return nil
        }

        frameProvider.attachIfNeeded()
        let itemTime = CMTime(seconds: position, preferredTimescale: 600)
        guard let frame = frameProvider.copyFrame(at: itemTime) else {
            return nil
        }

        let capturedGeneration = generation
        let hasher = hasher
        let hashTask = Task.detached(priority: .utility) {
            try await hasher.hash(frame)
        }
        inFlightTask = hashTask

        let hash = try? await hashTask.value
        inFlightTask = nil

        guard
            let hash,
            !isCancelled,
            generation == capturedGeneration,
            runtimeState.pauseReason == nil
        else {
            return nil
        }

        let sample = PerceptualHashSample(time: position, hash: hash)
        samples.append(sample)
        return .batch(SkipFingerprintBatch(samples: [sample]))
    }

    func updateRuntimeState(_ state: any SkipSamplingStateProviding) {
        guard state.skipSamplingState.pauseReason != nil else { return }
        generation &+= 1
        inFlightTask?.cancel()
        frameProvider.detach()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        generation &+= 1
        inFlightTask?.cancel()
        frameProvider.detach()
    }

    func complete(sampledAt: Date = Date()) throws -> EpisodeFingerprint? {
        guard !isCancelled, inFlightTask == nil, !samples.isEmpty else {
            return nil
        }

        isCancelled = true
        generation &+= 1
        frameProvider.detach()
        return try EpisodeFingerprint(
            validatingSeriesID: seriesID,
            episodeID: episodeID,
            duration: duration,
            samples: samples,
            sampledAt: sampledAt,
            policy: policy
        )
    }

    private func shouldSample(at position: TimeInterval) -> Bool {
        guard
            duration.isFinite,
            duration > 0,
            position.isFinite,
            position >= 0,
            position <= duration
        else {
            return false
        }

        let isInsideIntro = position <= min(duration, policy.introWindow)
        let outroStart = max(0, duration - policy.outroWindow)
        let isInsideOutro = position >= outroStart
        guard isInsideIntro || isInsideOutro else { return false }

        return samples.allSatisfy {
            abs($0.time - position) >= policy.sampleInterval
        }
    }
}

@MainActor
final class AVPlayerItemSkipVideoFrameProvider: SkipVideoFrameProviding {
    private weak var playerItem: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?

    init(playerItem: AVPlayerItem) {
        self.playerItem = playerItem
    }

    func attachIfNeeded() {
        guard output == nil, let playerItem else { return }
        let attributes: [String: NSNumber] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
                value: kCVPixelFormatType_32BGRA
            )
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        playerItem.add(output)
        self.output = output
    }

    func copyFrame(at time: CMTime) -> SkipVideoFrame? {
        guard
            let output,
            time.isValid,
            output.hasNewPixelBuffer(forItemTime: time),
            let pixelBuffer = output.copyPixelBuffer(
                forItemTime: time,
                itemTimeForDisplay: nil
            )
        else {
            return nil
        }
        return SkipVideoFrame(pixelBuffer: pixelBuffer)
    }

    func detach() {
        guard let output else { return }
        playerItem?.remove(output)
        self.output = nil
    }
}
