import Foundation
import XCTest
@testable import MyVideo

final class CategoryCatalogContractTests: XCTestCase {
    func testProviderCertificateCacheCoalescesConcurrentLoads() async throws {
        let cache = ProviderCertificateCache(lifetime: 60)
        let counter = CertificateLoadCounter()
        let load: @Sendable () async throws -> PlaybackCertificate = {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(30))
            return PlaybackCertificate(publicKey: "public", privateKey: "private")
        }

        async let first = cache.certificate(for: "yfsp.tv", load: load)
        async let second = cache.certificate(for: "yfsp.tv", load: load)
        async let third = cache.certificate(for: "yfsp.tv", load: load)
        let certificates = try await [first, second, third]
        let loadCount = await counter.value()

        XCTAssertEqual(Set(certificates.map(\.publicKey)), ["public"])
        XCTAssertEqual(loadCount, 1)
    }

    func testCategoriesUseProviderCatalogIdentifiers() {
        XCTAssertEqual(MyVideoCategory.movie.catalogCID, "0,1,3")
        XCTAssertEqual(MyVideoCategory.drama.catalogCID, "0,1,4")
        XCTAssertEqual(MyVideoCategory.variety.catalogCID, "0,1,5")
        XCTAssertEqual(MyVideoCategory.anime.catalogCID, "0,1,6")
        XCTAssertEqual(MyVideoCategory.allCases.map(\.id), ["movie", "drama", "variety", "anime"])
        XCTAssertEqual(MyVideoCategory.allCases.map(\.title), ["Movies", "Series", "Variety", "Anime"])
    }

    func testRequestBuilderSignsCatalogRequestDeterministically() throws {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")
        let query = CatalogQuery(
            category: .drama,
            genreCID: "0,1,4,137",
            region: "欧美",
            language: "英语",
            year: "今年",
            quality: "1080P",
            status: .ongoing,
            sort: .rating,
            descending: true
        )

        let url = try CategoryCatalogRequestBuilder.makeURL(
            query: query,
            page: 2,
            pageSize: 24,
            siteHost: "www.yfsp.tv",
            certificate: certificate
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "m10.yfsp.tv")
        XCTAssertEqual(components.path, "/api/list/Search")
        XCTAssertEqual(values["cinema"], "1")
        XCTAssertEqual(values["page"], "2")
        XCTAssertEqual(values["cid"], "0,1,4,137")
        XCTAssertEqual(values["size"], "24")
        XCTAssertEqual(values["orderby"], "3")
        XCTAssertEqual(values["desc"], "1")
        XCTAssertEqual(values["region"], "欧美")
        XCTAssertEqual(values["language"], "英语")
        XCTAssertEqual(values["year"], "今年")
        XCTAssertEqual(values["vipResource"], "1080P")
        XCTAssertEqual(values["isserial"], "1")
        XCTAssertEqual(values["isIndex"], "-1")
        XCTAssertEqual(values["isfree"], "-1")
        XCTAssertEqual(values["isVertical"], "-1")
        XCTAssertEqual(values["pub"], "public-test")
        XCTAssertEqual(values["vv"], "76d74b6a4dc42c4fceac4e5df13cd0d0")
    }

    func testCatalogQueryDefaultsToLatestUpdatesAndCountsActiveFilters() {
        let query = CatalogQuery(category: .anime)

        XCTAssertEqual(query.sort, .updated)
        XCTAssertTrue(query.descending)
        XCTAssertEqual(query.activeFilterCount, 0)

        let filtered = query
            .replacing(genreCID: "0,1,6,46")
            .replacing(language: "国语")
            .replacing(status: .complete)

        XCTAssertEqual(filtered.activeFilterCount, 3)
        XCTAssertEqual(query.activeFilterCount, 0)
    }

    func testCatalogSortUsesProviderIdentifiers() {
        XCTAssertEqual(CatalogSort.added.rawValue, 0)
        XCTAssertEqual(CatalogSort.updated.rawValue, 1)
        XCTAssertEqual(CatalogSort.popularity.rawValue, 2)
        XCTAssertEqual(CatalogSort.rating.rawValue, 3)
    }

    func testCategoriesMapToProviderGenreEndpoints() {
        XCTAssertEqual(MyVideoCategory.movie.genreEndpointPath, "/api/list/FilmType")
        XCTAssertEqual(MyVideoCategory.drama.genreEndpointPath, "/api/list/TvType")
        XCTAssertEqual(MyVideoCategory.variety.genreEndpointPath, "/api/list/VarietyType")
        XCTAssertEqual(MyVideoCategory.anime.genreEndpointPath, "/api/list/AnimeType")
    }

    func testFilterDecoderCombinesConditionsAndCategoryGenres() throws {
        let conditions = searchConditionsResponse()
        let genres = Data(#"{"ret":200,"data":{"code":0,"info":[{"pid":"0,1,4","className":"悬疑","path":"0,1,4,137"},{"pid":"0,1,4","className":"喜剧","path":"0,1,4,133"}]}}"#.utf8)

        let filters = try CatalogFilterResponseDecoder.decode(
            conditionData: conditions,
            genreData: genres,
            category: .drama
        )

        XCTAssertEqual(filters.genres.map(\.title), ["悬疑", "喜剧"])
        XCTAssertEqual(filters.genres.map(\.value), ["0,1,4,137", "0,1,4,133"])
        XCTAssertEqual(filters.regions.map(\.value), ["大陆", "欧美"])
        XCTAssertEqual(filters.languages.map(\.value), ["国语", "英语"])
        XCTAssertEqual(filters.years.map(\.value), ["今年", "去年"])
        XCTAssertEqual(filters.qualities.map(\.value), ["4K", "1080P"])
        XCTAssertEqual(filters.statuses.map(\.value), ["0", "1"])
    }

    func testMovieFiltersOmitSerialStatus() throws {
        let genres = Data(#"{"ret":200,"data":{"code":0,"info":[{"pid":"0,1,3","className":"剧情","path":"0,1,3,28"}]}}"#.utf8)

        let filters = try CatalogFilterResponseDecoder.decode(
            conditionData: searchConditionsResponse(),
            genreData: genres,
            category: .movie
        )

        XCTAssertTrue(filters.statuses.isEmpty)
    }

    func testFilterDecoderRejectsMissingConditionGroupAndWrongGenrePath() {
        let missingLanguage = Data(#"{"ret":200,"data":{"code":0,"info":[{"conditions":{"region":[],"year":[],"vipResource":[],"isSerial":[]}}]}}"#.utf8)
        let wrongGenres = Data(#"{"ret":200,"data":{"code":0,"info":[{"pid":"0,1,3","className":"剧情","path":"0,1,3,28"}]}}"#.utf8)

        XCTAssertThrowsError(try CatalogFilterResponseDecoder.decode(
            conditionData: missingLanguage,
            genreData: wrongGenres,
            category: .drama
        ))
        XCTAssertThrowsError(try CatalogFilterResponseDecoder.decode(
            conditionData: searchConditionsResponse(),
            genreData: wrongGenres,
            category: .drama
        ))
    }

    func testMovieQueryRejectsSerialStatusAndUnsafeFilterValues() {
        XCTAssertThrowsError(try CatalogQuery(
            validating: .movie,
            status: .ongoing
        ))
        XCTAssertThrowsError(try CatalogQuery(
            validating: .drama,
            language: "English\nInjected"
        ))
    }

    func testRequestBuilderRejectsInvalidPageAndUnsupportedHost() {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        XCTAssertThrowsError(try CategoryCatalogRequestBuilder.makeURL(
            query: CatalogQuery(category: .movie),
            page: 0,
            pageSize: 24,
            siteHost: "www.yfsp.tv",
            certificate: certificate
        ))
        XCTAssertThrowsError(try CategoryCatalogRequestBuilder.makeURL(
            query: CatalogQuery(category: .movie),
            page: 1,
            pageSize: 24,
            siteHost: "attacker.example",
            certificate: certificate
        )) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedSite)
        }
    }

    func testDecoderMapsCatalogMetadataAndNormalizesArtwork() throws {
        let data = catalogSearchResponse(count: 48, maxPage: 2, items: [[
            "key": "drama-42",
            "title": "The Test Series",
            "image": "//static.yfsp.tv/drama-42.jpg",
            "lastName": "更新至 12 集",
            "lastKey": "episode-12",
            "isSerial": true,
            "videoClassID": "0,1,4,137",
            "cid": "悬疑",
            "lang": "英语",
            "vipResource": "1080P",
            "hot": 123456,
            "rating": "9.1",
            "score": "9.6",
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
        XCTAssertEqual(item.isSerial, true)
        XCTAssertEqual(item.latestEpisodeKey, "episode-12")
        XCTAssertEqual(item.latestEpisodeTitle, "更新至 12 集")
        XCTAssertEqual(item.categoryPath, "0,1,4,137")
        XCTAssertEqual(item.genre, "悬疑")
        XCTAssertEqual(item.language, "英语")
        XCTAssertEqual(item.quality, "1080P")
        XCTAssertEqual(item.popularity, 123456)
        XCTAssertEqual(item.rating, "9.1")
        XCTAssertEqual(item.score, 9.6)
        XCTAssertEqual(item.thumbnailURL?.absoluteString, "https://static.yfsp.tv/drama-42.jpg")
        XCTAssertEqual(item.playURL.absoluteString, "https://m.yfsp.tv/play/drama-42")
        XCTAssertEqual(page.totalCount, 48)
        XCTAssertFalse(page.isLastPage)
    }

    func testDecoderRejectsInvalidEnvelopeMalformedItemsAndInsecureArtwork() {
        let invalidEnvelope = Data(#"{"ret":500,"data":{"code":0,"info":[]}}"#.utf8)
        let malformed = catalogSearchResponse(items: [["key": "", "title": "Missing key"]])
        let insecureArtwork = catalogSearchResponse(items: [[
            "key": "movie-1", "title": "Movie", "image": "http://static.yfsp.tv/poster.jpg"
        ]])
        let privateArtwork = catalogSearchResponse(items: [[
            "key": "movie-2", "title": "Private", "image": "https://192.168.1.20/poster.jpg"
        ]])
        let localArtwork = catalogSearchResponse(items: [[
            "key": "movie-3", "title": "Local", "image": "https://localhost/poster.jpg"
        ]])
        let unsupportedArtwork = catalogSearchResponse(items: [[
            "key": "movie-4", "title": "Unsupported", "image": "https://attacker.invalid/poster.jpg"
        ]])

        for data in [invalidEnvelope, malformed, insecureArtwork, privateArtwork, localArtwork, unsupportedArtwork] {
            XCTAssertThrowsError(try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24))
        }
    }

    func testDecoderRejectsMoreItemsThanRequestedPageSize() {
        let items = (1...25).map { index in
            ["key": "movie-\(index)", "title": "Movie \(index)"]
        }
        let data = catalogSearchResponse(count: 25, items: items)

        XCTAssertThrowsError(try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24))
    }

    func testDecoderRejectsOversizedResponse() {
        let data = Data(repeating: 0x20, count: 2_000_001)

        XCTAssertThrowsError(try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24))
    }

    func testDecoderOmitsInvalidOptionalScoresWithoutDroppingTitles() throws {
        for invalidScore in ["-0.1", "10.1", "not-a-score", "infinity"] {
            let data = catalogSearchResponse(items: [[
                "key": "movie-score",
                "title": "Original Provider Title",
                "score": invalidScore
            ]])

            let page = try CategoryCatalogResponseDecoder.decode(data, page: 1, pageSize: 24)

            XCTAssertEqual(page.items.first?.title, "Original Provider Title")
            XCTAssertNil(page.items.first?.score)
        }

        let booleanScore = catalogSearchResponse(items: [[
            "key": "movie-boolean-score",
            "title": "Original Provider Title",
            "score": true
        ]])
        XCTAssertNil(
            try CategoryCatalogResponseDecoder.decode(booleanScore, page: 1, pageSize: 24).items.first?.score
        )
    }

    private func catalogSearchResponse(
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

    private func searchConditionsResponse() -> Data {
        Data(#"{"ret":200,"data":{"code":0,"info":[{"conditions":{"region":[{"title":"全部","link":"-1"},{"title":"大陆","link":"大陆"},{"title":"欧美","link":"欧美"}],"language":[{"title":"国语","link":"国语"},{"title":"英语","link":"英语"}],"year":[{"title":"今年","link":"今年"},{"title":"去年","link":"去年"}],"vipResource":[{"title":"4K","link":"4K"},{"title":"1080P","link":"1080P"}],"isSerial":[{"title":"全部","link":"-1"},{"title":"全集","link":"0"},{"title":"连载中","link":"1"}]}}]}}"#.utf8)
    }
}

private actor CertificateLoadCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

@MainActor
final class CatalogPreferenceStoreTests: XCTestCase {
    func testQueriesPersistIndependentlyByStableCategoryRawValue() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let movie = CatalogQuery(category: .movie, language: "English", sort: .rating, descending: false)
        let series = CatalogQuery(
            category: .drama,
            region: "US",
            status: .ongoing,
            sort: .popularity,
            descending: true
        )

        store.save(movie)
        store.save(series)

        XCTAssertEqual(store.query(for: .movie), movie)
        XCTAssertEqual(store.query(for: .drama), series)
        XCTAssertNil(store.query(for: .anime))
    }

    func testClearFiltersRetainsSortAndDirection() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.save(CatalogQuery(
            category: .drama,
            language: "English",
            status: .complete,
            sort: .rating,
            descending: false
        ))

        store.clearFilters(for: .drama)

        XCTAssertEqual(
            store.query(for: .drama),
            CatalogQuery(category: .drama, sort: .rating, descending: false)
        )
    }

    func testCorruptOrInvalidStoredQueryIsIgnored() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "catalog-preferences")

        XCTAssertNil(store.query(for: .movie))

        store.save(CatalogQuery(category: .movie, status: .ongoing))

        XCTAssertNil(store.query(for: .movie))
    }

    private func makeStore() -> (CatalogPreferenceStore, UserDefaults, String) {
        let suite = "CatalogPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (
            CatalogPreferenceStore(defaults: defaults, storageKey: "catalog-preferences"),
            defaults,
            suite
        )
    }
}

