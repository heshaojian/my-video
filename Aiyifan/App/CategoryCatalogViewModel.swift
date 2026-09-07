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
    }

    func loadInitial() async {
        guard items.isEmpty, !isLoadingInitial else {
            return
        }
        let requestGeneration = generation
        isLoadingInitial = true
        initialErrorMessage = nil

        do {
            let page = try await service.fetchPage(category: category, page: 1, pageSize: pageSize)
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

    func refresh() async {
        generation += 1
        let requestGeneration = generation
        isLoadingInitial = false
        isRefreshing = true
        initialErrorMessage = nil
        loadMoreErrorMessage = nil
        refreshErrorMessage = nil

        do {
            let page = try await service.fetchPage(category: category, page: 1, pageSize: pageSize)
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

    private func loadNextPage() async {
        guard !reachedEnd, !isLoadingMore, !items.isEmpty else {
            return
        }
        let pageNumber = nextPage
        let requestGeneration = generation
        isLoadingMore = true

        do {
            let page = try await service.fetchPage(category: category, page: pageNumber, pageSize: pageSize)
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
        initialErrorMessage = nil
        loadMoreErrorMessage = nil
        refreshErrorMessage = nil
    }
}
