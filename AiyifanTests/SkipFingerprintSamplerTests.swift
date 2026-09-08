import AVFoundation
import CoreVideo
import XCTest
@testable import Aiyifan

@MainActor
final class SkipFingerprintSamplerTests: XCTestCase {
    func testSamplesOnlyInsideBoundedIntroAndOutroWindows() async throws {
        let source = TestSkipVideoFrameProvider()
        let sampler = makeSampler(source: source)

        let introStart = await sampler.capture(at: 0, state: readyState())
        let introEnd = await sampler.capture(at: 480, state: readyState())
        let outsideIntro = await sampler.capture(at: 481, state: readyState())
        let beforeOutro = await sampler.capture(at: 3_239.999, state: readyState())
        let outroStart = await sampler.capture(at: 3_240, state: readyState())
        let programEnd = await sampler.capture(at: 3_600, state: readyState())

        XCTAssertNotNil(introStart)
        XCTAssertNotNil(introEnd)
        XCTAssertNil(outsideIntro)
        XCTAssertNil(beforeOutro)
        XCTAssertNotNil(outroStart)
        XCTAssertNotNil(programEnd)

        XCTAssertEqual(source.requestedTimes, [0, 480, 3_240, 3_600])
        XCTAssertEqual(source.attachCount, 1)
    }

    func testThrottlesSamplesToAtMostOneEveryTwoSeconds() async throws {
        let source = TestSkipVideoFrameProvider()
        let sampler = makeSampler(source: source)

        let first = await sampler.capture(at: 10, state: readyState())
        let tooSoon = await sampler.capture(at: 11.999, state: readyState())
        let boundary = await sampler.capture(at: 12, state: readyState())
        let nearExistingSample = await sampler.capture(at: 10.5, state: readyState())

        XCTAssertNotNil(first)
        XCTAssertNil(tooSoon)
        XCTAssertNotNil(boundary)
        XCTAssertNil(nearExistingSample)

        XCTAssertEqual(source.requestedTimes, [10, 12])
    }

    func testEveryUnsafeRuntimeConditionPausesBeforeRequestingAFrame() async throws {
        let source = TestSkipVideoFrameProvider()
        let sampler = makeSampler(source: source)
        let pausedStates = [
            readyState(isProgram: false),
            readyState(isReadyToPlay: false),
            readyState(isLoading: true),
            readyState(isSeeking: true),
            readyState(isPictureInPictureActive: true),
            readyState(isPictureInPictureTransitioning: true),
            readyState(isCasting: true),
            readyState(isAppSuspended: true),
            readyState(isLowPowerModeEnabled: true),
            readyState(isUnderMemoryPressure: true)
        ]

        for state in pausedStates {
            let output = await sampler.capture(at: 10, state: state)
            XCTAssertNil(output)
        }

        XCTAssertEqual(source.attachCount, 0)
        XCTAssertTrue(source.requestedTimes.isEmpty)
    }