@MainActor
final class CategoryCatalogViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "myvideoCatalogPreferencesV1")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "myvideoCatalogPreferencesV1")
        super.tearDown()
    }

    func testRestoresPersistedQueryBeforeInitialRequest() async {
        let (store, defaults, suite) = preferenceStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let savedQuery = CatalogQuery(
            category: .drama,
            language: "English",
            sort: .rating,
            descending: false
        )
        store.save(savedQuery)
        let service = QueryRecordingCatalogService()

        let viewModel = CategoryCatalogViewModel(
            category: .drama,
            service: service,
            preferenceStore: store
        )
        await viewModel.loadInitial()

        let requestedQuery = await service.lastQuery()
        XCTAssertEqual(viewModel.appliedQuery, savedQuery)
        XCTAssertEqual(requestedQuery, savedQuery)
    }

    func testOnlySuccessfulFilterAndSortChangesArePersisted() async {
        let (store, defaults, suite) = preferenceStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = MyVideoItem(listPath: "original", title: "Original")
        let filtered = MyVideoItem(listPath: "filtered", title: "Filtered")
        let sorted = MyVideoItem(listPath: "sorted", title: "Sorted")
        let service = TransactionalCategoryCatalogService(original: original, filtered: filtered, sorted: sorted)
        let viewModel = CategoryCatalogViewModel(
            category: .drama,
            service: service,
            preferenceStore: store
        )
        await viewModel.loadInitial()
        viewModel.beginFilterEditing()
        viewModel.setDraftLanguage("英语")

        let failedApply = await viewModel.applyDraftQuery()
        XCTAssertFalse(failedApply)
        XCTAssertNil(store.query(for: .drama))

        let successfulApply = await viewModel.applyDraftQuery()
        XCTAssertTrue(successfulApply)
        XCTAssertEqual(store.query(for: .drama)?.language, "英语")

        let successfulSort = await viewModel.applySort(.rating, descending: false)
        XCTAssertTrue(successfulSort)
        XCTAssertEqual(store.query(for: .drama)?.sort, CatalogSort.rating)
        XCTAssertEqual(store.query(for: .drama)?.descending, false)
    }

    func testStaleRestoredFilterIsRemovedButSortIsRetained() async {
        let (store, defaults, suite) = preferenceStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.save(CatalogQuery(
            category: .drama,
            language: "Removed Provider Option",
            sort: .popularity,
            descending: false
        ))
        let service = StaleOptionCatalogService()
        let viewModel = CategoryCatalogViewModel(
            category: .drama,
            service: service,
            preferenceStore: store
        )

        await viewModel.loadInitial()
        await viewModel.loadFilters()

        let requestedQuery = await service.lastQuery()
        XCTAssertNil(viewModel.appliedQuery.language)
        XCTAssertEqual(viewModel.appliedQuery.sort, CatalogSort.popularity)
        XCTAssertFalse(viewModel.appliedQuery.descending)
        XCTAssertNil(store.query(for: .drama)?.language)
        XCTAssertNil(requestedQuery?.language)
    }

    func testFilterDraftCancelAndApplyAreTransactional() async {
        let original = MyVideoItem(listPath: "original", title: "Original")
        let filtered = MyVideoItem(listPath: "filtered", title: "Filtered")
        let service = TransactionalCategoryCatalogService(original: original, filtered: filtered)
        let viewModel = CategoryCatalogViewModel(category: .drama, pageSize: 24, service: service)

        await viewModel.loadInitial()
        await viewModel.loadFilters()
        XCTAssertEqual(viewModel.filterSet?.languages.map(\.value), ["国语", "英语"])

        viewModel.beginFilterEditing()
        viewModel.setDraftLanguage("英语")
        viewModel.cancelFilterEditing()
        XCTAssertNil(viewModel.draftQuery.language)
        XCTAssertEqual(viewModel.items, [original])

        viewModel.beginFilterEditing()
        viewModel.setDraftLanguage("英语")
        let firstApplySucceeded = await viewModel.applyDraftQuery()
        XCTAssertFalse(firstApplySucceeded)
        XCTAssertNil(viewModel.appliedQuery.language)
        XCTAssertEqual(viewModel.items, [original])
        XCTAssertNotNil(viewModel.queryErrorMessage)

        let retrySucceeded = await viewModel.applyDraftQuery()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(viewModel.appliedQuery.language, "英语")
        XCTAssertEqual(viewModel.items, [filtered])
        XCTAssertEqual(viewModel.totalCount, 1)
        XCTAssertNil(viewModel.queryErrorMessage)
    }

    func testSortAppliesImmediatelyAndResetsPagination() async {
        let original = MyVideoItem(listPath: "original", title: "Original")
        let sorted = MyVideoItem(listPath: "sorted", title: "Sorted")
        let service = TransactionalCategoryCatalogService(original: original, sorted: sorted)
        let viewModel = CategoryCatalogViewModel(category: .anime, pageSize: 24, service: service)

        await viewModel.loadInitial()
        let sortSucceeded = await viewModel.applySort(.rating, descending: false)
        XCTAssertTrue(sortSucceeded)

        XCTAssertEqual(viewModel.appliedQuery.sort, .rating)
        XCTAssertFalse(viewModel.appliedQuery.descending)
        XCTAssertEqual(viewModel.items, [sorted])
        XCTAssertEqual(viewModel.nextPage, 2)
    }

    func testInitialLoadAndPaginationDeduplicateItems() async {
        let first = MyVideoItem(listPath: "one", title: "One")
        let duplicate = MyVideoItem(listPath: "two", title: "Two")
        let third = MyVideoItem(listPath: "three", title: "Three")
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
        let first = MyVideoItem(listPath: "one", title: "One")
        let second = MyVideoItem(listPath: "two", title: "Two")
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
        let old = MyVideoItem(listPath: "old", title: "Old")
        let fresh = MyVideoItem(listPath: "fresh", title: "Fresh")
        let service = SequencedCategoryCatalogService(old: old, fresh: fresh)
        let viewModel = CategoryCatalogViewModel(category: .drama, pageSize: 24, service: service)

        let initialTask = Task { await viewModel.loadInitial() }
        try await Task.sleep(for: .milliseconds(20))
        await viewModel.refresh()
        await initialTask.value

        XCTAssertEqual(viewModel.items, [fresh])
        XCTAssertEqual(viewModel.nextPage, 2)
    }

    func testApplyingQueryCancelsOldPaginationWithoutMixingResults() async throws {
        let service = RacingPaginationCatalogService()
        let viewModel = CategoryCatalogViewModel(category: .drama, pageSize: 1, service: service)
        await viewModel.loadInitial()
        let original = try XCTUnwrap(viewModel.items.first)

        let pagination = Task { await viewModel.loadMoreIfNeeded(currentItem: original) }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(viewModel.isLoadingMore)

        viewModel.beginFilterEditing()
        viewModel.setDraftLanguage("英语")
        let didApplyQuery = await viewModel.applyDraftQuery()
        XCTAssertTrue(didApplyQuery)
        await pagination.value

        XCTAssertEqual(viewModel.items.map(\.id), ["filtered"])
        XCTAssertEqual(viewModel.appliedQuery.language, "英语")
        XCTAssertFalse(viewModel.isLoadingMore)
        XCTAssertNil(viewModel.loadMoreErrorMessage)
    }

    func testRefreshCancelsPendingQueryWithoutStrandingLoadingState() async throws {
        let service = RefreshWinsCatalogService()
        let viewModel = CategoryCatalogViewModel(category: .drama, pageSize: 1, service: service)
        await viewModel.loadInitial()

        viewModel.beginFilterEditing()
        viewModel.setDraftLanguage("英语")
        let queryTask = Task { await viewModel.applyDraftQuery() }
        try await Task.sleep(for: .milliseconds(20))
        await viewModel.refresh()
        _ = await queryTask.value

        XCTAssertEqual(viewModel.items.map(\.id), ["refreshed"])
        XCTAssertNil(viewModel.appliedQuery.language)
        XCTAssertFalse(viewModel.isApplyingQuery)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testApplyingQueryCancelsPendingInitialLoadWithoutStrandingLoadingState() async throws {
        let service = QueryWinsCatalogService()
        let viewModel = CategoryCatalogViewModel(category: .drama, pageSize: 1, service: service)
        let initialTask = Task { await viewModel.loadInitial() }
        try await Task.sleep(for: .milliseconds(20))

        viewModel.beginFilterEditing()
        viewModel.setDraftLanguage("英语")
        let didApplyQuery = await viewModel.applyDraftQuery()
        XCTAssertTrue(didApplyQuery)
        await initialTask.value

        XCTAssertEqual(viewModel.items.map(\.id), ["filtered"])
        XCTAssertFalse(viewModel.isLoadingInitial)
        XCTAssertFalse(viewModel.isApplyingQuery)
    }

    private func preferenceStore() -> (CatalogPreferenceStore, UserDefaults, String) {
        let suite = "CategoryCatalogViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (
            CatalogPreferenceStore(defaults: defaults, storageKey: "catalog-preferences"),
            defaults,
            suite
        )
    }

}

