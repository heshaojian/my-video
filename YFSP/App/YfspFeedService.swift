import Foundation

enum YfspFeedError: Error {
    case missingPageData
    case missingFeed
}

struct YfspFeedService {
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
    }

    func fetchLatest(category: YfspCategory) async throws -> [YfspItem] {
        let (data, _) = try await URLSession.shared.data(from: category.url)
        guard
            let html = String(data: data, encoding: .utf8),
            let json = extractInjectedJSON(from: html)
        else {
            throw YfspFeedError.missingPageData
        }

        guard
            let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let key = root.keys.first(where: { $0.hasPrefix("slide-list") }),
            let rawItems = root[key]
        else {
            throw YfspFeedError.missingFeed
        }

        let itemData = try JSONSerialization.data(withJSONObject: rawItems)
        return try decoder.decode([YfspItem].self, from: itemData)
    }

    private func extractInjectedJSON(from html: String) -> String? {
        guard
            let start = html.range(of: "var injectJson = ")?.upperBound,
            let end = html[start...].range(of: "};")?.lowerBound
        else {
            return nil
        }

        return String(html[start...end])
    }
}
