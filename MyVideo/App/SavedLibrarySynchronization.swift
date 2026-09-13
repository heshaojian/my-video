import Foundation

enum AppOpenRefreshPolicy {
    static let interval: TimeInterval = 15 * 60

    static func isDue(lastSuccessfulRefresh: Date?, now: Date = Date()) -> Bool {
        guard let lastSuccessfulRefresh else { return true }
        return now.timeIntervalSince(lastSuccessfulRefresh) >= interval
    }
}

@MainActor
final class AppOpenLibraryRefreshCoordinator {
    private struct ActiveRefresh {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private var activeRefresh: ActiveRefresh?
    private(set) var lastSuccessfulRefresh: Date?

    init(lastSuccessfulRefresh: Date? = nil) {
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
    }

    @discardableResult
    func refreshIfNeeded(
        now: Date = Date(),
        force: Bool = false,
        operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if let activeRefresh {
            return await activeRefresh.task.value
        }
        guard force || AppOpenRefreshPolicy.isDue(
            lastSuccessfulRefresh: lastSuccessfulRefresh,
            now: now
        ) else {
            return false
        }

        let id = UUID()
        let task = Task { @MainActor in
            await operation()
        }
        activeRefresh = ActiveRefresh(id: id, task: task)
        let succeeded = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if activeRefresh?.id == id {
            activeRefresh = nil
            if succeeded {
                lastSuccessfulRefresh = now
            }
        }
        return succeeded
    }
}

struct SavedEpisodeReconciliation: Equatable, Sendable {
    let state: SavedEpisodeUpdateState
    let didAdvance: Bool
}

enum SavedEpisodeSnapshotReconciler {
    static func reconcile(
        previous: SavedEpisodeUpdateState?,
        observedEpisodes: [EpisodeSelection],
        previouslySeenKey: String?,
        observedAt: Date
    ) -> SavedEpisodeReconciliation? {
        let observed = normalized(observedEpisodes)
        guard let candidate = observed.first else { return nil }
        guard let previous else {
            return SavedEpisodeReconciliation(
                state: SavedEpisodeUpdateState(
                    episodes: observed,
                    latestEpisodeKey: candidate.mediaKey,
                    seenEpisodeKey: candidate.mediaKey,
                    detectedAt: observedAt,
                    lastObservedAt: observedAt
                ),
                didAdvance: false
            )
        }

        let previousLatest = episode(
            withKey: previous.latestEpisodeKey,
            in: previous.episodes
        ) ?? EpisodeSelection(mediaKey: previous.latestEpisodeKey, title: previous.latestEpisodeKey)
        let didAdvance = candidate.mediaKey != previous.latestEpisodeKey
            && isNewer(candidate, than: previousLatest, in: observed, previousEpisodes: previous.episodes)
        let latest = didAdvance ? candidate : previousLatest
        let primaryEpisodes = didAdvance ? observed : [latest] + previous.episodes
        let secondaryEpisodes = didAdvance ? previous.episodes : observed
        let mergedEpisodes = normalized(primaryEpisodes + secondaryEpisodes)

        return SavedEpisodeReconciliation(
            state: SavedEpisodeUpdateState(
                episodes: mergedEpisodes,
                latestEpisodeKey: latest.mediaKey,
                seenEpisodeKey: previous.seenEpisodeKey ?? previouslySeenKey,
                detectedAt: didAdvance ? observedAt : previous.detectedAt,
                lastObservedAt: observedAt
            ),
            didAdvance: didAdvance
        )
    }

    private static func isNewer(
        _ candidate: EpisodeSelection,
        than previous: EpisodeSelection,
        in observed: [EpisodeSelection],
        previousEpisodes: [EpisodeSelection]
    ) -> Bool {
        if let candidateNumber = episodeNumber(candidate),
           let previousNumber = episodeNumber(previous) {
            return candidateNumber > previousNumber
        }
        if observed.contains(where: { $0.mediaKey == previous.mediaKey }) {
            return true
        }
        if previousEpisodes.contains(where: { $0.mediaKey == candidate.mediaKey }) {
            return false
        }
        return false
    }

