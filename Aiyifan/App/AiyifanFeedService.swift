import Foundation

enum AiyifanFeedError: Error {
    case missingPageData
    case missingFeed
}

protocol AiyifanFeedServing: Sendable {
    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem]
}

struct AiyifanFeedService: @unchecked Sendable, AiyifanFeedServing {
    private let catalogService: any CategoryCatalogServing
    private let usesFixtureFeed: Bool

    init(
        catalogService: any CategoryCatalogServing = CategoryCatalogService(),
        usesFixtureFeed: Bool = AiyifanFixtureRuntime.usesFixtureFeed
    ) {
        self.catalogService = catalogService
#if DEBUG
        self.usesFixtureFeed = usesFixtureFeed
#else
        self.usesFixtureFeed = false
#endif
    }

    func fetchLatest(category: AiyifanCategory) async throws -> [AiyifanItem] {
#if DEBUG
        if usesFixtureFeed {
            return Self.fixtureItems(for: category)
        }
#endif

        return try await catalogService.fetchPage(
            query: CatalogQuery(category: category),
            page: 1,
            pageSize: 8
        ).items
    }

#if DEBUG
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
                subTitle: category == .movie ? "New release" : "Episode 10",
                url: fixtureURL,
                isSerial: category != .movie,
                latestEpisodeKey: category == .movie ? nil : "episode-10",
                latestEpisodeTitle: category == .movie ? nil : "10",
                categoryPath: category.catalogCID,
                score: 9.4
            )
        ]
    }
#endif
}
