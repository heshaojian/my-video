import CoreFoundation
import Foundation

struct CategoryCatalogPage: Equatable, Sendable {
    let items: [MyVideoItem]
    let page: Int
    let isLastPage: Bool
    let totalCount: Int

    init(items: [MyVideoItem], page: Int, isLastPage: Bool, totalCount: Int? = nil) {
        self.items = items
        self.page = page
        self.isLastPage = isLastPage
        self.totalCount = totalCount ?? items.count
    }
}

enum CatalogSort: Int, CaseIterable, Codable, Sendable {
    case added = 0
    case updated = 1
    case popularity = 2
    case rating = 3

    var title: String {
        switch self {
        case .added: "Date Added"
        case .updated: "Last Updated"
        case .popularity: "Popularity"
        case .rating: "Rating"
        }
    }
}

enum CatalogSerialStatus: String, CaseIterable, Codable, Sendable {
    case complete = "0"
    case ongoing = "1"

    var title: String {
        switch self {
        case .complete: "Complete"
        case .ongoing: "Ongoing"
        }
    }
}

struct CatalogQuery: Equatable, Sendable {
    let category: MyVideoCategory
    let genreCID: String?
    let region: String?
    let language: String?
    let year: String?
    let quality: String?
    let status: CatalogSerialStatus?
    let sort: CatalogSort
    let descending: Bool

    init(
        category: MyVideoCategory,
        genreCID: String? = nil,
        region: String? = nil,
        language: String? = nil,
        year: String? = nil,
        quality: String? = nil,
        status: CatalogSerialStatus? = nil,
        sort: CatalogSort = .updated,
        descending: Bool = true
    ) {
        self.category = category
        self.genreCID = genreCID
        self.region = region
        self.language = language
        self.year = year
        self.quality = quality
        self.status = status
        self.sort = sort
        self.descending = descending
    }

    init(
        validating category: MyVideoCategory,
        genreCID: String? = nil,
        region: String? = nil,
        language: String? = nil,
        year: String? = nil,
        quality: String? = nil,
        status: CatalogSerialStatus? = nil,
        sort: CatalogSort = .updated,
        descending: Bool = true
    ) throws {
        let query = CatalogQuery(
            category: category,
            genreCID: genreCID,
            region: region,
            language: language,
            year: year,
            quality: quality,
            status: status,
            sort: sort,
            descending: descending
        )
        try query.validate()
        self = query
    }

    var activeFilterCount: Int {
        [genreCID, region, language, year, quality].compactMap { $0 }.count + (status == nil ? 0 : 1)
    }

    var requestCID: String {
        genreCID ?? category.catalogCID
    }

    func replacing(genreCID: String?) -> CatalogQuery {
        copy(genreCID: genreCID)
    }

    func replacing(region: String?) -> CatalogQuery {
        copy(region: region)
    }

    func replacing(language: String?) -> CatalogQuery {
        copy(language: language)
    }

    func replacing(year: String?) -> CatalogQuery {
        copy(year: year)
    }

    func replacing(quality: String?) -> CatalogQuery {
        copy(quality: quality)
    }

    func replacing(status: CatalogSerialStatus?) -> CatalogQuery {
        copy(status: status)
    }

    func replacing(sort: CatalogSort, descending: Bool) -> CatalogQuery {
        copy(sort: sort, descending: descending)
    }

    func validate() throws {
        if let genreCID {
            let isCategoryPath = genreCID == category.catalogCID || genreCID.hasPrefix("\(category.catalogCID),")
            guard isCategoryPath,
                  genreCID.range(of: #"^[0-9]+(?:,[0-9]+){2,4}$"#, options: .regularExpression) != nil
            else {
                throw CategoryCatalogError.invalidRequest
            }
        }
        for value in [region, language, year, quality].compactMap({ $0 }) {
            guard !value.isEmpty,
                  value.count <= 64,
                  value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                throw CategoryCatalogError.invalidRequest
            }
        }
        guard category != .movie || status == nil else {
            throw CategoryCatalogError.invalidRequest
        }
    }

