import Foundation

enum PlaybackSessionPresentation: Equatable, Sendable {
    case inactive
    case collapsed
    case expanded
}

@MainActor
final class PlaybackSessionController: ObservableObject {
    typealias ViewModelFactory = @MainActor (
        _ item: AiyifanItem,
        _ episodeKey: String?,
        _ playedItemsStore: PlayedItemsStore,
        _ onEpisodesObserved: @escaping NativePlayerViewModel.EpisodeObservationHandler
    ) -> NativePlayerViewModel

    @Published private(set) var presentation = PlaybackSessionPresentation.inactive
    @Published private(set) var viewModel: NativePlayerViewModel?

    var item: AiyifanItem? { viewModel?.item }

    private let makeViewModel: ViewModelFactory

    init(makeViewModel: @escaping ViewModelFactory = PlaybackSessionController.makeDefaultViewModel) {
        self.makeViewModel = makeViewModel
    }

    func play(
        item: AiyifanItem,
        episodeKey: String?,
        playedItemsStore: PlayedItemsStore,
        monitorPlayback: Bool,
        onEpisodesObserved: @escaping NativePlayerViewModel.EpisodeObservationHandler = { _ in }
    ) {
        if let existing = viewModel, existing.item.id == item.id {
            let requestedDifferentEpisode = episodeKey.map { $0 != existing.selectedEpisode?.mediaKey } ?? false
            if !requestedDifferentEpisode {
                presentation = .expanded
                return
            }
        }

        viewModel?.stop()
        let replacement = makeViewModel(item, episodeKey, playedItemsStore, onEpisodesObserved)
        viewModel = replacement
        presentation = .expanded
        replacement.start(monitorPlayback: monitorPlayback)
    }

    func collapse() {
        guard let viewModel else { return }
        viewModel.persistProgress()
        presentation = .collapsed
    }

    func expand() {
        guard viewModel != nil else { return }
        presentation = .expanded
    }

    func stop() {
        viewModel?.stop()
        viewModel = nil
        presentation = .inactive
    }

    private static func makeDefaultViewModel(
        item: AiyifanItem,
        episodeKey: String?,
        playedItemsStore: PlayedItemsStore,
        onEpisodesObserved: @escaping NativePlayerViewModel.EpisodeObservationHandler
    ) -> NativePlayerViewModel {
#if DEBUG
        let usesFixturePlayback = AiyifanFixtureRuntime.usesFixtureFeed
        let resolver: any NativePlaybackResolving = usesFixturePlayback
            ? FixtureNativePlaybackResolver()
            : NativePlaybackResolver()
        let itemPreparer: any PlaybackItemPreparing
        let qualityLoader: any PlaybackQualityLoading
        if usesFixturePlayback {
            itemPreparer = FixturePlaybackItemPreparer(
                failingURL: AiyifanFixtureRuntime.failingQualityTier
                    .flatMap { FixtureNativePlaybackResolver.qualitySource(for: $0)?.url }
            )
            qualityLoader = FixturePlaybackQualityLoader()
        } else {
            itemPreparer = AVPlaybackItemPreparer()
            qualityLoader = AVAssetPlaybackQualityLoader()
        }
#else
        let resolver: any NativePlaybackResolving = NativePlaybackResolver()
        let itemPreparer: any PlaybackItemPreparing = AVPlaybackItemPreparer()
        let qualityLoader: any PlaybackQualityLoading = AVAssetPlaybackQualityLoader()
#endif
        return NativePlayerViewModel(
            item: item,
            initialEpisodeKey: episodeKey,
            resolver: resolver,
            playedItemsStore: playedItemsStore,
            qualityLoader: qualityLoader,
            itemPreparer: itemPreparer,
            onEpisodesObserved: onEpisodesObserved
        )
    }
}
