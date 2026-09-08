import SwiftUI

struct ProviderSearchResultsView: View {
    @ObservedObject var viewModel: ProviderSearchViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    let onSelectItem: (AiyifanItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 180), spacing: 14)
    ]

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Searching")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                    .accessibilityIdentifier("searchLoading")
            } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView {
                    Label("Search Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task { _ = await viewModel.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retrySearch")
                }
                .foregroundStyle(.white)
            } else if viewModel.showsEmptyResults {
                ContentUnavailableView(
                    "No titles found",
                    systemImage: "magnifyingglass",
                    description: Text("Try another title.")
                )
                .foregroundStyle(.white)
                .accessibilityIdentifier("searchEmpty")
            } else {
                results
            }
        }
        .accessibilityIdentifier("providerSearchResults")
    }

    private var results: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(viewModel.items.count) shown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .accessibilityIdentifier("searchResultCount")
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.cyan)
                }
            }

            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                ForEach(viewModel.items) { item in
                    PosterMediaCard(
                        item: item,
                        layout: .grid,
                        actionStyle: .save(isSaved: savedItemsStore.contains(item)),
                        itemIdentifier: "catalogItem-\(item.id)",
                        actionIdentifier: "saveCatalogItem-\(item.id)",
                        scoreIdentifier: "catalogScore-\(item.id)",
                        onTap: { onSelectItem(item) },
                        onAction: { savedItemsStore.toggle(item) }
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: item)
                    }
                }
            }

            if viewModel.loadMoreErrorMessage != nil {
                Button {
                    Task { await viewModel.retryLoadMore() }
                } label: {
                    Label("Load failed. Tap to retry.", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("retrySearchLoadMore")
            } else if viewModel.canContinueFilteredSearch {
                Button {
                    Task { await viewModel.retryLoadMore() }
                } label: {
                    Label("Search more results", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("continueFilteredSearch")
            } else if viewModel.reachedEnd {
                Text("All results shown")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 44)
            } else {
                Color.clear.frame(height: 44)
            }
        }
        .padding(.horizontal, 18)
    }
}