    private func copy(
        genreCID: String?? = nil,
        region: String?? = nil,
        language: String?? = nil,
        year: String?? = nil,
        quality: String?? = nil,
        status: CatalogSerialStatus?? = nil,
        sort: CatalogSort? = nil,
        descending: Bool? = nil
    ) -> CatalogQuery {
        CatalogQuery(
            category: category,
            genreCID: genreCID ?? self.genreCID,
            region: region ?? self.region,
            language: language ?? self.language,
            year: year ?? self.year,
            quality: quality ?? self.quality,
            status: status ?? self.status,
            sort: sort ?? self.sort,
            descending: descending ?? self.descending
        )
    }
}

struct CatalogFilterOption: Equatable, Identifiable, Sendable {
    let title: String
    let value: String

    var id: String { value }

    init(title: String, value: String) throws {
        guard Self.isSafe(title), Self.isSafe(value) else {
            throw CategoryCatalogError.invalidResponse
        }
        self.title = title
        self.value = value
    }

    private static func isSafe(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 64
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

struct CatalogFilterSet: Equatable, Sendable {
    let genres: [CatalogFilterOption]
    let regions: [CatalogFilterOption]
    let languages: [CatalogFilterOption]
    let years: [CatalogFilterOption]
    let qualities: [CatalogFilterOption]
    let statuses: [CatalogFilterOption]
}

enum CatalogFilterResponseDecoder {
    static func decode(
        conditionData: Data,
        genreData: Data,
        category: MyVideoCategory
    ) throws -> CatalogFilterSet {
        let conditionInfo = try infoArray(from: conditionData)
        guard
            let conditions = conditionInfo.first?["conditions"] as? [String: Any],
            conditions["region"] is [[String: Any]],
            conditions["language"] is [[String: Any]],
            conditions["year"] is [[String: Any]],
            conditions["vipResource"] is [[String: Any]],
            conditions["isSerial"] is [[String: Any]]
        else {
            throw CategoryCatalogError.invalidResponse
        }

        let genres = try infoArray(from: genreData).map { raw -> CatalogFilterOption in
            guard
                string(raw["pid"]) == category.catalogCID,
                let title = string(raw["className"]),
                let path = string(raw["path"])
            else {
                throw CategoryCatalogError.invalidResponse
            }
            _ = try CatalogQuery(validating: category, genreCID: path)
            return try CatalogFilterOption(title: title, value: path)
        }

        let statuses: [CatalogFilterOption]
        if category == .movie {
            statuses = []
        } else {
            statuses = try options(conditions["isSerial"], allowedValues: ["0", "1"])
        }

        return CatalogFilterSet(
            genres: unique(genres),
            regions: try options(conditions["region"]),
            languages: try options(conditions["language"]),
            years: try options(conditions["year"]),
            qualities: try options(conditions["vipResource"]),
            statuses: statuses
        )
    }

    private static func options(_ value: Any?, allowedValues: Set<String>? = nil) throws -> [CatalogFilterOption] {
        guard let rawOptions = value as? [[String: Any]] else {
            throw CategoryCatalogError.invalidResponse
        }
        let decoded = try rawOptions.compactMap { raw -> CatalogFilterOption? in
            guard let title = string(raw["title"]), let value = string(raw["link"]) else {
                throw CategoryCatalogError.invalidResponse
            }
            guard value != "-1" else { return nil }
            guard allowedValues?.contains(value) ?? true else { return nil }
            return try CatalogFilterOption(title: title, value: value)
        }
        return unique(decoded)
    }

    private static func infoArray(from data: Data) throws -> [[String: Any]] {
        guard data.count <= 1_000_000 else {
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
            let info = payload["info"] as? [[String: Any]]
        else {
            throw CategoryCatalogError.invalidResponse
        }
        return info
    }

    private static func unique(_ options: [CatalogFilterOption]) -> [CatalogFilterOption] {
        var values = Set<String>()
        return options.filter { values.insert($0.value).inserted }
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

enum CategoryCatalogMetadataRequestBuilder {
    static func makeConditionsURL(siteHost: String, certificate: PlaybackCertificate) throws -> URL {
        try ProviderRequestSigner.makeSignedURL(
            path: "/v3/list/GetSearchCondition",
            parameters: [URLQueryItem(name: "version", value: "1")],
            siteHost: siteHost,
            certificate: certificate
        )
    }

    static func makeGenresURL(
        category: MyVideoCategory,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        try ProviderRequestSigner.makeSignedURL(
            path: category.genreEndpointPath,
            parameters: [],
            siteHost: siteHost,
            certificate: certificate
        )
    }
}

protocol CategoryCatalogServing: Sendable {
    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage
    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage
    func fetchFilters(category: MyVideoCategory) async throws -> CatalogFilterSet
}

extension CategoryCatalogServing {
    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(category: query.category, page: page, pageSize: pageSize)
    }

    func fetchFilters(category: MyVideoCategory) async throws -> CatalogFilterSet {
        throw CategoryCatalogError.invalidResponse
    }
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
            return "MyVideo returned an invalid catalog response."
        case .insecureArtwork:
            return "MyVideo returned an insecure artwork URL."
        case .httpStatus:
            return "MyVideo could not load this catalog page."
        }
    }
}

enum CategoryCatalogRequestBuilder {
    static func makeURL(
        query: CatalogQuery,
        page: Int,
        pageSize: Int,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        guard (1...10_000).contains(page), (1...100).contains(pageSize) else {
            throw CategoryCatalogError.invalidRequest
        }
        try query.validate()

        var parameters = [
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "orderby", value: String(query.sort.rawValue)),
            URLQueryItem(name: "desc", value: query.descending ? "1" : "0"),
            URLQueryItem(name: "cid", value: query.requestCID)
        ]
        parameters += optionalQueryItem(name: "year", value: query.year)
        parameters += optionalQueryItem(name: "language", value: query.language)
        parameters += optionalQueryItem(name: "region", value: query.region)
        parameters.append(URLQueryItem(name: "isserial", value: query.status?.rawValue ?? "-1"))
        parameters.append(URLQueryItem(name: "isIndex", value: "-1"))
        parameters.append(URLQueryItem(name: "isfree", value: "-1"))
        parameters += optionalQueryItem(name: "vipResource", value: query.quality)
        parameters.append(URLQueryItem(name: "isVertical", value: "-1"))
        return try ProviderRequestSigner.makeSignedURL(
            path: "/api/list/Search",
            parameters: parameters,
            siteHost: siteHost,
            certificate: certificate
        )
    }

    private static func optionalQueryItem(name: String, value: String?) -> [URLQueryItem] {
        value.map { [URLQueryItem(name: name, value: $0)] } ?? []
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
            let rawInfo = payload["info"] as? [[String: Any]],
            let catalog = rawInfo.first,
            let rawItems = catalog["result"] as? [[String: Any]],
            rawItems.count <= pageSize,
            let totalCount = integer(catalog["recordcount"]),
            totalCount >= rawItems.count,
            let maxPage = integer(catalog["maxpage"]),
            maxPage >= 0,
            rawItems.isEmpty || maxPage >= page
        else {
            throw CategoryCatalogError.invalidResponse
        }

        let items = try rawItems.map(decodeItem)
        return CategoryCatalogPage(
            items: items,
            page: page,
            isLastPage: page >= maxPage,
            totalCount: totalCount
        )
    }

    private static func decodeItem(_ raw: [String: Any]) throws -> MyVideoItem {
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
        return MyVideoItem(
            listPath: key,
            title: title,
            image: artwork,
            subTitle: string(raw["lastName"]) ?? string(raw["updates"]),
            addTime: string(raw["addTime"]),
            url: "/play/\(key)",
            year: string(raw["year"]),
            region: string(raw["regional"]),
            isSerial: boolean(raw["isSerial"]),
            latestEpisodeKey: string(raw["lastKey"]),
            latestEpisodeTitle: string(raw["lastName"]),
            categoryPath: string(raw["videoClassID"]),
            genre: string(raw["cid"]),
            language: string(raw["lang"]),
            quality: string(raw["vipResource"]),
            popularity: integer(raw["hot"]),
            rating: string(raw["rating"]),
            score: score(raw["score"])
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
            let host = url.host,
            url.user == nil,
            url.password == nil,
            RemoteResourceHostValidator.isAllowedArtworkHost(host)
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

    private static func score(_ value: Any?) -> Double? {
        let decoded: Double?
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return nil
            }
            decoded = value.doubleValue
        } else if let value = value as? String {
            decoded = Double(value)
        } else {
            decoded = nil
        }
        guard let decoded, decoded.isFinite, (0...10).contains(decoded) else {
            return nil
        }
        return decoded
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }
}

struct CategoryCatalogService: @unchecked Sendable, CategoryCatalogServing {
    private let session: URLSession
    private let filterCache: CategoryCatalogFilterCache
    private let certificateCache: ProviderCertificateCache

