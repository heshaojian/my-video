import Foundation

struct ProviderSearchQuery: Equatable, Sendable {
    let tags: String

    init(validating rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            trimmed.count <= 80,
            trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw ProviderSearchError.invalidQuery
        }
        tags = trimmed
    }
}

struct ProviderSearchPage: Equatable, Sendable {
    let items: [MyVideoItem]
    let page: Int
    let isLastPage: Bool
    let totalCount: Int
}

enum ProviderSearchError: Error, Equatable {
    case invalidQuery
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
}

extension ProviderSearchError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Enter a title using 80 characters or fewer."
        case .invalidRequest:
            return "The requested search page is invalid."
        case .invalidResponse:
            return "MyVideo returned an invalid search response."
        case .httpStatus:
            return "MyVideo could not load these search results."
        }
    }
}

enum ProviderSearchRequestBuilder {
    static func makeURL(
        query: ProviderSearchQuery,
        page: Int,
        pageSize: Int,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        guard (1...10_000).contains(page), (1...100).contains(pageSize) else {
            throw ProviderSearchError.invalidRequest
        }

        let parameters = [
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "orderby", value: "-1"),
            URLQueryItem(name: "desc", value: "1"),
            URLQueryItem(name: "cid", value: "0,1"),
            URLQueryItem(name: "tags", value: query.tags),
            URLQueryItem(name: "isserial", value: "-1"),
            URLQueryItem(name: "isIndex", value: "-1"),
            URLQueryItem(name: "isfree", value: "-1"),
            URLQueryItem(name: "isVertical", value: "-1")
        ]
        return try ProviderRequestSigner.makeSignedURL(
            path: "/api/list/Search",
            parameters: parameters,
            siteHost: siteHost,
            certificate: certificate
        )
    }
}

enum ProviderSearchResponseDecoder {
    private static let supportedCategoryPrefixes = Set(MyVideoCategory.allCases.map(\.catalogCID))

    static func decode(_ data: Data, page: Int, pageSize: Int) throws -> ProviderSearchPage {
        let catalogPage: CategoryCatalogPage
        do {
            catalogPage = try CategoryCatalogResponseDecoder.decode(data, page: page, pageSize: pageSize)
        } catch let error as CategoryCatalogError {
            switch error {
            case .insecureArtwork:
                throw error
            default:
                throw ProviderSearchError.invalidResponse
            }
        }

        let supportedItems = catalogPage.items.filter { item in
            guard let path = item.categoryPath else { return false }
            let components = path.split(separator: ",", omittingEmptySubsequences: false)
            guard components.count >= 3 else { return false }
            return supportedCategoryPrefixes.contains(components.prefix(3).joined(separator: ","))
        }
        return ProviderSearchPage(
            items: supportedItems,
            page: catalogPage.page,
            isLastPage: catalogPage.isLastPage,
            totalCount: catalogPage.totalCount
        )
    }
}

protocol ProviderSearchServing: Sendable {
    func search(query: ProviderSearchQuery, page: Int, pageSize: Int) async throws -> ProviderSearchPage
}

struct ProviderSearchService: @unchecked Sendable, ProviderSearchServing {
    private let session: URLSession
    private let certificateCache: ProviderCertificateCache
    private let siteURL: URL

    init(
        session: URLSession? = nil,
        certificateCache: ProviderCertificateCache = .shared,
        siteURL: URL = URL(string: "https://m.yfsp.tv")!
    ) {
        self.session = session ?? ProviderSessionFactory.make()
        self.certificateCache = certificateCache
        self.siteURL = siteURL
    }