private actor QueryRecordingCatalogService: CategoryCatalogServing {
    private var queries: [CatalogQuery] = []

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        queries.append(query)
        return CategoryCatalogPage(
            items: [MyVideoItem(listPath: "result", title: "Result")],
            page: page,
            isLastPage: true
        )
    }

    func lastQuery() -> CatalogQuery? {
        queries.last
    }
}

private actor StaleOptionCatalogService: CategoryCatalogServing {
    private var queries: [CatalogQuery] = []

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        queries.append(query)
        return CategoryCatalogPage(
            items: [MyVideoItem(listPath: query.language ?? "default", title: "Result")],
            page: page,
            isLastPage: true
        )
    }

    func fetchFilters(category: MyVideoCategory) async throws -> CatalogFilterSet {
        CatalogFilterSet(
            genres: [],
            regions: [],
            languages: [try! CatalogFilterOption(title: "Provider Original", value: "Provider Original")],
            years: [],
            qualities: [],
            statuses: []
        )
    }

    func lastQuery() -> CatalogQuery? {
        queries.last
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

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
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
    private let old: MyVideoItem
    private let fresh: MyVideoItem
    private var callCount = 0

    init(old: MyVideoItem, fresh: MyVideoItem) {
        self.old = old
        self.fresh = fresh
    }

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        callCount += 1
        if callCount == 1 {
            try await Task.sleep(for: .milliseconds(100))
            return CategoryCatalogPage(items: [old], page: 1, isLastPage: true)
        }
        return CategoryCatalogPage(items: [fresh], page: 1, isLastPage: true)
    }
}

