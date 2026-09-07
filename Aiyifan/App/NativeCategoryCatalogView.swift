import SwiftUI

struct NativeCategoryCatalogView: View {
    @ObservedObject var savedItemsStore: SavedItemsStore
    let onSelectItem: (AiyifanItem) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: CategoryCatalogViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 180), spacing: 14)
    ]

    init(
        category: AiyifanCategory,
        savedItemsStore: SavedItemsStore,
        onSelectItem: @escaping (AiyifanItem) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.savedItemsStore = savedItemsStore
        self.onSelectItem = onSelectItem
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: CategoryCatalogViewModel(category: category))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.052, blue: 0.073)
                    .ignoresSafeArea()

                content
            }
            .navigationTitle(viewModel.category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.055, green: 0.052, blue: 0.073), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.backward")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Back to Latest")
                    .accessibilityIdentifier("closeCategoryCatalog")
                }
            }
        }
        .tint(.cyan)
        .accessibilityIdentifier("nativeCategoryCatalog-\(viewModel.category.id)")
        .task {
            await viewModel.loadInitial()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingInitial && viewModel.items.isEmpty {
            ProgressView("正在加载")
                .tint(.white)
                .foregroundStyle(.white)
                .accessibilityIdentifier("catalogInitialLoading")
        } else if let message = viewModel.initialErrorMessage, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await viewModel.loadInitial() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retryCatalogInitial")
            }
            .foregroundStyle(.white)
        } else if viewModel.items.isEmpty {
            ContentUnavailableView("暂无内容", systemImage: "film.stack")
                .foregroundStyle(.white)
                .accessibilityIdentifier("catalogEmpty")
        } else {
            catalogGrid
        }
    }

    private var catalogGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                if let message = viewModel.refreshErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(columns.count)
                        .accessibilityIdentifier("catalogRefreshError")
                }

                ForEach(viewModel.items) { item in
                    CatalogItemCard(
                        item: item,
                        isSaved: savedItemsStore.contains(item),
                        onTap: { onSelectItem(item) },
                        onToggleSaved: { savedItemsStore.toggle(item) }
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: item)
                    }
                }

                catalogFooter
                    .gridCellColumns(columns.count)
            }
            .padding(18)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var catalogFooter: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .tint(.white)
                .frame(height: 52)
                .accessibilityIdentifier("catalogLoadingMore")
        } else if viewModel.loadMoreErrorMessage != nil {
            Button {
                Task { await viewModel.retryLoadMore() }
            } label: {
                Label("加载失败，点击重试", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("retryCatalogLoadMore")
        } else if viewModel.reachedEnd {
            Text("已显示全部")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 44)
        } else {
            Color.clear.frame(height: 44)
        }
    }
}

private struct CatalogItemCard: View {
    let item: AiyifanItem
    let isSaved: Bool
    let onTap: () -> Void
    let onToggleSaved: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 7) {
                    PosterImage(item: item)
                        .aspectRatio(0.72, contentMode: .fit)

                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.94))

                    Text(item.updateLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.cyan.opacity(0.82))

                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("catalogItem-\(item.id)")

            Button(action: onToggleSaved) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSaved ? .black : .white)
                    .frame(width: 34, height: 34)
                    .background(isSaved ? Color.cyan : Color.black.opacity(0.68))
                    .clipShape(Circle())
            }
            .padding(7)
            .accessibilityLabel(isSaved ? "Remove from Saved" : "Save for Later")
            .accessibilityIdentifier("saveCatalogItem-\(item.id)")
        }
        .frame(maxWidth: 180, alignment: .leading)
    }

    private var metadata: String {
        [item.year, item.region]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}
