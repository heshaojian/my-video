import Foundation

@MainActor
final class ProviderSearchViewModel: ObservableObject {
    let pageSize: Int

    @Published private(set) var isExpanded = false
    @Published var query = ""
    @Published private(set) var submittedQuery: String?
    @Published private(set) var items: [AiyifanItem] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var nextPage = 1
    @Published private(set) var reachedEnd = false
    @Published private(set) var isLoadingInitial = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var validationMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadMoreErrorMessage: String?

    var isLoading: Bool {
        isLoadingInitial || isLoadingMore
    }

    var showsEmptyResults: Bool {
        submittedQuery != nil && !isLoading && errorMessage == nil && items.isEmpty && reachedEnd
    }

    var canContinueFilteredSearch: Bool {
        submittedQuery != nil
            && !isLoading
            && errorMessage == nil
            && loadMoreErrorMessage == nil
            && items.isEmpty
            && !reachedEnd
    }

    private let service: any ProviderSearchServing
    private let filteredPageLimit = 3
    private var generation = 0
    private var requestTask: Task<ProviderSearchPage, Error>?

    init(
        pageSize: Int = 24,
        service: any ProviderSearchServing = ProviderSearchService()
    ) {
        self.pageSize = pageSize
        self.service = service
    }

    func expand() {
        isExpanded = true
        validationMessage = nil
    }

    func cancel() {
        generation += 1
        requestTask?.cancel()
        requestTask = nil
        isExpanded = false
        query = ""
        submittedQuery = nil
        items = []
        totalCount = 0
        nextPage = 1
        reachedEnd = false
        isLoadingInitial = false
        isLoadingMore = false
        validationMessage = nil
        errorMessage = nil
        loadMoreErrorMessage = nil
    }

    @discardableResult
    func submit() async -> Bool {
        let validatedQuery: ProviderSearchQuery
        do {
            validatedQuery = try ProviderSearchQuery(validating: query)
        } catch {
            validationMessage = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter a title to search."
                : error.localizedDescription
            return false
        }

        query = validatedQuery.tags
        submittedQuery = validatedQuery.tags
        generation += 1
        requestTask?.cancel()
        requestTask = nil
        items = []
        totalCount = 0
        nextPage = 1
        reachedEnd = false
        isLoadingInitial = false
        isLoadingMore = false
        validationMessage = nil
        errorMessage = nil
        loadMoreErrorMessage = nil
        return await loadInitial(query: validatedQuery, generation: generation)
    }

    @discardableResult
    func retry() async -> Bool {
        guard let submittedQuery else { return false }
        guard let validatedQuery = try? ProviderSearchQuery(validating: submittedQuery) else {
            validationMessage = ProviderSearchError.invalidQuery.localizedDescription
            return false
        }

        generation += 1
        requestTask?.cancel()
        requestTask = nil
        isLoadingInitial = false
        isLoadingMore = false
        errorMessage = nil
        loadMoreErrorMessage = nil
        return await loadInitial(query: validatedQuery, generation: generation)
    }

    func loadMoreIfNeeded(currentItem: AiyifanItem) async {
        guard
            !reachedEnd,
            !isLoadingInitial,
            !isLoadingMore,
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

    private func loadInitial(query: ProviderSearchQuery, generation requestGeneration: Int) async -> Bool {
        isLoadingInitial = true

        do {
            var pageNumber = 1
            var appendedResults = false
            var fetchedPages = 0
            repeat {
                let requestedPage = pageNumber
                let task = Task {
                    try await service.search(query: query, page: requestedPage, pageSize: pageSize)
                }
                requestTask = task
                let page = try await task.value
                fetchedPages += 1
                guard generation == requestGeneration else { return false }
                guard page.page == requestedPage else { throw ProviderSearchError.invalidResponse }
                if requestedPage == 1 {
                    applyInitial(page)
                    appendedResults = !items.isEmpty
                } else {
                    appendedResults = append(page)
                }
                pageNumber = nextPage
            } while !appendedResults && !reachedEnd && fetchedPages < filteredPageLimit
            isLoadingInitial = false
            requestTask = nil
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            isLoadingInitial = false
            requestTask = nil
            if !Self.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func loadNextPage() async {
        guard
            let submittedQuery,
            let validatedQuery = try? ProviderSearchQuery(validating: submittedQuery),
            !reachedEnd,
            !isLoadingInitial,
            !isLoadingMore
        else {
            return
        }

        let requestGeneration = generation
        isLoadingMore = true

        do {
            var appendedResults = false
            var fetchedPages = 0
            repeat {
                let pageNumber = nextPage
                let task = Task {
                    try await service.search(query: validatedQuery, page: pageNumber, pageSize: pageSize)
                }
                requestTask = task
                let page = try await task.value
                fetchedPages += 1
                guard generation == requestGeneration else { return }
                guard page.page == pageNumber else { throw ProviderSearchError.invalidResponse }
                appendedResults = append(page)
            } while !appendedResults && !reachedEnd && fetchedPages < filteredPageLimit
            loadMoreErrorMessage = nil
        } catch {
            guard generation == requestGeneration else { return }
            if !Self.isCancellation(error) {
                loadMoreErrorMessage = error.localizedDescription
            }
        }
        if generation == requestGeneration {
            isLoadingMore = false
            requestTask = nil
        }
    }

    private func applyInitial(_ page: ProviderSearchPage) {
        var knownIDs = Set<String>()
        items = page.items.filter { knownIDs.insert($0.id).inserted }
        totalCount = page.totalCount
        nextPage = 2
        reachedEnd = page.isLastPage
        errorMessage = nil
        loadMoreErrorMessage = nil
    }

    @discardableResult
    private func append(_ page: ProviderSearchPage) -> Bool {
        let existingIDs = Set(items.map(\.id))
        let newItems = page.items.filter { !existingIDs.contains($0.id) }
        items = items + newItems
        nextPage = page.page + 1
        reachedEnd = page.isLastPage
        totalCount = page.totalCount
        return !newItems.isEmpty
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
