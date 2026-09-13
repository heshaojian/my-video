import SwiftUI

struct NativeCategoryCatalogView: View {
    @ObservedObject var savedItemsStore: SavedItemsStore
    let onSelectItem: (MyVideoItem) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: CategoryCatalogViewModel
    @State private var isShowingFilters = false

    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 180), spacing: 14)
    ]

    init(
        category: MyVideoCategory,
        savedItemsStore: SavedItemsStore,
        onSelectItem: @escaping (MyVideoItem) -> Void,
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
                LibraryScreenChrome.background
                    .ignoresSafeArea()

                content
            }
            .navigationTitle(viewModel.category.title)
            .navigationBarTitleDisplayMode(.inline)
            .libraryNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.backward")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Back to Home")
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
                    .accessibilityLabel("Filters")
                    .accessibilityValue("\(viewModel.appliedQuery.activeFilterCount) selected")
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
            ProgressView("Loading")
                .tint(.white)
                .foregroundStyle(.white)
                .accessibilityIdentifier("catalogInitialLoading")
        } else if let message = viewModel.initialErrorMessage, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.loadInitial() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retryCatalogInitial")
            }
            .foregroundStyle(.white)
        } else if viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("No Titles Found", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(viewModel.appliedQuery.activeFilterCount > 0 ? "Try clearing your filters." : "No titles are available.")
            } actions: {
                if viewModel.appliedQuery.activeFilterCount > 0 {
                    Button("Clear Filters") {
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
                    Text("\(viewModel.totalCount) results")
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
                Label("Load failed. Tap to retry.", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("retryCatalogLoadMore")
        } else if viewModel.reachedEnd {
            Text("All results shown")
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
                    viewModel.appliedQuery.descending ? "Switch to Ascending" : "Switch to Descending",
                    systemImage: viewModel.appliedQuery.descending ? "arrow.up" : "arrow.down"
                )
            }
            .accessibilityIdentifier("catalogSortDirection")
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Sort: \(viewModel.appliedQuery.sort.title)")
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
                    ProgressView("Loading Filters")
                } else if let message = viewModel.filterErrorMessage, viewModel.filterSet == nil {
                    ContentUnavailableView {
                        Label("Unable to Load Filters", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await viewModel.loadFilters() } }
                            .accessibilityIdentifier("retryCatalogFilters")
                    }
                } else if let filters = viewModel.filterSet {
                    Form {
                        filterPicker(
                            title: "Genre",
                            selection: binding(\.genreCID, set: viewModel.setDraftGenre),
                            options: filters.genres
                        )
                        filterPicker(
                            title: "Region",
                            selection: binding(\.region, set: viewModel.setDraftRegion),
                            options: filters.regions
                        )
                        filterPicker(
                            title: "Language",
                            selection: binding(\.language, set: viewModel.setDraftLanguage),
                            options: filters.languages
                        )
                        filterPicker(
                            title: "Year",
                            selection: binding(\.year, set: viewModel.setDraftYear),
                            options: filters.years
                        )
                        filterPicker(
                            title: "Quality",
                            selection: binding(\.quality, set: viewModel.setDraftQuality),
                            options: filters.qualities
                        )
                        if !filters.statuses.isEmpty {
                            filterPicker(
                                title: "Status",
                                selection: Binding(
                                    get: { viewModel.draftQuery.status?.rawValue },
                                    set: { viewModel.setDraftStatus($0.flatMap(CatalogSerialStatus.init(rawValue:))) }
                                ),
                                options: filters.statuses
                            )
                        }

                        Section {
                            Button("Reset All Filters") { viewModel.resetDraftFilters() }
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
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelFilterEditing()
                        onDismiss()
                    }
                    .accessibilityIdentifier("cancelCatalogFilters")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
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
        set: @escaping @MainActor @Sendable (String?) -> Void
    ) -> Binding<String?> {
        Binding(
            get: { viewModel.draftQuery[keyPath: keyPath] },
            set: { value in set(value) }
        )
    }

    private func filterPicker(
        title: String,
        selection: Binding<String?>,
        options: [CatalogFilterOption]
    ) -> some View {
        Section {
            Picker(title, selection: selection) {
                Text("All").tag(String?.none)
                ForEach(options) { option in
                    Text(option.title).tag(Optional(option.value))
                }
            }
            .accessibilityIdentifier("catalogFilter-\(title)")
        }
    }
}
