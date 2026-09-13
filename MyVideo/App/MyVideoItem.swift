import Foundation

enum ProviderWebURLPolicy {
    static func isAllowed(
        _ url: URL,
        processArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
#if DEBUG
        if url.scheme?.lowercased() == "data" {
            return processArguments.contains("-MyVideoUseFixtureFeed")
        }
#endif
        guard
            url.scheme?.lowercased() == "https",
            let host = url.host,
            url.user == nil,
            url.password == nil,
            url.port == nil
        else {
            return false
        }

        return RemoteResourceHostValidator.matchingProviderDomain(for: host) != nil
    }
}

struct MyVideoItem: Codable, Equatable, Identifiable, Sendable {
    let listPath: String
    let title: String
    let image: String?
    let img: String?
    let verticalImg: String?
    let subTitle: String?
    let addTime: String?
    let url: String?
    let year: String?
    let region: String?
    let isSerial: Bool?
    let latestEpisodeKey: String?
    let latestEpisodeTitle: String?
    let categoryPath: String?
    let genre: String?
    let language: String?
    let quality: String?
    let popularity: Int?
    let rating: String?
    let score: Double?

    init(
        listPath: String,
        title: String,
        image: String? = nil,
        img: String? = nil,
        verticalImg: String? = nil,
        subTitle: String? = nil,
        addTime: String? = nil,
        url: String? = nil,
        year: String? = nil,
        region: String? = nil,
        isSerial: Bool? = nil,
        latestEpisodeKey: String? = nil,
        latestEpisodeTitle: String? = nil,
        categoryPath: String? = nil,
        genre: String? = nil,
        language: String? = nil,
        quality: String? = nil,
        popularity: Int? = nil,
        rating: String? = nil,
        score: Double? = nil
    ) {
        self.listPath = listPath
        self.title = title
        self.image = image
        self.img = img
        self.verticalImg = verticalImg
        self.subTitle = subTitle
        self.addTime = addTime
        self.url = url
        self.year = year
        self.region = region
        self.isSerial = isSerial
        self.latestEpisodeKey = latestEpisodeKey
        self.latestEpisodeTitle = latestEpisodeTitle
        self.categoryPath = categoryPath
        self.genre = genre
        self.language = language
        self.quality = quality
        self.popularity = popularity
        self.rating = rating
        self.score = score
    }

    var id: String {
        listPath
    }

    var thumbnailURL: URL? {
        Self.siteURL(from: verticalImg) ?? Self.siteURL(from: image) ?? Self.siteURL(from: img)
    }

    var playURL: URL {
        if let url = Self.siteURL(from: url) {
            return url
        }

        return Self.playURL(from: listPath)
    }

    var updateLabel: String {
        subTitle?.isEmpty == false ? subTitle! : "Latest update"
    }

    enum CodingKeys: String, CodingKey {
        case listPath
        case title
        case image
        case img
        case verticalImg
        case subTitle
        case addTime
        case url
        case year
        case region
        case isSerial
        case latestEpisodeKey
        case latestEpisodeTitle
        case categoryPath
        case genre
        case language
        case quality
        case popularity
        case rating
        case score
    }

    private static func playURL(from rawPath: String) -> URL {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = siteURL(from: path), path.contains("/") {
            return url
        }

        let mediaKey = path
            .replacingOccurrences(of: "/play/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return URL(string: "https://m.yfsp.tv/play/\(mediaKey)")!
    }

    private static func siteURL(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }

        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("about:") || value.hasPrefix("data:") {
            return URL(string: value)
        }

        if value.hasPrefix("/") {
            return URL(string: "https://m.yfsp.tv\(value)")
        }

        return nil
    }
}