    init(
        session: URLSession? = nil,
        filterCache: CategoryCatalogFilterCache = .shared,
        certificateCache: ProviderCertificateCache = .shared
    ) {
        self.session = session ?? ProviderSessionFactory.make()
        self.filterCache = filterCache
        self.certificateCache = certificateCache
    }

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
#if DEBUG
        if MyVideoFixtureRuntime.usesFixtureFeed {
            return try await FixtureCategoryCatalog.shared.page(query: query, page: page, pageSize: pageSize)
        }
#endif

        let category = query.category
        let certificate = try await certificate(for: category)
        guard let host = category.url.host else {
            throw CategoryCatalogError.invalidRequest
        }
        let apiURL = try CategoryCatalogRequestBuilder.makeURL(
            query: query,
            page: page,
            pageSize: pageSize,
            siteHost: host,
            certificate: certificate
        )
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(category.url.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, maximumSize: 2_000_000)
        return try CategoryCatalogResponseDecoder.decode(data, page: page, pageSize: pageSize)
    }

    func fetchFilters(category: MyVideoCategory) async throws -> CatalogFilterSet {
#if DEBUG
        if MyVideoFixtureRuntime.usesFixtureFeed {
            return try FixtureCategoryCatalog.filters(category: category)
        }
#endif
        if let cached = await filterCache.value(for: category) {
            return cached
        }

        let certificate = try await certificate(for: category)
        guard let host = category.url.host else {
            throw CategoryCatalogError.invalidRequest
        }
        let conditionsURL = try CategoryCatalogMetadataRequestBuilder.makeConditionsURL(
            siteHost: host,
            certificate: certificate
        )
        let genresURL = try CategoryCatalogMetadataRequestBuilder.makeGenresURL(
            category: category,
            siteHost: host,
            certificate: certificate
        )
        async let conditionData = fetch(conditionsURL, referer: category.url)
        async let genreData = fetch(genresURL, referer: category.url)
        let filters = try await CatalogFilterResponseDecoder.decode(
            conditionData: conditionData,
            genreData: genreData,
            category: category
        )
        await filterCache.store(filters, for: category)
        return filters
    }

