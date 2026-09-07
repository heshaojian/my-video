import Foundation
import XCTest
@testable import Aiyifan

@MainActor
final class NativePlayerViewModelTests: XCTestCase {
    func testStartQueuesAdvertisementBeforeProgram() async throws {
        let playback = NativePlayback(entries: [
            NativePlaybackEntry(
                url: URL(string: "https://ads.example.com/front.mp4")!,
                isAdvertisement: true
            ),
            NativePlaybackEntry(
                url: URL(string: "https://media.example.com/full.m3u8")!,
                isAdvertisement: false
            )
        ], episodeTitle: "04")
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "media-key", title: "Movie"),
            resolver: StubPlaybackResolver(playback: playback)
        )

        viewModel.start()
        try await waitUntil { viewModel.player.items().count == 2 }

        XCTAssertEqual(viewModel.player.items().count, 2)
        XCTAssertEqual(viewModel.episodeTitle, "04")
        viewModel.stop()
        XCTAssertTrue(viewModel.player.items().isEmpty)
    }

    func testResolverErrorBecomesUserFacingPlaybackError() async throws {
        let viewModel = NativePlayerViewModel(
            item: AiyifanItem(listPath: "media-key", title: "Movie"),
            resolver: StubPlaybackResolver(error: .loginRequired)
        )

        viewModel.start()
        try await waitUntil { viewModel.errorMessage != nil }

        XCTAssertEqual(viewModel.errorMessage, "This title requires you to sign in on the website.")
        XCTAssertFalse(viewModel.isLoading)
    }

    private func waitUntil(
        timeoutIterations: Int = 50,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition was not satisfied before timeout")
    }
}

private struct StubPlaybackResolver: NativePlaybackResolving {
    let playback: NativePlayback?
    let error: NativePlaybackError?

    init(playback: NativePlayback? = nil, error: NativePlaybackError? = nil) {
        self.playback = playback
        self.error = error
    }

    func resolve(item: AiyifanItem) async throws -> NativePlayback {
        if let error {
            throw error
        }
        return playback ?? NativePlayback(entries: [])
    }
}