private actor TransactionalCategoryCatalogService: CategoryCatalogServing {
    private let original: MyVideoItem
    private let filtered: MyVideoItem?
    private let sorted: MyVideoItem?
    private var filteredAttempts = 0

    init(original: MyVideoItem, filtered: MyVideoItem? = nil, sorted: MyVideoItem? = nil) {
        self.original = original
        self.filtered = filtered
        self.sorted = sorted
    }

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        CategoryCatalogPage(items: [original], page: page, isLastPage: true, totalCount: 1)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        if query.language == "英语", let filtered {
            filteredAttempts += 1
            if filteredAttempts == 1 { throw URLError(.timedOut) }
            return CategoryCatalogPage(items: [filtered], page: page, isLastPage: true, totalCount: 1)
        }
        if query.sort == .rating, let sorted {
            return CategoryCatalogPage(items: [sorted], page: page, isLastPage: true, totalCount: 1)
        }
        return CategoryCatalogPage(items: [original], page: page, isLastPage: true, totalCount: 1)
    }

    func fetchFilters(category: MyVideoCategory) async throws -> CatalogFilterSet {
        CatalogFilterSet(
            genres: [],
            regions: [],
            languages: [
                try! CatalogFilterOption(title: "国语", value: "国语"),
                try! CatalogFilterOption(title: "英语", value: "英语")
            ],
            years: [],
            qualities: [],
            statuses: []
        )
    }
}

