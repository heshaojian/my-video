import Foundation

enum AiyifanFeedError: Error {
    case missingPageData
    case missingFeed
}

protocol AiyifanFeedServing: Sendable {
    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem]
}

struct AiyifanFeedService: @unchecked Sendable, AiyifanFeedServing {
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
    }

    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem] {
        if ProcessInfo.processInfo.arguments.contains("-AiyifanUseFixtureFeed") {
            return Self.fixtureItems(for: category)
        }

        let (data, _) = try await URLSession.shared.data(from: category.url)
        guard
            let html = String(data: data, encoding: .utf8),
            let json = extractInjectedJSON(from: html)
        else {
            throw AiyifanFeedError.missingPageData
        }

        guard
            let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let key = root.keys.first(where: { $0.hasPrefix("slide-list") }),
            let rawItems = root[key]
        else {
            throw AiyifanFeedError.missingFeed
        }

        let itemData = try JSONSerialization.data(withJSONObject: rawItems)
        return try decoder.decode([AiyifanItem].self, from: itemData)
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

    private static func fixtureItems(for category: AiyifanCategory) -> [AiyifanItem] {
        let html = """
        <html><body>
        <p>Playback page ready</p>
        <button aria-label="Open popup" onclick="window.open('https://example.com', '_blank')">Open popup</button>
        </body></html>
        """
        let fixtureURL = "data:text/html;base64,\(Data(html.utf8).base64EncodedString())"

        return [
            AiyifanItem(
                listPath: "fixture-\(category.id)",
                title: "Fixture \(category.title)",
                subTitle: "更新至 01 集",
                url: fixtureURL,
                isSerial: category != .movie,
                latestEpisodeKey: category == .movie ? nil : "episode-10",
                latestEpisodeTitle: category == .movie ? nil : "10",
                categoryPath: category.catalogCID
            )
        ]
    }
}