    private func fetch(_ url: URL, referer: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, maximumSize: 1_000_000)
        return data
    }

    private func certificate(for category: MyVideoCategory) async throws -> PlaybackCertificate {
        guard
            let host = category.url.host,
            let domain = RemoteResourceHostValidator.matchingProviderDomain(for: host)
        else {
            throw CategoryCatalogError.invalidRequest
        }
        return try await certificateCache.certificate(for: domain) {
            let (data, response) = try await session.data(from: category.url)
            try validate(response: response, data: data, maximumSize: 1_000_000)
            return try PlaybackCertificateParser.parse(data)
        }
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
        guard
            response.url?.scheme?.lowercased() == "https",
            let finalHost = response.url?.host,
            RemoteResourceHostValidator.matchingProviderDomain(for: finalHost) != nil
        else {
            throw NativePlaybackError.unsupportedSite
        }
    }
}

actor CategoryCatalogFilterCache {
    static let shared = CategoryCatalogFilterCache()
    private var values: [MyVideoCategory: CatalogFilterSet] = [:]

    func value(for category: MyVideoCategory) -> CatalogFilterSet? {
        values[category]
    }

    func store(_ filters: CatalogFilterSet, for category: MyVideoCategory) {
        values = values.merging([category: filters], uniquingKeysWith: { _, new in new })
    }
}