private actor RacingPaginationCatalogService: CategoryCatalogServing {
    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        if query.language == "英语" {
            return CategoryCatalogPage(
                items: [MyVideoItem(listPath: "filtered", title: "Filtered")],
                page: 1,
                isLastPage: true,
                totalCount: 1
            )
        }
        if page == 2 {
            try await Task.sleep(for: .milliseconds(100))
            return CategoryCatalogPage(
                items: [MyVideoItem(listPath: "stale", title: "Stale")],
                page: 2,
                isLastPage: true,
                totalCount: 2
            )
        }
        return CategoryCatalogPage(
            items: [MyVideoItem(listPath: "original", title: "Original")],
            page: 1,
            isLastPage: false,
            totalCount: 2
        )
    }
}

private actor RefreshWinsCatalogService: CategoryCatalogServing {
    private var unfilteredCallCount = 0

    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        if query.language == "英语" {
            try await Task.sleep(for: .milliseconds(100))
            return CategoryCatalogPage(items: [MyVideoItem(listPath: "stale", title: "Stale")], page: 1, isLastPage: true)
        }
        unfilteredCallCount += 1
        let id = unfilteredCallCount == 1 ? "original" : "refreshed"
        return CategoryCatalogPage(items: [MyVideoItem(listPath: id, title: id)], page: 1, isLastPage: true)
    }
}

private actor QueryWinsCatalogService: CategoryCatalogServing {
    func fetchPage(category: MyVideoCategory, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        try await fetchPage(query: CatalogQuery(category: category), page: page, pageSize: pageSize)
    }

    func fetchPage(query: CatalogQuery, page: Int, pageSize: Int) async throws -> CategoryCatalogPage {
        if query.language == "英语" {
            return CategoryCatalogPage(items: [MyVideoItem(listPath: "filtered", title: "Filtered")], page: 1, isLastPage: true)
        }
        try await Task.sleep(for: .milliseconds(100))
        return CategoryCatalogPage(items: [MyVideoItem(listPath: "stale", title: "Stale")], page: 1, isLastPage: true)
    }
}
