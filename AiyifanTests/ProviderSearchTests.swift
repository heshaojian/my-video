import Foundation
import XCTest
@testable import Aiyifan

final class ProviderSearchContractTests: XCTestCase {
    override func tearDown() {
        SearchURLProtocol.reset()
        super.tearDown()
    }

    func testQueryTrimsInputAndRejectsInvalidValues() throws {
        XCTAssertEqual(try ProviderSearchQuery(validating: "  披荆斩棘 2026  ").tags, "披荆斩棘 2026")
        XCTAssertThrowsError(try ProviderSearchQuery(validating: "   "))
        XCTAssertThrowsError(try ProviderSearchQuery(validating: "Line\nBreak"))
        XCTAssertThrowsError(try ProviderSearchQuery(validating: String(repeating: "a", count: 81)))
    }

    func testRequestBuilderUsesGlobalRelevantProviderSearchAndStableParameterOrder() throws {
        let query = try ProviderSearchQuery(validating: "  特立独行  ")
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        let url = try ProviderSearchRequestBuilder.makeURL(
            query: query,
            page: 2,
            pageSize: 24,
            siteHost: "www.yfsp.tv",
            certificate: certificate
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "m10.yfsp.tv")
        XCTAssertEqual(components.path, "/api/list/Search")
        XCTAssertEqual(queryItems.prefix(10).map(\.name), [
            "cinema", "page", "size", "orderby", "desc", "cid", "tags", "isserial", "isIndex", "isfree"
        ])
        XCTAssertEqual(values["cinema"], "1")
        XCTAssertEqual(values["page"], "2")
        XCTAssertEqual(values["size"], "24")
        XCTAssertEqual(values["orderby"], "-1")
        XCTAssertEqual(values["desc"], "1")
        XCTAssertEqual(values["cid"], "0,1")
        XCTAssertEqual(values["tags"], "特立独行")
        XCTAssertEqual(values["isserial"], "-1")
        XCTAssertEqual(values["isIndex"], "-1")
        XCTAssertEqual(values["isfree"], "-1")
        XCTAssertEqual(values["isVertical"], "-1")
        XCTAssertEqual(values["pub"], "public-test")
        XCTAssertNotNil(values["vv"])
    }

