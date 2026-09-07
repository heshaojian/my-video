import Foundation

struct YfspItem: Decodable, Identifiable {
    let listPath: String
    let title: String
    let image: URL?
    let img: URL?
    let verticalImg: URL?
    let subTitle: String?
    let addTime: String?
    let url: URL?

    var id: String {
        listPath
    }

    var thumbnailURL: URL? {
        verticalImg ?? image ?? img
    }

    var playURL: URL {
        url ?? URL(string: "https://m.yfsp.tv/play/\(listPath)")!
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
}
