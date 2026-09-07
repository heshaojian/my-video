import SwiftUI

struct NativeCategoryCatalogView: View {
    @ObservedObject var savedItemsStore: SavedItemsStore
    let onSelectItem: (AiyifanItem) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: CategoryCatalogViewModel
    @State private var isShowingFilters = false

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

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.beginFilterEditing()
                        isShowingFilters = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .frame(width: 44, height: 44)
                            if viewModel.appliedQuery.activeFilterCount > 0 {
                                Text("\(viewModel.appliedQuery.activeFilterCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.black)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.cyan)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .accessibilityLabel("筛选")
                    .accessibilityValue("已选 \(viewModel.appliedQuery.activeFilterCount) 项")
                    .accessibilityIdentifier("catalogFilter")

                    catalogSortMenu
                }
            }
        }
        .tint(.cyan)
        .accessibilityIdentifier("nativeCategoryCatalog-\(viewModel.category.id)")
        .task {
            await viewModel.loadInitial()
        }
        .sheet(isPresented: $isShowingFilters) {
            CatalogFilterSheet(viewModel: viewModel) {
                isShowingFilters = false
            }
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
            ContentUnavailableView {
                Label("未找到内容", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(viewModel.appliedQuery.activeFilterCount > 0 ? "试试清除筛选条件" : "暂无内容")
            } actions: {
                if viewModel.appliedQuery.activeFilterCount > 0 {
                    Button("清除筛选") {
                        Task { _ = await viewModel.clearFilters() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("clearCatalogFilters")
                }
            }
            .foregroundStyle(.white)
            .accessibilityIdentifier("catalogEmpty")
        } else {
            catalogGrid
        }
    }

    private var catalogGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("共 \(viewModel.totalCount) 个结果")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityIdentifier("catalogResultCount")
                    Spacer()
                    if viewModel.isApplyingQuery {
                        ProgressView()
                            .tint(.cyan)
                            .accessibilityIdentifier("catalogApplyingQuery")
                    }
                }

                if let message = viewModel.queryErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("catalogQueryError")
                }

                if let message = viewModel.refreshErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("catalogRefreshError")
                }

                LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
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
                }

                catalogFooter
                    .frame(maxWidth: .infinity)
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

    private var catalogSortMenu: some View {
        Menu {
            ForEach(CatalogSort.allCases, id: \.rawValue) { sort in
                Button {
                    Task { _ = await viewModel.applySort(sort, descending: viewModel.appliedQuery.descending) }
                } label: {
                    if sort == viewModel.appliedQuery.sort {
                        Label(sort.title, systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
                .accessibilityIdentifier("catalogSort-\(sort.rawValue)")
            }

            Divider()

            Button {
                Task {
                    _ = await viewModel.applySort(
                        viewModel.appliedQuery.sort,
                        descending: !viewModel.appliedQuery.descending
                    )
                }
            } label: {
                Label(
                    viewModel.appliedQuery.descending ? "切换为升序" : "切换为降序",
                    systemImage: viewModel.appliedQuery.descending ? "arrow.up" : "arrow.down"
                )
            }
            .accessibilityIdentifier("catalogSortDirection")
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("排序：\(viewModel.appliedQuery.sort.title)")
        .accessibilityIdentifier("catalogSort")
    }
}

private struct CatalogFilterSheet: View {
    @ObservedObject var viewModel: CategoryCatalogViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingFilters {
                    ProgressView("正在加载筛选项")
                } else if let message = viewModel.filterErrorMessage, viewModel.filterSet == nil {
                    ContentUnavailableView {
                        Label("筛选项加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") { Task { await viewModel.loadFilters() } }
                            .accessibilityIdentifier("retryCatalogFilters")
                    }
                } else if let filters = viewModel.filterSet {
                    Form {
                        filterPicker(
                            title: "类型",
                            selection: binding(\.genreCID, set: viewModel.setDraftGenre),
                            options: filters.genres
                        )
                        filterPicker(
                            title: "地区",
                            selection: binding(\.region, set: viewModel.setDraftRegion),
                            options: filters.regions
                        )
                        filterPicker(
                            title: "语言",
                            selection: binding(\.language, set: viewModel.setDraftLanguage),
                            options: filters.languages
                        )
                        filterPicker(
                            title: "年份",
                            selection: binding(\.year, set: viewModel.setDraftYear),
                            options: filters.years
                        )
                        filterPicker(
                            title: "画质",
                            selection: binding(\.quality, set: viewModel.setDraftQuality),
                            options: filters.qualities
                        )
                        if !filters.statuses.isEmpty {
                            filterPicker(
                                title: "状态",
                                selection: Binding(
                                    get: { viewModel.draftQuery.status?.rawValue },
                                    set: { viewModel.setDraftStatus($0.flatMap(CatalogSerialStatus.init(rawValue:))) }
                                ),
                                options: filters.statuses
                            )
                        }

                        Section {
                            Button("重置所有筛选") { viewModel.resetDraftFilters() }
                                .frame(maxWidth: .infinity)
                                .disabled(viewModel.isApplyingQuery)
                                .accessibilityIdentifier("resetCatalogFilters")
                        }

                        if let message = viewModel.queryErrorMessage {
                            Section {
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .accessibilityIdentifier("filterApplyError")
                            }
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelFilterEditing()
                        onDismiss()
                    }
                    .accessibilityIdentifier("cancelCatalogFilters")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        Task {
                            if await viewModel.applyDraftQuery() {
                                onDismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isApplyingQuery || viewModel.filterSet == nil)
                    .accessibilityIdentifier("applyCatalogFilters")
                }
            }
        }
        .task {
            await viewModel.loadFilters()
        }
        .interactiveDismissDisabled(viewModel.isApplyingQuery)
        .preferredColorScheme(.dark)
    }

    private func binding(
        _ keyPath: KeyPath<CatalogQuery, String?>,
        set: @escaping (String?) -> Void
    ) -> Binding<String?> {
        Binding(get: { viewModel.draftQuery[keyPath: keyPath] }, set: set)
    }

    private func filterPicker(
        title: String,
        selection: Binding<String?>,
        options: [CatalogFilterOption]
    ) -> some View {
        Section {
            Picker(title, selection: selection) {
                Text("全部").tag(String?.none)
                ForEach(options) { option in
                    Text(option.title).tag(Optional(option.value))
                }
            }
            .accessibilityIdentifier("catalogFilter-\(title)")
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
