import Foundation

@MainActor
final class CategoryCatalogViewModel: ObservableObject {
    let category: AiyifanCategory
    let pageSize: Int

    @Published private(set) var items: [AiyifanItem] = []
    @Published private(set) var nextPage = 1
    @Published private(set) var reachedEnd = false
    @Published private(set) var isLoadingInitial = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var initialErrorMessage: String?
    @Published private(set) var loadMoreErrorMessage: String?
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var appliedQuery: CatalogQuery
    @Published private(set) var draftQuery: CatalogQuery
    @Published private(set) var filterSet: CatalogFilterSet?
    @Published private(set) var isLoadingFilters = false
    @Published private(set) var filterErrorMessage: String?
    @Published private(set) var isApplyingQuery = false
    @Published private(set) var queryErrorMessage: String?
    @Published private(set) var totalCount = 0

    private let service: any CategoryCatalogServing
    private var generation = 0

    init(
        category: AiyifanCategory,
        pageSize: Int = 24,
        service: any CategoryCatalogServing = CategoryCatalogService()
    ) {
        self.category = category
        self.pageSize = pageSize
        self.service = service
        let initialQuery = CatalogQuery(category: category)
        appliedQuery = initialQuery
        draftQuery = initialQuery
    }

    func loadInitial() async {
        guard items.isEmpty, !isLoadingInitial, !isRefreshing, !isApplyingQuery else {
            return
        }
        let requestGeneration = generation
        isLoadingInitial = true
        initialErrorMessage = nil

        do {
            let page = try await service.fetchPage(query: appliedQuery, page: 1, pageSize: pageSize)
            guard generation == requestGeneration else { return }
            applyInitial(page)
        } catch {
            guard generation == requestGeneration else { return }
            initialErrorMessage = error.localizedDescription
        }
        if generation == requestGeneration {
            isLoadingInitial = false
        }
    }

    func loadFilters() async {
        guard filterSet == nil, !isLoadingFilters else { return }
        isLoadingFilters = true
        filterErrorMessage = nil
        do {
            filterSet = try await service.fetchFilters(category: category)
        } catch {
            filterErrorMessage = error.localizedDescription
        }
        isLoadingFilters = false
    }

    func beginFilterEditing() {
        draftQuery = appliedQuery
        queryErrorMessage = nil
    }

    func cancelFilterEditing() {
        draftQuery = appliedQuery
    }

    func resetDraftFilters() {
        draftQuery = CatalogQuery(
            category: category,
            sort: appliedQuery.sort,
            descending: appliedQuery.descending
        )
    }

    func setDraftGenre(_ value: String?) { draftQuery = draftQuery.replacing(genreCID: value) }
    func setDraftRegion(_ value: String?) { draftQuery = draftQuery.replacing(region: value) }
    func setDraftLanguage(_ value: String?) { draftQuery = draftQuery.replacing(language: value) }
    func setDraftYear(_ value: String?) { draftQuery = draftQuery.replacing(year: value) }
    func setDraftQuality(_ value: String?) { draftQuery = draftQuery.replacing(quality: value) }
    func setDraftStatus(_ value: CatalogSerialStatus?) { draftQuery = draftQuery.replacing(status: value) }

    func applyDraftQuery() async -> Bool {
        await applyQuery(draftQuery)
    }

    func applySort(_ sort: CatalogSort, descending: Bool) async -> Bool {
        await applyQuery(appliedQuery.replacing(sort: sort, descending: descending))
    }

    func clearFilters() async -> Bool {
        let query = CatalogQuery(
            category: category,
            sort: appliedQuery.sort,
            descending: appliedQuery.descending
        )
        draftQuery = query
        return await applyQuery(query)
    }

    func loadMoreIfNeeded(currentItem: AiyifanItem) async {
        guard
            !reachedEnd,
            !isLoadingInitial,
            !isLoadingMore,
            !isApplyingQuery,
            loadMoreErrorMessage == nil,
            let index = items.firstIndex(where: { $0.id == currentItem.id }),
            index >= max(0, items.count - 4)
        else {
            return
        }
        await loadNextPage()
    }

    func retryLoadMore() async {
        loadMoreErrorMessage = nil
        await loadNextPage()
    }

    func refresh() async {
        generation += 1
        let requestGeneration = generation
        isLoadingInitial = false
        isLoadingMore = false
        isApplyingQuery = false
        isRefreshing = true
        initialErrorMessage = nil
        loadMoreErrorMessage = nil
        refreshErrorMessage = nil

        do {
            let page = try await service.fetchPage(query: appliedQuery, page: 1, pageSize: pageSize)
            guard generation == requestGeneration else { return }
            applyInitial(page)
        } catch {
            guard generation == requestGeneration else { return }
            if items.isEmpty {
                initialErrorMessage = error.localizedDescription
            } else {
                refreshErrorMessage = error.localizedDescription
            }
        }
        if generation == requestGeneration {
            isRefreshing = false
        }
    }

    private func applyQuery(_ query: CatalogQuery) async -> Bool {
        guard query != appliedQuery else {
            draftQuery = appliedQuery
            return true
        }
        generation += 1
        let requestGeneration = generation
        isLoadingInitial = false
        isRefreshing = false
        isApplyingQuery = true
        isLoadingMore = false
        queryErrorMessage = nil
        loadMoreErrorMessage = nil

        do {
            let page = try await service.fetchPage(query: query, page: 1, pageSize: pageSize)
            guard generation == requestGeneration else { return false }
            appliedQuery = query
            draftQuery = query
            applyInitial(page)
            isApplyingQuery = false
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            queryErrorMessage = error.localizedDescription
            isApplyingQuery = false
            return false
        }
    }

    private func loadNextPage() async {
        guard !reachedEnd, !isLoadingMore, !isApplyingQuery, !items.isEmpty else {
            return
        }
        let pageNumber = nextPage
        let requestGeneration = generation
        isLoadingMore = true

        do {
            let page = try await service.fetchPage(query: appliedQuery, page: pageNumber, pageSize: pageSize)
            guard generation == requestGeneration else { return }
            guard page.page == pageNumber else {
                throw CategoryCatalogError.invalidResponse
            }
            let existingIDs = Set(items.map(\.id))
            let uniqueItems = page.items.filter { !existingIDs.contains($0.id) }
            items = items + uniqueItems
            nextPage = pageNumber + 1
            reachedEnd = page.isLastPage
            loadMoreErrorMessage = nil
        } catch {
            guard generation == requestGeneration else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
        if generation == requestGeneration {
            isLoadingMore = false
        }
    }

    private func applyInitial(_ page: CategoryCatalogPage) {
        guard page.page == 1 else {
            initialErrorMessage = CategoryCatalogError.invalidResponse.localizedDescription
            return
        }
        var knownIDs = Set<String>()
        items = page.items.filter { knownIDs.insert($0.id).inserted }
        nextPage = 2
        reachedEnd = page.isLastPage
        totalCount = page.totalCount
        initialErrorMessage = nil
        loadMoreErrorMessage = nil
        refreshErrorMessage = nil
    }
}