    private static func episodeNumber(_ episode: EpisodeSelection) -> Int? {
        if let titleNumber = EpisodeNumberParser.number(in: episode.title) {
            return titleNumber
        }
        let trailingDigits = episode.mediaKey.reversed().prefix(while: { $0.isNumber }).reversed()
        return trailingDigits.isEmpty ? nil : Int(String(trailingDigits))
    }

    private static func episode(withKey key: String, in episodes: [EpisodeSelection]) -> EpisodeSelection? {
        episodes.first { $0.mediaKey == key }
    }

    private static func normalized(_ episodes: [EpisodeSelection]) -> [EpisodeSelection] {
        var keys: Set<String> = []
        var result: [EpisodeSelection] = []
        for episode in episodes {
            let key = episode.mediaKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, keys.insert(key).inserted else { continue }
            result.append(EpisodeSelection(mediaKey: key, title: title.isEmpty ? key : title))
            if result.count == SavedEpisodeUpdateState.maximumEpisodeCount { break }
        }
        return result
    }
}

enum SavedCatalogItemReconciler {
    static func merge(
        saved: MyVideoItem,
        observed: MyVideoItem,
        episodeState: SavedEpisodeUpdateState? = nil
    ) -> MyVideoItem {
        guard saved.id == observed.id else { return saved }
        let merged = MyVideoItem(
            listPath: saved.listPath,
            title: preferred(observed.title, fallback: saved.title),
            image: preferred(observed.image, fallback: saved.image),
            img: preferred(observed.img, fallback: saved.img),
            verticalImg: preferred(observed.verticalImg, fallback: saved.verticalImg),
            subTitle: preferred(observed.subTitle, fallback: saved.subTitle),
            addTime: preferred(observed.addTime, fallback: saved.addTime),
            url: preferred(observed.url, fallback: saved.url),
            year: preferred(observed.year, fallback: saved.year),
            region: preferred(observed.region, fallback: saved.region),
            isSerial: observed.isSerial ?? saved.isSerial,
            latestEpisodeKey: preferred(observed.latestEpisodeKey, fallback: saved.latestEpisodeKey),
            latestEpisodeTitle: preferred(observed.latestEpisodeTitle, fallback: saved.latestEpisodeTitle),
            categoryPath: preferred(observed.categoryPath, fallback: saved.categoryPath),
            genre: preferred(observed.genre, fallback: saved.genre),
            language: preferred(observed.language, fallback: saved.language),
            quality: preferred(observed.quality, fallback: saved.quality),
            popularity: observed.popularity ?? saved.popularity,
            rating: preferred(observed.rating, fallback: saved.rating),
            score: observed.score ?? saved.score
        )
        return applying(episodeState: episodeState, to: merged)
    }

    static func applying(
        episodeState: SavedEpisodeUpdateState?,
        to item: MyVideoItem
    ) -> MyVideoItem {
        guard
            let episodeState,
            let latestEpisode = episodeState.episodes.first(where: {
                $0.mediaKey == episodeState.latestEpisodeKey
            })
        else {
            return item
        }
        return MyVideoItem(
            listPath: item.listPath,
            title: item.title,
            image: item.image,
            img: item.img,
            verticalImg: item.verticalImg,
            subTitle: latestEpisode.title,
            addTime: item.addTime,
            url: item.url,
            year: item.year,
            region: item.region,
            isSerial: item.isSerial,
            latestEpisodeKey: latestEpisode.mediaKey,
            latestEpisodeTitle: latestEpisode.title,
            categoryPath: item.categoryPath,
            genre: item.genre,
            language: item.language,
            quality: item.quality,
            popularity: item.popularity,
            rating: item.rating,
            score: item.score
        )
    }

    private static func preferred(_ observed: String, fallback: String) -> String {
        observed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : observed
    }

    private static func preferred(_ observed: String?, fallback: String?) -> String? {
        guard let observed, !observed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return observed
    }
}
