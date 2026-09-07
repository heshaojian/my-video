import Foundation

enum AiyifanCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case movie
    case drama
    case variety
    case anime

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .movie:
            "Movies"
        case .drama:
            "Series"
        case .variety:
            "Variety"
        case .anime:
            "Anime"
        }
    }

    var latestTitle: String {
        "Latest \(title)"
    }

    var catalogCID: String {
        switch self {
        case .movie:
            "0,1,3"
        case .drama:
            "0,1,4"
        case .variety:
            "0,1,5"
        case .anime:
            "0,1,6"
        }
    }

    var genreEndpointPath: String {
        switch self {
        case .movie: "/api/list/FilmType"
        case .drama: "/api/list/TvType"
        case .variety: "/api/list/VarietyType"
        case .anime: "/api/list/AnimeType"
        }
    }

    var url: URL {
        switch self {
        case .movie:
            URL(string: "https://m.yfsp.tv/list/movie")!
        case .drama:
            URL(string: "https://m.yfsp.tv/list/drama")!
        case .variety:
            URL(string: "https://m.yfsp.tv/list/variety")!
        case .anime:
            URL(string: "https://m.yfsp.tv/list/anime")!
        }
    }
}
