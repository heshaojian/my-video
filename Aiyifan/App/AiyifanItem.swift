import Foundation

struct AiyifanItem: Codable, Equatable, Identifiable {
    let listPath: String
    let title: String
    let image: String?
    let img: String?
    let verticalImg: String?
    let subTitle: String?
    let addTime: String?
    let url: String?

    init(
        listPath: String,
        title: String,
        image: String? = nil,
        img: String? = nil,
        verticalImg: String? = nil,
        subTitle: String? = nil,
        addTime: String? = nil,
        url: String? = nil
    ) {
        self.listPath = listPath
        self.title = title
        self.image = image
        self.img = img
        self.verticalImg = verticalImg
        self.subTitle = subTitle
        self.addTime = addTime
        self.url = url
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
        subTitle?.isEmpty == false ? subTitle! : "最新更新"
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