    func search(query: ProviderSearchQuery, page: Int, pageSize: Int) async throws -> ProviderSearchPage {
        if ProcessInfo.processInfo.arguments.contains("-MyVideoUseFixtureFeed") {
            return try await FixtureProviderSearch.shared.page(query: query, page: page, pageSize: pageSize)
        }

        guard
            siteURL.scheme?.lowercased() == "https",
            siteURL.user == nil,
            siteURL.password == nil,
            let host = siteURL.host,
            let domain = RemoteResourceHostValidator.matchingProviderDomain(for: host)
        else {
            throw ProviderSearchError.invalidRequest
        }

        do {
            return try await searchOnce(
                query: query,
                page: page,
                pageSize: pageSize,
                siteHost: host,
                domain: domain
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as ProviderSearchError where error == .invalidResponse {
            await certificateCache.invalidate(for: domain)
            try Task.checkCancellation()
            return try await searchOnce(
                query: query,
                page: page,
                pageSize: pageSize,
                siteHost: host,
                domain: domain
            )
        }
    }

    private func searchOnce(
        query: ProviderSearchQuery,
        page: Int,
        pageSize: Int,
        siteHost: String,
        domain: String
    ) async throws -> ProviderSearchPage {
        let certificate = try await certificateCache.certificate(for: domain) {
            var request = URLRequest(url: siteURL)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, data: data, maximumSize: 1_000_000)
            return try PlaybackCertificateParser.parse(data)
        }
        let apiURL = try ProviderSearchRequestBuilder.makeURL(
            query: query,
            page: page,
            pageSize: pageSize,
            siteHost: siteHost,
            certificate: certificate
        )
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(siteURL.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data, maximumSize: 2_000_000)
        return try ProviderSearchResponseDecoder.decode(data, page: page, pageSize: pageSize)
    }

    private static func validate(response: URLResponse, data: Data, maximumSize: Int) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ProviderSearchError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderSearchError.httpStatus(response.statusCode)
        }
        guard data.count <= maximumSize else {
            throw ProviderSearchError.invalidResponse
        }
        guard
            response.url?.scheme?.lowercased() == "https",
            response.url?.user == nil,
            response.url?.password == nil,
            let finalHost = response.url?.host,
            RemoteResourceHostValidator.matchingProviderDomain(for: finalHost) != nil
        else {
            throw NativePlaybackError.unsupportedSite
        }
    }
}

private actor FixtureProviderSearch {
    static let shared = FixtureProviderSearch()

    private var failedRequests: Set<String> = []

    func page(query: ProviderSearchQuery, page: Int, pageSize: Int) async throws -> ProviderSearchPage {
        guard (1...10_000).contains(page), (1...100).contains(pageSize) else {
            throw ProviderSearchError.invalidRequest
        }

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-MyVideoFixtureSearchDelay") {
            try await Task.sleep(for: .milliseconds(250))
        }
        let failureKey = "\(query.tags)-\(page)"
        let shouldFail = (arguments.contains("-MyVideoFixtureSearchInitialFailure") && page == 1)
            || (arguments.contains("-MyVideoFixtureSearchLoadMoreFailure") && page == 2)
        if shouldFail, !failedRequests.contains(failureKey) {
            failedRequests = failedRequests.union([failureKey])
            throw URLError(.timedOut)
        }
        if arguments.contains("-MyVideoFixtureSearchEmpty") {
            return ProviderSearchPage(items: [], page: page, isLastPage: true, totalCount: 0)
        }

        let totalCount = 48
        let start = min((page - 1) * pageSize, totalCount)
        let end = min(start + pageSize, totalCount)
        let categories = MyVideoCategory.allCases
        let items = (start..<end).map { offset in
            let index = offset + 1
            let category = categories[offset % categories.count]
            let stableKey = index <= categories.count
                ? "fixture-search-\(category.id)"
                : "fixture-search-\(category.id)-\(index)"
            return MyVideoItem(
                listPath: stableKey,
                title: "\(query.tags) Result \(index)",
                subTitle: category == .movie ? "2026" : "Episode \(index)",
                url: "/play/\(stableKey)",
                year: "2026",
                region: "Provider region",
                isSerial: category != .movie,
                latestEpisodeKey: category == .movie ? nil : "fixture-episode-\(index)",
                latestEpisodeTitle: category == .movie ? nil : "Episode \(index)",
                categoryPath: category.catalogCID,
                genre: "Provider genre",
                language: "Provider language",
                quality: "1080P",
                popularity: totalCount - offset,
                rating: "9.0",
                score: 8.8
            )
        }
        return ProviderSearchPage(
            items: items,
            page: page,
            isLastPage: end >= totalCount,
            totalCount: totalCount
        )
    }
}