    func testRequestBuilderRejectsInvalidPagingAndUnsupportedHost() throws {
        let query = try ProviderSearchQuery(validating: "title")
        let certificate = PlaybackCertificate(publicKey: "public", privateKey: "private")

        for (page, pageSize) in [(0, 24), (1, 0), (10_001, 24), (1, 101)] {
            XCTAssertThrowsError(try ProviderSearchRequestBuilder.makeURL(
                query: query,
                page: page,
                pageSize: pageSize,
                siteHost: "www.yfsp.tv",
                certificate: certificate
            ))
        }
        XCTAssertThrowsError(try ProviderSearchRequestBuilder.makeURL(
            query: query,
            page: 1,
            pageSize: 24,
            siteHost: "attacker.example",
            certificate: certificate
        )) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedSite)
        }
    }

    func testDecoderPreservesProviderOrderAndPlayableMetadataForSupportedCategories() throws {
        let data = Self.searchResponse(count: 5, maxPage: 2, items: [
            Self.item(key: "variety-first", title: "综艺", categoryPath: "0,1,5,39", score: "9.6"),
            Self.item(key: "movie-second", title: "电影", categoryPath: "0,1,3,28", score: "8.8"),
            Self.item(key: "series-third", title: "电视剧", categoryPath: "0,1,4,137", score: "8.2"),
            Self.item(key: "anime-fourth", title: "动漫", categoryPath: "0,1,6,46", score: "7.9"),
            Self.item(key: "short-excluded", title: "短剧", categoryPath: "0,2,7", score: "9.9")
        ])

        let page = try ProviderSearchResponseDecoder.decode(data, page: 1, pageSize: 24)

        XCTAssertEqual(page.items.map(\.id), ["variety-first", "movie-second", "series-third", "anime-fourth"])
        XCTAssertEqual(page.items.first?.playURL.absoluteString, "https://m.yfsp.tv/play/variety-first")
        XCTAssertEqual(page.items.first?.latestEpisodeKey, "episode-12")
        XCTAssertEqual(page.items.first?.latestEpisodeTitle, "第12期")
        XCTAssertEqual(page.items.first?.quality, "4K")
        XCTAssertEqual(page.items.first?.score, 9.6)
        XCTAssertEqual(page.items.first?.thumbnailURL?.absoluteString, "https://static.yfsp.tv/variety-first.jpg")
        XCTAssertEqual(page.totalCount, 5)
        XCTAssertFalse(page.isLastPage)
    }

    func testDecoderRejectsMalformedStableKeysAndInsecureArtwork() {
        let invalidKey = Self.searchResponse(items: [
            Self.item(key: "../escape", title: "Bad", categoryPath: "0,1,3")
        ])
        let insecureArtwork = Self.searchResponse(items: [[
            "key": "movie-safe",
            "title": "Bad image",
            "image": "http://static.yfsp.tv/poster.jpg",
            "videoClassID": "0,1,3"
        ]])

        XCTAssertThrowsError(try ProviderSearchResponseDecoder.decode(invalidKey, page: 1, pageSize: 24))
        XCTAssertThrowsError(try ProviderSearchResponseDecoder.decode(insecureArtwork, page: 1, pageSize: 24))
    }

    func testDecoderReturnsImmutableEmptyPageWhenNothingIsSupported() throws {
        let data = Self.searchResponse(count: 1, items: [
            Self.item(key: "news", title: "News", categoryPath: "0,2,9")
        ])

        let page = try ProviderSearchResponseDecoder.decode(data, page: 1, pageSize: 24)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.totalCount, 1)
        XCTAssertTrue(page.isLastPage)
    }

    func testServiceUsesValidatedSignedTransportWithoutPersistingRequestSecrets() async throws {
        let cache = ProviderCertificateCache(lifetime: 60)
        _ = try await cache.certificate(for: "yfsp.tv") {
            PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")
        }
        let observation = SearchRequestObservation()
        SearchURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            observation.record(
                path: url.path,
                host: url.host,
                tags: values["tags"],
                referer: request.value(forHTTPHeaderField: "Referer")
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let data = Self.searchResponse(items: [
                Self.item(key: "movie-live", title: "Live", categoryPath: "0,1,3")
            ])
            return (response, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = ProviderSearchService(session: session, certificateCache: cache)

        let page = try await service.search(
            query: ProviderSearchQuery(validating: " Live "),
            page: 1,
            pageSize: 24
        )

        XCTAssertEqual(page.items.map(\.id), ["movie-live"])
        XCTAssertEqual(observation.path, "/api/list/Search")
        XCTAssertEqual(observation.host, "m10.yfsp.tv")
        XCTAssertEqual(observation.tags, "Live")
        XCTAssertEqual(observation.referer, "https://m.yfsp.tv")
    }

    func testServiceRejectsSuccessfulResponseFromUnsupportedFinalHost() async throws {
        let cache = ProviderCertificateCache(lifetime: 60)
        _ = try await cache.certificate(for: "yfsp.tv") {
            PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")
        }
        SearchURLProtocol.setHandler { _ in
            let finalURL = try XCTUnwrap(URL(string: "https://attacker.invalid/results"))
            let response = try XCTUnwrap(HTTPURLResponse(
                url: finalURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Self.searchResponse(items: []))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = ProviderSearchService(session: session, certificateCache: cache)

        do {
            _ = try await service.search(
                query: ProviderSearchQuery(validating: "Title"),
                page: 1,
                pageSize: 24
            )
            XCTFail("Expected unsupported final host rejection")
        } catch {
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedSite)
        }
    }

    func testServiceRetriesInvalidSignedResponseWithFreshCertificate() async throws {
        let cache = ProviderCertificateCache(lifetime: 60)
        let pageLoads = SearchLockedCounter()
        SearchURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let data: Data
            if url.path == "/api/list/Search" {
                let publicKey = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "pub" }?.value
                data = publicKey == "public-1"
                    ? Data(#"{"ret":200,"data":{"code":1,"info":[]}}"#.utf8)
                    : Self.searchResponse(items: [
                        Self.item(key: "fresh-result", title: "Fresh", categoryPath: "0,1,3")
                    ])
            } else {
                let version = pageLoads.increment()
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-\(version)","privateKey":["private-\(version)"]}}]};</script>
                """.utf8)
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let page = try await ProviderSearchService(
            session: session,
            certificateCache: cache
        ).search(
            query: ProviderSearchQuery(validating: "Fresh"),
            page: 1,
            pageSize: 24
        )

        XCTAssertEqual(page.items.map(\.id), ["fresh-result"])
        XCTAssertEqual(pageLoads.value, 2)
    }

    private static func item(
        key: String,
        title: String,
        categoryPath: String,
        score: String = "8.0"
    ) -> [String: Any] {
        [
            "key": key,
            "title": title,
            "image": "//static.yfsp.tv/\(key).jpg",
            "lastName": "第12期",
            "lastKey": "episode-12",
            "isSerial": true,
            "videoClassID": categoryPath,
            "cid": "Provider genre",
            "lang": "Provider language",
            "vipResource": "4K",
            "hot": 12_345,
            "rating": "9.1",
            "score": score
        ]
    }

    private static func searchResponse(
        count: Int? = nil,
        maxPage: Int = 1,
        items: [[String: Any]]
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "ret": 200,
            "data": ["code": 0, "info": [[
                "recordcount": count ?? items.count,
                "maxpage": maxPage,
                "result": items
            ]]]
        ])
    }
}

private final class SearchRequestObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (path: String?, host: String?, tags: String?, referer: String?) = (nil, nil, nil, nil)

    var path: String? { lock.withLock { storage.path } }
    var host: String? { lock.withLock { storage.host } }
    var tags: String? { lock.withLock { storage.tags } }
    var referer: String? { lock.withLock { storage.referer } }

    func record(path: String?, host: String?, tags: String?, referer: String?) {
        lock.withLock {
            storage = (path, host, tags, referer)
        }
    }
}

private final class SearchLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int { lock.withLock { storage } }

    func increment() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}

private final class SearchURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func setHandler(_ newHandler: @escaping Handler) {
        lock.withLock { handler = newHandler }
    }

    static func reset() {
        lock.withLock { handler = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let currentHandler = Self.lock.withLock { Self.handler }
            let handler = try XCTUnwrap(currentHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class ProviderSearchViewModelTests: XCTestCase {
    func testInitialStateIsCollapsedAndTypingDoesNotSearch() async {
        let service = SearchStubService()
        let viewModel = ProviderSearchViewModel(service: service)

        XCTAssertFalse(viewModel.isExpanded)
        XCTAssertTrue(viewModel.items.isEmpty)
        viewModel.expand()
        viewModel.query = "Movie"
        try? await Task.sleep(for: .milliseconds(20))
        let requests = await service.requests()

        XCTAssertTrue(viewModel.isExpanded)
        XCTAssertEqual(requests.count, 0)
    }

    func testSubmitTrimsQueryAndPublishesResults() async {
        let result = MyVideoItem(listPath: "movie-one", title: "Movie One", categoryPath: "0,1,3")
        let service = SearchStubService(responses: [
            .success(ProviderSearchPage(items: [result], page: 1, isLastPage: true, totalCount: 1))
        ])
        let viewModel = ProviderSearchViewModel(pageSize: 24, service: service)
        viewModel.expand()
        viewModel.query = "  Movie One  "

        let submitted = await viewModel.submit()

        XCTAssertTrue(submitted)
        XCTAssertEqual(viewModel.query, "Movie One")
        XCTAssertEqual(viewModel.submittedQuery, "Movie One")
        XCTAssertEqual(viewModel.items, [result])
        XCTAssertEqual(viewModel.totalCount, 1)
        XCTAssertTrue(viewModel.reachedEnd)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        let requests = await service.requests()
        XCTAssertEqual(requests.map(\.query.tags), ["Movie One"])
    }

    func testEmptyQueryIsRejectedWithoutCallingService() async {
        let service = SearchStubService()
        let viewModel = ProviderSearchViewModel(service: service)
        viewModel.expand()
        viewModel.query = "   "

        let submitted = await viewModel.submit()
        let requests = await service.requests()

        XCTAssertFalse(submitted)
        XCTAssertEqual(viewModel.validationMessage, "Enter a title to search.")
        XCTAssertEqual(requests.count, 0)
    }

    func testLoadingAndEmptyResultStatesAreExplicit() async throws {
        let service = SearchStubService(responses: [
            .delayed(.milliseconds(80), ProviderSearchPage(items: [], page: 1, isLastPage: true, totalCount: 0))
        ])
        let viewModel = ProviderSearchViewModel(service: service)
        viewModel.expand()
        viewModel.query = "Nothing"

        let task = Task { await viewModel.submit() }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.showsEmptyResults)
        _ = await task.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.showsEmptyResults)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailureKeepsSubmittedQueryAndRetrySucceeds() async {
        let result = MyVideoItem(listPath: "retry-result", title: "Retry Result", categoryPath: "0,1,3")
        let service = SearchStubService(responses: [
            .failure(URLError(.timedOut)),
            .success(ProviderSearchPage(items: [result], page: 1, isLastPage: true, totalCount: 1))
        ])
        let viewModel = ProviderSearchViewModel(service: service)
        viewModel.expand()
        viewModel.query = "Retry Me"

        let firstAttempt = await viewModel.submit()
        XCTAssertFalse(firstAttempt)
        XCTAssertEqual(viewModel.submittedQuery, "Retry Me")
        XCTAssertNotNil(viewModel.errorMessage)

        let retrySucceeded = await viewModel.retry()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(viewModel.items, [result])
        XCTAssertNil(viewModel.errorMessage)
        let requests = await service.requests()
        XCTAssertEqual(requests.count, 2)
    }

    func testPaginationDeduplicatesAndCanRetry() async throws {
        let first = MyVideoItem(listPath: "one", title: "One", categoryPath: "0,1,3")
        let second = MyVideoItem(listPath: "two", title: "Two", categoryPath: "0,1,4")
        let service = SearchStubService(responses: [
            .success(ProviderSearchPage(items: [first], page: 1, isLastPage: false, totalCount: 2)),
            .failure(URLError(.networkConnectionLost)),
            .success(ProviderSearchPage(items: [first, second], page: 2, isLastPage: true, totalCount: 2))
        ])
        let viewModel = ProviderSearchViewModel(pageSize: 1, service: service)
        viewModel.expand()
        viewModel.query = "Paged"
        let submitted = await viewModel.submit()
        XCTAssertTrue(submitted)

        await viewModel.loadMoreIfNeeded(currentItem: first)
        XCTAssertEqual(viewModel.items, [first])
        XCTAssertNotNil(viewModel.loadMoreErrorMessage)

        await viewModel.retryLoadMore()
        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertNil(viewModel.loadMoreErrorMessage)
        XCTAssertTrue(viewModel.reachedEnd)
        let requests = await service.requests()
        XCTAssertEqual(requests.map(\.page), [1, 2, 2])
    }

    func testCancelCollapsesClearsAndCancelsPendingSearch() async throws {
        let result = MyVideoItem(listPath: "late", title: "Late", categoryPath: "0,1,3")
        let service = SearchStubService(responses: [
            .delayed(.milliseconds(200), ProviderSearchPage(items: [result], page: 1, isLastPage: true, totalCount: 1))
        ])
        let viewModel = ProviderSearchViewModel(service: service)
        viewModel.expand()
        viewModel.query = "Late"

        let task = Task { await viewModel.submit() }
        try await Task.sleep(for: .milliseconds(20))
        viewModel.cancel()
        _ = await task.value

        XCTAssertFalse(viewModel.isExpanded)
        XCTAssertEqual(viewModel.query, "")
        XCTAssertNil(viewModel.submittedQuery)
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        let observedCancellation = await service.observedCancellation()
        XCTAssertTrue(observedCancellation)
    }

    func testNewSubmissionSuppressesStaleResultEvenWhenServiceIgnoresCancellation() async throws {
        let stale = MyVideoItem(listPath: "stale", title: "Stale", categoryPath: "0,1,3")
        let fresh = MyVideoItem(listPath: "fresh", title: "Fresh", categoryPath: "0,1,4")
        let service = SearchStubService(responses: [
            .uncancellable(.milliseconds(100), ProviderSearchPage(items: [stale], page: 1, isLastPage: true, totalCount: 1)),
            .success(ProviderSearchPage(items: [fresh], page: 1, isLastPage: true, totalCount: 1))
        ])
        let viewModel = ProviderSearchViewModel(service: service)
        viewModel.expand()
        viewModel.query = "Old"
        let oldTask = Task { await viewModel.submit() }
        try await Task.sleep(for: .milliseconds(20))

        viewModel.query = "New"
        let newSubmitted = await viewModel.submit()
        XCTAssertTrue(newSubmitted)
        _ = await oldTask.value

        XCTAssertEqual(viewModel.submittedQuery, "New")
        XCTAssertEqual(viewModel.items, [fresh])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testNewSubmissionDuringPaginationClearsStaleLoadingState() async throws {
        let first = MyVideoItem(listPath: "first", title: "First", categoryPath: "0,1,3")
        let stale = MyVideoItem(listPath: "stale-page", title: "Stale Page", categoryPath: "0,1,3")
        let fresh = MyVideoItem(listPath: "fresh", title: "Fresh", categoryPath: "0,1,4")
        let service = SearchStubService(responses: [
            .success(ProviderSearchPage(items: [first], page: 1, isLastPage: false, totalCount: 2)),
            .uncancellable(.milliseconds(100), ProviderSearchPage(items: [stale], page: 2, isLastPage: true, totalCount: 2)),
            .success(ProviderSearchPage(items: [fresh], page: 1, isLastPage: true, totalCount: 1))
        ])
        let viewModel = ProviderSearchViewModel(pageSize: 1, service: service)
        viewModel.expand()
        viewModel.query = "Old"
        let oldSubmitted = await viewModel.submit()
        XCTAssertTrue(oldSubmitted)

        let paginationTask = Task { await viewModel.loadMoreIfNeeded(currentItem: first) }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(viewModel.isLoadingMore)

        viewModel.query = "New"
        let newSubmitted = await viewModel.submit()
        XCTAssertTrue(newSubmitted)
        _ = await paginationTask.value

        XCTAssertEqual(viewModel.items, [fresh])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadMoreErrorMessage)
    }

    func testInitialSearchSkipsFilteredEmptyPagesUntilSupportedResultsAppear() async {
        let supported = MyVideoItem(listPath: "supported", title: "Supported", categoryPath: "0,1,6")
        let service = SearchStubService(responses: [
            .success(ProviderSearchPage(items: [], page: 1, isLastPage: false, totalCount: 2)),
            .success(ProviderSearchPage(items: [supported], page: 2, isLastPage: true, totalCount: 2))
        ])
        let viewModel = ProviderSearchViewModel(pageSize: 1, service: service)
        viewModel.expand()
        viewModel.query = "Supported"

        let submitted = await viewModel.submit()
        XCTAssertTrue(submitted)

        XCTAssertEqual(viewModel.items, [supported])
        XCTAssertTrue(viewModel.reachedEnd)
        XCTAssertFalse(viewModel.showsEmptyResults)
        let requests = await service.requests()
        XCTAssertEqual(requests.map(\.page), [1, 2])
    }

    func testPaginationSkipsFilteredEmptyPagesUntilSupportedResultsAppear() async {
        let first = MyVideoItem(listPath: "first", title: "First", categoryPath: "0,1,3")
        let later = MyVideoItem(listPath: "later", title: "Later", categoryPath: "0,1,5")
        let service = SearchStubService(responses: [
            .success(ProviderSearchPage(items: [first], page: 1, isLastPage: false, totalCount: 3)),
            .success(ProviderSearchPage(items: [], page: 2, isLastPage: false, totalCount: 3)),
            .success(ProviderSearchPage(items: [later], page: 3, isLastPage: true, totalCount: 3))
        ])
        let viewModel = ProviderSearchViewModel(pageSize: 1, service: service)
        viewModel.expand()
        viewModel.query = "Paged"
        _ = await viewModel.submit()

        await viewModel.loadMoreIfNeeded(currentItem: first)

        XCTAssertEqual(viewModel.items, [first, later])
        XCTAssertTrue(viewModel.reachedEnd)
        let requests = await service.requests()
        XCTAssertEqual(requests.map(\.page), [1, 2, 3])
    }

    func testFilteredEmptyPageSkippingIsBoundedAndCanContinue() async {
        let later = MyVideoItem(listPath: "later", title: "Later", categoryPath: "0,1,5")
        let service = SearchStubService(responses: [
            .success(ProviderSearchPage(items: [], page: 1, isLastPage: false, totalCount: 5)),
            .success(ProviderSearchPage(items: [], page: 2, isLastPage: false, totalCount: 5)),
            .success(ProviderSearchPage(items: [], page: 3, isLastPage: false, totalCount: 5)),
            .success(ProviderSearchPage(items: [], page: 4, isLastPage: false, totalCount: 5)),
            .success(ProviderSearchPage(items: [later], page: 5, isLastPage: true, totalCount: 5))
        ])
        let viewModel = ProviderSearchViewModel(pageSize: 1, service: service)
        viewModel.expand()
        viewModel.query = "Deep"

        _ = await viewModel.submit()

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertTrue(viewModel.canContinueFilteredSearch)
        XCTAssertFalse(viewModel.showsEmptyResults)
        var requests = await service.requests()
        XCTAssertEqual(requests.map(\.page), [1, 2, 3])

        await viewModel.retryLoadMore()

        XCTAssertEqual(viewModel.items, [later])
        XCTAssertFalse(viewModel.canContinueFilteredSearch)
        requests = await service.requests()
        XCTAssertEqual(requests.map(\.page), [1, 2, 3, 4, 5])
    }
}

private actor SearchStubService: ProviderSearchServing {
    struct Request: Sendable {
        let query: ProviderSearchQuery
        let page: Int
        let pageSize: Int
    }

    enum Response: @unchecked Sendable {
        case success(ProviderSearchPage)
        case failure(Error)
        case delayed(Duration, ProviderSearchPage)
        case uncancellable(Duration, ProviderSearchPage)
    }

    private var queuedResponses: [Response]
    private var recordedRequests: [Request] = []
    private var wasCancelled = false

    init(responses: [Response] = []) {
        queuedResponses = responses
    }

    func search(query: ProviderSearchQuery, page: Int, pageSize: Int) async throws -> ProviderSearchPage {
        recordedRequests.append(Request(query: query, page: page, pageSize: pageSize))
        guard !queuedResponses.isEmpty else {
            return ProviderSearchPage(items: [], page: page, isLastPage: true, totalCount: 0)
        }
        let response = queuedResponses.removeFirst()
        switch response {
        case .success(let page):
            return page
        case .failure(let error):
            throw error
        case .delayed(let duration, let page):
            do {
                try await Task.sleep(for: duration)
            } catch is CancellationError {
                wasCancelled = true
                throw CancellationError()
            }
            return page
        case .uncancellable(let duration, let page):
            try? await Task.sleep(for: duration)
            return page
        }
    }

    func requests() -> [Request] {
        recordedRequests
    }

    func observedCancellation() -> Bool {
        wasCancelled
    }
}
