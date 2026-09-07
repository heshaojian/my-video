import Foundation

struct CategoryCatalogPage: Equatable, Sendable {
    let items: [AiyifanItem]
    let page: Int
    let isLastPage: Bool
}

protocol CategoryCatalogServing: Sendable {
    func fetchPage(category: AiyifanCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage
}

enum CategoryCatalogError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case insecureArtwork
    case httpStatus(Int)
}

extension CategoryCatalogError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The requested catalog page is invalid."
        case .invalidResponse:
            return "Aiyifan returned an invalid catalog response."
        case .insecureArtwork:
            return "Aiyifan returned an insecure artwork URL."
        case .httpStatus:
            return "Aiyifan could not load this catalog page."
        }
    }
}

enum CategoryCatalogRequestBuilder {
    static func makeURL(
        category: AiyifanCategory,
        page: Int,
        pageSize: Int,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        guard (1...10_000).contains(page), (1...100).contains(pageSize) else {
            throw CategoryCatalogError.invalidRequest
        }

        let parameters = [
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "cid", value: category.catalogCID),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "isn", value: "0"),
            URLQueryItem(name: "isfree", value: "-1")
        ]
        return try ProviderRequestSigner.makeSignedURL(
            path: "/api/list/index",
            parameters: parameters,
            siteHost: siteHost,
            certificate: certificate
        )
    }
}

enum CategoryCatalogResponseDecoder {
    static func decode(_ data: Data, page: Int, pageSize: Int) throws -> CategoryCatalogPage {
        guard
            data.count <= 2_000_000,
            (1...10_000).contains(page),
            (1...100).contains(pageSize)
        else {
            throw CategoryCatalogError.invalidResponse
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CategoryCatalogError.invalidResponse
        }
        guard
            let envelope = object as? [String: Any],
            integer(envelope["ret"]) == 200,
            let payload = envelope["data"] as? [String: Any],
            integer(payload["code"]) == 0,
            let rawItems = payload["info"] as? [[String: Any]]
        else {
            throw CategoryCatalogError.invalidResponse
        }

        let items = try rawItems.map(decodeItem)
        return CategoryCatalogPage(items: items, page: page, isLastPage: rawItems.count < pageSize)
    }

    private static func decodeItem(_ raw: [String: Any]) throws -> AiyifanItem {
        guard
            let key = string(raw["key"]),
            key.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
            let title = string(raw["title"]),
            !title.isEmpty,
            title.count <= 500
        else {
            throw CategoryCatalogError.invalidResponse
        }

        let artwork = try secureArtwork(raw["image"] ?? raw["img"] ?? raw["verticalImg"])
        return AiyifanItem(
            listPath: key,
            title: title,
            image: artwork,
            subTitle: string(raw["lastName"]) ?? string(raw["updates"]),
            addTime: string(raw["addTime"]),
            url: "/play/\(key)",
            year: string(raw["year"]),
            region: string(raw["regional"])
        )
    }

    private static func secureArtwork(_ value: Any?) throws -> String? {
        guard let rawValue = string(value), !rawValue.isEmpty else {
            return nil
        }
        let normalized = rawValue.hasPrefix("//") ? "https:\(rawValue)" : rawValue
        guard
            let url = URL(string: normalized),
            url.scheme?.lowercased() == "https",
            url.host?.isEmpty == false
        else {
            throw CategoryCatalogError.insecureArtwork
        }
        return normalized
    }

    private static func string(_ value: Any?) -> String? {
        let result: String?
        if let value = value as? String {
            result = value
        } else if let value = value as? NSNumber {
            result = value.stringValue
        } else {
            result = nil
        }
        return result?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

struct CategoryCatalogService: @unchecked Sendable, CategoryCatalogServing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPage(category: AiyifanCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        if ProcessInfo.processInfo.arguments.contains("-AiyifanUseFixtureFeed") {
            return try await FixtureCategoryCatalog.shared.page(category: category, page: page, pageSize: pageSize)
        }

        let (pageData, pageResponse) = try await session.data(from: category.url)
        try validate(response: pageResponse, data: pageData, maximumSize: 1_000_000)
        let certificate = try PlaybackCertificateParser.parse(pageData)
        guard let host = category.url.host else {
            throw CategoryCatalogError.invalidRequest
        }
        let apiURL = try CategoryCatalogRequestBuilder.makeURL(
            category: category,
            page: page,
            pageSize: pageSize,
            siteHost: host,
            certificate: certificate
        )
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, maximumSize: 2_000_000)
        return try CategoryCatalogResponseDecoder.decode(data, page: page, pageSize: pageSize)
    }

    private func validate(response: URLResponse, data: Data, maximumSize: Int) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CategoryCatalogError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CategoryCatalogError.httpStatus(response.statusCode)
        }
        guard data.count <= maximumSize else {
            throw CategoryCatalogError.invalidResponse
        }
    }
}

private actor FixtureCategoryCatalog {
    static let shared = FixtureCategoryCatalog()
    private var failedRequests: Set<String> = []

    func page(category: AiyifanCategory, page: Int, pageSize: Int) throws -> CategoryCatalogPage {
        let arguments = ProcessInfo.processInfo.arguments
        let shouldFailInitial = arguments.contains("-AiyifanFixtureCatalogInitialFailure") && page == 1
        let shouldFailMore = arguments.contains("-AiyifanFixtureCatalogLoadMoreFailure") && page == 2
        let failureKey = "\(category.id)-\(page)"
        if (shouldFailInitial || shouldFailMore), !failedRequests.contains(failureKey) {
            failedRequests = failedRequests.union([failureKey])
            throw URLError(.timedOut)
        }

        let firstIndex = ((page - 1) * pageSize) + 1
        let count = page == 1 ? pageSize : (page == 2 ? 6 : 0)
        let items = (firstIndex..<(firstIndex + count)).map { index in
            AiyifanItem(
                listPath: "fixture-catalog-\(category.id)-\(index)",
                title: "Fixture \(category.title) \(index)",
                subTitle: category == .movie ? "2026" : "更新至 \(index) 集",
                url: "/play/fixture-catalog-\(category.id)-\(index)",
                year: "2026",
                region: index.isMultiple(of: 2) ? "中国" : "US"
            )
        }
        return CategoryCatalogPage(items: items, page: page, isLastPage: page >= 2)
    }
}