#if DEBUG
private actor FixtureCategoryCatalog {
    static let shared = FixtureCategoryCatalog()
    private var failedRequests: Set<String> = []

    func page(query: CatalogQuery, page: Int, pageSize: Int) throws -> CategoryCatalogPage {
        let category = query.category
        let arguments = ProcessInfo.processInfo.arguments
        let shouldFailInitial = arguments.contains("-MyVideoFixtureCatalogInitialFailure") && page == 1
        let shouldFailMore = arguments.contains("-MyVideoFixtureCatalogLoadMoreFailure") && page == 2
        let failureKey = "\(category.id)-\(page)"
        if (shouldFailInitial || shouldFailMore), !failedRequests.contains(failureKey) {
            failedRequests = failedRequests.union([failureKey])
            throw URLError(.timedOut)
        }

        let allItems = (1...30).map { index in
            MyVideoItem(
                listPath: "fixture-catalog-\(category.id)-\(index)",
                title: "Fixture \(category.title) \(index)",
                subTitle: category == .movie ? "2026" : "更新至 \(index) 集",
                url: "/play/fixture-catalog-\(category.id)-\(index)",
                year: "今年",
                region: index.isMultiple(of: 2) ? "欧美" : "大陆",
                isSerial: category != .movie,
                latestEpisodeKey: category == .movie ? nil : "episode-10",
                latestEpisodeTitle: category == .movie ? nil : "10",
                categoryPath: category.catalogCID,
                genre: "\(category.catalogCID),999",
                language: index.isMultiple(of: 2) ? "英语" : "国语",
                quality: "1080P",
                popularity: index,
                rating: String(index),
                score: Double(index % 10) + 0.5
            )
        }
        let filteredItems = allItems.filter { item in
            guard let index = item.popularity else { return false }
            return (query.genreCID == nil || item.genre == query.genreCID)
                && (query.region == nil || item.region == query.region)
                && (query.language == nil || item.language == query.language)
                && (query.year == nil || item.year == query.year)
                && (query.quality == nil || item.quality == query.quality)
                && (query.status == nil || (query.status == .ongoing) == index.isMultiple(of: 2))
        }
        let orderedItems = filteredItems.sorted { left, right in
            let leftValue = sortValue(for: left, sort: query.sort)
            let rightValue = sortValue(for: right, sort: query.sort)
            return query.descending ? leftValue > rightValue : leftValue < rightValue
        }
        let startIndex = min((page - 1) * pageSize, orderedItems.count)
        let endIndex = min(startIndex + pageSize, orderedItems.count)
        let items = Array(orderedItems[startIndex..<endIndex])
        return CategoryCatalogPage(
            items: items,
            page: page,
            isLastPage: endIndex >= orderedItems.count,
            totalCount: orderedItems.count
        )
    }

    private func sortValue(for item: MyVideoItem, sort: CatalogSort) -> Double {
        let index = Double(item.popularity ?? 0)
        switch sort {
        case .updated: return 31 - index
        case .added, .popularity: return index
        case .rating: return Double(item.rating ?? "") ?? 0
        }
    }

    static func filters(category: MyVideoCategory) throws -> CatalogFilterSet {
        CatalogFilterSet(
            genres: [try CatalogFilterOption(title: "剧情", value: "\(category.catalogCID),999")],
            regions: [
                try CatalogFilterOption(title: "大陆", value: "大陆"),
                try CatalogFilterOption(title: "欧美", value: "欧美")
            ],
            languages: [
                try CatalogFilterOption(title: "国语", value: "国语"),
                try CatalogFilterOption(title: "英语", value: "英语")
            ],
            years: [try CatalogFilterOption(title: "今年", value: "今年")],
            qualities: [try CatalogFilterOption(title: "1080P", value: "1080P")],
            statuses: category == .movie ? [] : [
                try CatalogFilterOption(title: "全集", value: "0"),
                try CatalogFilterOption(title: "连载中", value: "1")
            ]
        )
    }
}
#endif
