import Foundation

enum AiyifanCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case movie
    case drama
    case variety
    case anime

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .movie:
            "电影"
        case .drama:
            "电视剧"
        case .variety:
            "综艺"
        case .anime:
            "动漫"
        }
    }

    var latestTitle: String {
        "最新\(title)"
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
