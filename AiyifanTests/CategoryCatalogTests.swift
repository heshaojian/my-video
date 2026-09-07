import Foundation
import XCTest
@testable import Aiyifan

final class CategoryCatalogContractTests: XCTestCase {
    func testCategoriesUseProviderCatalogIdentifiers() {
        XCTAssertEqual(AiyifanCategory.movie.catalogCID, "0,1,3")
        XCTAssertEqual(AiyifanCategory.drama.catalogCID, "0,1,4")
        XCTAssertEqual(AiyifanCategory.variety.catalogCID, "0,1,5")
        XCTAssertEqual(AiyifanCategory.anime.catalogCID, "0,1,6")
    }

    func testRequestBuilderSignsCatalogRequestDeterministically() throws {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        let url = try CategoryCatalogRequestBuilder.makeURL(
            category: .drama,
            page: 2,
            pageSize: 24,
            siteHost: "www.yfsp.tv",
            certificate: certificate
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "m10.yfsp.tv")
        XCTAssertEqual(components.path, "/api/list/index")
        XCTAssertEqual(values["cinema"], "1")
        XCTAssertEqual(values["page"], "2")
        XCTAssertEqual(values["cid"], "0,1,4")
        XCTAssertEqual(values["size"], "24")
        XCTAssertEqual(values["isn"], "0")
        XCTAssertEqual(values["isfree"], "-1")
        XCTAssertEqual(values["vv"], "ad437e2fa799355de0a4f68c4a77f173")
        XCTAssertEqual(values["pub"], "public-test")
    }

    func testRequestBuilderRejectsInvalidPageAndUnsupportedHost() {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        XCTAssertThrowsError(try CategoryCatalogRequestBuilder.makeURL(
            category: .movie,
            page: 0,
            pageSize: 24,
            siteHost: "www.yfsp.tv",
            certificate: certificate
        ))
        XCTAssertThrowsError(try CategoryCatalogRequestBuilder.makeURL(
            category: .movie,
            page: 1,
            pageSize: 24,
            siteHost: "attacker.example",
            certificate: certificate
        )) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedSite)
        }
    }

    func testDecoderMapsCatalogMetadataAndNormalizesArtwork() throws {
        let data = catalogResponse(items: [[
            "key": "drama-42",
            "title": "The Test Series",
            "image": "//static.yfsp.tv/drama-42.jpg",
            "lastName": "更新至 12 集",
            "year": "2026",
            "regional": "中国",
            "addTime": "2026-09-07 08:00:00"
        ]])

        let page = try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24)
        let item = try XCTUnwrap(page.items.first)

        XCTAssertEqual(item.id, "drama-42")
        XCTAssertEqual(item.title, "The Test Series")
        XCTAssertEqual(item.updateLabel, "更新至 12 集")
        XCTAssertEqual(item.year, "2026")
        XCTAssertEqual(item.region, "中国")
        XCTAssertEqual(item.thumbnailURL?.absoluteString, "https://static.yfsp.tv/drama-42.jpg")
        XCTAssertEqual(item.playURL.absoluteString, "https://m.yfsp.tv/play/drama-42")
        XCTAssertTrue(page.isLastPage)
    }

    func testDecoderRejectsInvalidEnvelopeMalformedItemsAndInsecureArtwork() {
        let invalidEnvelope = Data(#"{"ret":500,"data":{"code":0,"info":[]}}"#.utf8)
        let malformed = catalogResponse(items: [["key": "", "title": "Missing key"]])
        let insecureArtwork = catalogResponse(items: [[
            "key": "movie-1", "title": "Movie", "image": "http://static.yfsp.tv/poster.jpg"
        ]])

        for data in [invalidEnvelope, malformed, insecureArtwork] {
            XCTAssertThrowsError(try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24))
        }
    }

    func testDecoderRejectsOversizedResponse() {
        let data = Data(repeating: 0x20, count: 2_000_001)

        XCTAssertThrowsError(try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24))
    }

    private func catalogResponse(items: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "ret": 200,
            "data": ["code": 0, "info": items]
        ])
    }
}

