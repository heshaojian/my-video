import Foundation

enum EpisodeNavigator {
    static func next(in newestFirstEpisodes: [Episode], current: Episode?) -> Episode? {
        guard
            let current,
            let index = newestFirstEpisodes.firstIndex(where: { $0.id == current.id }),
            index > newestFirstEpisodes.startIndex
        else {
            return nil
        }
        return newestFirstEpisodes[index - 1]
    }

    static func previous(in newestFirstEpisodes: [Episode], current: Episode?) -> Episode? {
        guard
            let current,
            let index = newestFirstEpisodes.firstIndex(where: { $0.id == current.id }),
            newestFirstEpisodes.indices.contains(index + 1)
        else {
            return nil
        }
        return newestFirstEpisodes[index + 1]
    }
}