    func testStateProtocolCanPauseAnOutstandingHashAndDiscardItsResult() async throws {
        let source = TestSkipVideoFrameProvider()
        let hasher = BlockingSkipFrameHasher(hash: 77)
        let sampler = makeSampler(source: source, hasher: hasher)

        let capture = Task { @MainActor in
            await sampler.capture(at: 10, state: self.readyState())
        }
        await hasher.waitUntilStarted()

        sampler.updateRuntimeState(TestSkipSamplingState(
            snapshot: readyState(isUnderMemoryPressure: true)
        ))
        await hasher.release()

        let output = await capture.value
        XCTAssertNil(output)
        XCTAssertNil(try sampler.complete(sampledAt: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(source.detachCount, 1)
    }

    func testAllowsOnlyOneOutstandingFrameHash() async throws {
        let source = TestSkipVideoFrameProvider()
        let hasher = BlockingSkipFrameHasher(hash: 42)
        let sampler = makeSampler(source: source, hasher: hasher)

        let first = Task { @MainActor in
            await sampler.capture(at: 10, state: self.readyState())
        }
        await hasher.waitUntilStarted()

        let concurrentOutput = await sampler.capture(at: 12, state: readyState())
        XCTAssertNil(concurrentOutput)
        XCTAssertEqual(source.requestedTimes, [10])

        await hasher.release()
        let firstOutput = await first.value
        XCTAssertEqual(
            firstOutput,
            .batch(SkipFingerprintBatch(samples: [PerceptualHashSample(time: 10, hash: 42)]))
        )
    }

    func testCancellationGenerationDropsStaleWorkAndDetachesOutput() async throws {
        let source = TestSkipVideoFrameProvider()
        let hasher = BlockingSkipFrameHasher(hash: 99)
        let sampler = makeSampler(source: source, hasher: hasher)

        let capture = Task { @MainActor in
            await sampler.capture(at: 10, state: self.readyState())
        }
        await hasher.waitUntilStarted()

        sampler.cancel()
        await hasher.release()

        let staleOutput = await capture.value
        let afterCancellation = await sampler.capture(at: 12, state: readyState())
        XCTAssertNil(staleOutput)
        XCTAssertNil(afterCancellation)
        XCTAssertNil(try sampler.complete(sampledAt: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(source.detachCount, 1)
    }

    func testCompletionReturnsValidatedSortedFingerprintWithoutPersistence() async throws {
        let source = TestSkipVideoFrameProvider()
        let hasher = SequencedSkipFrameHasher(hashes: [90, 10, 50])
        let sampler = makeSampler(source: source, hasher: hasher)

        let first = await sampler.capture(at: 90, state: readyState())
        let second = await sampler.capture(at: 10, state: readyState())
        let third = await sampler.capture(at: 50, state: readyState())
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)

        let sampledAt = Date(timeIntervalSince1970: 500)
        let output = try sampler.complete(sampledAt: sampledAt)

        XCTAssertEqual(
            output,
            EpisodeFingerprint(
                seriesID: "series-1",
                episodeID: "episode-2",
                duration: 3_600,
                samples: [
                    PerceptualHashSample(time: 10, hash: 10),
                    PerceptualHashSample(time: 50, hash: 50),
                    PerceptualHashSample(time: 90, hash: 90)
                ],
                sampledAt: sampledAt,
                schemaVersion: 1
            )
        )
        XCTAssertEqual(source.detachCount, 1)
    }

    private func makeSampler(
        source: TestSkipVideoFrameProvider,
        hasher: any SkipFrameHashing = SequencedSkipFrameHasher(hashes: Array(repeating: 1, count: 20))
    ) -> SkipFingerprintSampler {
        SkipFingerprintSampler(
            seriesID: "series-1",
            episodeID: "episode-2",
            duration: 3_600,
            frameProvider: source,
            hasher: hasher
        )
    }

    private func readyState(
        isProgram: Bool = true,
        isReadyToPlay: Bool = true,
        isLoading: Bool = false,
        isSeeking: Bool = false,
        isPictureInPictureActive: Bool = false,
        isPictureInPictureTransitioning: Bool = false,
        isCasting: Bool = false,
        isAppSuspended: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        isUnderMemoryPressure: Bool = false
    ) -> SkipSamplingRuntimeState {
        SkipSamplingRuntimeState(
            isProgram: isProgram,
            isReadyToPlay: isReadyToPlay,
            isLoading: isLoading,
            isSeeking: isSeeking,
            isPictureInPictureActive: isPictureInPictureActive,
            isPictureInPictureTransitioning: isPictureInPictureTransitioning,
            isCasting: isCasting,
            isAppSuspended: isAppSuspended,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            isUnderMemoryPressure: isUnderMemoryPressure
        )
    }
}

@MainActor
private final class TestSkipVideoFrameProvider: SkipVideoFrameProviding {
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    private(set) var requestedTimes: [TimeInterval] = []
    private var isAttached = false
    private let frame = SkipVideoFrame(pixelBuffer: makeTestPixelBuffer())

    func attachIfNeeded() {
        guard !isAttached else { return }
        isAttached = true
        attachCount += 1
    }

    func copyFrame(at time: CMTime) -> SkipVideoFrame? {
        requestedTimes.append(time.seconds)
        return frame
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false
        detachCount += 1
    }
}

private struct TestSkipSamplingState: SkipSamplingStateProviding {
    let snapshot: SkipSamplingRuntimeState

    var skipSamplingState: SkipSamplingRuntimeState { snapshot }
}

private actor SequencedSkipFrameHasher: SkipFrameHashing {
    private var hashes: [UInt64]

    init(hashes: [UInt64]) {
        self.hashes = hashes
    }

    func hash(_ frame: SkipVideoFrame) async throws -> UInt64 {
        hashes.isEmpty ? 0 : hashes.removeFirst()
    }
}

private actor BlockingSkipFrameHasher: SkipFrameHashing {
    private let outputHash: UInt64
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(hash: UInt64) {
        outputHash = hash
    }

    func hash(_ frame: SkipVideoFrame) async throws -> UInt64 {
        started = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return outputHash
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func makeTestPixelBuffer() -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        2,
        2,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    precondition(status == kCVReturnSuccess)
    return pixelBuffer!
}