@MainActor
final class CategoryCatalogViewModelTests: XCTestCase {
    func testInitialLoadAndPaginationDeduplicateItems() async {
        let first = AiyifanItem(listPath: "one", title: "One")
        let duplicate = AiyifanItem(listPath: "two", title: "Two")
        let third = AiyifanItem(listPath: "three", title: "Three")
        let service = StubCategoryCatalogService(pages: [
            1: .success(CategoryCatalogPage(items: [first, duplicate], page: 1, isLastPage: false)),
            2: .success(CategoryCatalogPage(items: [duplicate, third], page: 2, isLastPage: true))
        ])
        let viewModel = CategoryCatalogViewModel(category: .movie, pageSize: 2, service: service)

        await viewModel.loadInitial()
        await viewModel.loadMoreIfNeeded(currentItem: duplicate)

        XCTAssertEqual(viewModel.items.map(\.id), ["one", "two", "three"])
        XCTAssertEqual(viewModel.nextPage, 3)
        XCTAssertTrue(viewModel.reachedEnd)
        XCTAssertNil(viewModel.initialErrorMessage)
        XCTAssertNil(viewModel.loadMoreErrorMessage)
    }

    func testLoadMoreFailureKeepsItemsAndRetrySucceeds() async {
        let first = AiyifanItem(listPath: "one", title: "One")
        let second = AiyifanItem(listPath: "two", title: "Two")
        let service = StubCategoryCatalogService(pages: [
            1: .success(CategoryCatalogPage(items: [first], page: 1, isLastPage: false)),
            2: .failureThenSuccess(CategoryCatalogPage(items: [second], page: 2, isLastPage: true))
        ])
        let viewModel = CategoryCatalogViewModel(category: .movie, pageSize: 1, service: service)

        await viewModel.loadInitial()
        await viewModel.loadMoreIfNeeded(currentItem: first)
        XCTAssertEqual(viewModel.items, [first])
        XCTAssertNotNil(viewModel.loadMoreErrorMessage)

        await viewModel.retryLoadMore()
        XCTAssertEqual(viewModel.items, [first, second])
        XCTAssertNil(viewModel.loadMoreErrorMessage)
        XCTAssertTrue(viewModel.reachedEnd)
    }

    func testRefreshReplacesItemsAndIgnoresOlderInitialResponse() async throws {
        let old = AiyifanItem(listPath: "old", title: "Old")
        let fresh = AiyifanItem(listPath: "fresh", title: "Fresh")
        let service = SequencedCategoryCatalogService(old: old, fresh: fresh)
        let viewModel = CategoryCatalogViewModel(category: .drama, pageSize: 24, service: service)

        let initialTask = Task { await viewModel.loadInitial() }
        try await Task.sleep(for: .milliseconds(20))
        await viewModel.refresh()
        await initialTask.value

        XCTAssertEqual(viewModel.items, [fresh])
        XCTAssertEqual(viewModel.nextPage, 2)
    }
}

private actor StubCategoryCatalogService: CategoryCatalogServing {
    enum Response: Sendable {
        case success(CategoryCatalogPage)
        case failure
        case failureThenSuccess(CategoryCatalogPage)
    }

    private let pages: [Int: Response]
    private var attempts: [Int: Int] = [:]

    init(pages: [Int: Response]) {
        self.pages = pages
    }

    func fetchPage(category: AiyifanCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        let attempt = attempts[page, default: 0]
        attempts = attempts.merging([page: attempt + 1], uniquingKeysWith: { _, new in new })
        guard let response = pages[page] else { throw URLError(.resourceUnavailable) }
        switch response {
        case .success(let result):
            return result
        case .failure:
            throw URLError(.notConnectedToInternet)
        case .failureThenSuccess(let result):
            if attempt == 0 { throw URLError(.timedOut) }
            return result
        }
    }
}

private actor SequencedCategoryCatalogService: CategoryCatalogServing {
    private let old: AiyifanItem
    private let fresh: AiyifanItem
    private var callCount = 0

    init(old: AiyifanItem, fresh: AiyifanItem) {
        self.old = old
        self.fresh = fresh
    }

    func fetchPage(category: AiyifanCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        callCount += 1
        if callCount == 1 {
            try await Task.sleep(for: .milliseconds(100))
            return CategoryCatalogPage(items: [old], page: 1, isLastPage: true)
        }
        return CategoryCatalogPage(items: [fresh], page: 1, isLastPage: true)
    }
}
