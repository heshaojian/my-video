import SwiftUI
import WebKit

private enum LibraryTab: Hashable {
    case latest
    case saved
    case played
}

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @StateObject private var savedItemsStore = SavedItemsStore()
    @StateObject private var playedItemsStore = PlayedItemsStore()
    @StateObject private var appSettings = AppSettingsStore()
    @State private var selectedLibraryTab = LibraryTab.latest

    var body: some View {
        Group {
            if let selectedItem = viewModel.selectedItem {
                NativePlayerScreen(
                    item: selectedItem,
                    initialEpisodeKey: viewModel.selectedEpisodeKey,
                    playedItemsStore: playedItemsStore,
                    onClose: viewModel.closePlayer,
                    onOpenWebsite: { viewModel.openWebsiteFallback(for: selectedItem) }
                )
            } else if let selectedCategory = viewModel.selectedCategory {
                NativeCategoryCatalogView(
                    category: selectedCategory,
                    savedItemsStore: savedItemsStore,
                    onSelectItem: viewModel.selectItem,
                    onClose: viewModel.closeCategory
                )
            } else if !viewModel.isBrowsing {
                LibraryView(
                    viewModel: viewModel,
                    savedItemsStore: savedItemsStore,
                    playedItemsStore: playedItemsStore,
                    appSettings: appSettings,
                    selectedTab: $selectedLibraryTab
                )
            } else {
                VStack(spacing: 0) {
                    HeaderView(viewModel: viewModel)

                    ZStack {
                        WebView(viewModel: viewModel)
                            .accessibilityIdentifier("browserWebView")

                        if let errorMessage = viewModel.errorMessage {
                            ContentUnavailableView(
                                "Could not load Aiyifan",
                                systemImage: "wifi.exclamationmark",
                                description: Text(errorMessage)
                            )
                            .padding()
                            .background(.background)
                        } else if !viewModel.hasCommittedContent && viewModel.estimatedProgress < 1 {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading Aiyifan")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .allowsHitTesting(false)
                        }
                    }

                    if !viewModel.hasCommittedContent && viewModel.estimatedProgress > 0 && viewModel.estimatedProgress < 1 {
                        ProgressView(value: viewModel.estimatedProgress)
                            .progressViewStyle(.linear)
                    }

                    BrowserToolbar(viewModel: viewModel)
                }
            }
        }
        .onOpenURL { url in
            if let destination = AiyifanDeepLink.parse(url) {
                viewModel.openDeepLink(destination)
            }
        }
    }
}

private struct LibraryView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @ObservedObject var appSettings: AppSettingsStore
    @Binding var selectedTab: LibraryTab
    @StateObject private var castManager = GoogleCastManager.shared
    @State private var isShowingCastControls = false

    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $selectedTab) {
                LatestHomeView(
                    viewModel: viewModel,
                    savedItemsStore: savedItemsStore,
                    playedItemsStore: playedItemsStore,
                    appSettings: appSettings
                )
                    .tabItem {
                        Label("Latest", systemImage: "sparkles.tv")
                    }
                    .tag(LibraryTab.latest)

                SavedItemsView(
                    viewModel: viewModel,
                    savedItemsStore: savedItemsStore,
                    appSettings: appSettings
                )
                    .tabItem {
                        Label("Saved", systemImage: "bookmark.fill")
                    }
                    .tag(LibraryTab.saved)

                PlayedItemsView(viewModel: viewModel, playedItemsStore: playedItemsStore)
                    .tabItem {
                        Label("Played", systemImage: "clock.arrow.circlepath")
                    }
                    .tag(LibraryTab.played)
            }
            .tint(.cyan)
            .overlay(alignment: .bottom) {
                if castManager.isCasting {
                    CastMiniController(manager: castManager) {
                        isShowingCastControls = true
                    }
                    .padding(.bottom, 50 + geometry.safeAreaInsets.bottom)
                }
            }
        }
        .sheet(isPresented: $isShowingCastControls) {
            CastExpandedController(manager: castManager)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack {
            Text("Aiyifan")
                .font(.headline)

            Spacer()

            Text(viewModel.selectedTitle ?? "Aiyifan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct LatestHomeView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @ObservedObject var appSettings: AppSettingsStore
    @State private var filter = LibraryFilter()
    @State private var isShowingFilters = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.052, blue: 0.073)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("最新更新")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(.white)

                                Spacer()

                                Button {
                                    isShowingFilters = true
                                } label: {
                                    Image(systemName: filter.isActive && filter.query.isEmpty ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                .accessibilityLabel("Filter Latest")
                                .accessibilityIdentifier("filterLatest")

                                Button {
                                    isShowingSettings = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                .accessibilityLabel("Settings")
                                .accessibilityIdentifier("appSettings")
                            }

                            Text("中文 / English")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                        if !continueWatching.isEmpty && !filter.isActive {
                            ContinueWatchingSection(
                                records: continueWatching,
                                onResume: viewModel.selectPlayed,
                                onRestart: playedItemsStore.restart,
                                onMarkWatched: playedItemsStore.markWatched,
                                onRemove: playedItemsStore.remove
                            )
                        }

                        if !newForYou.isEmpty && !filter.isActive {
                            NewForYouSection(
                                items: newForYou,
                                onPlay: viewModel.selectItem,
                                onMarkSeen: savedItemsStore.markUpdateSeen
                            )
                        }

                        if viewModel.isLoadingLatest {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else if let message = viewModel.latestErrorMessage {
                            ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(message))
                                .foregroundStyle(.white)
                                .padding(.horizontal)
                        } else if filter.isActive {
                            SearchResultsSection(
                                documents: searchResults,
                                onSelectItem: viewModel.selectItem,
                                isSaved: savedItemsStore.contains,
                                onToggleSaved: toggleSaved,
                                onClearSearch: { filter.query = "" }
                            )
                        } else {
                            ForEach(AiyifanCategory.allCases) { category in
                                LatestCategorySection(
                                    category: category,
                                    items: viewModel.latestItems[category] ?? [],
                                    onSelectCategory: { viewModel.selectCategory(category) },
                                    onSelectItem: { viewModel.selectItem($0) },
                                    isSaved: { savedItemsStore.contains($0) },
                                    onToggleSaved: toggleSaved
                                )
                            }
                        }

                        if let status = viewModel.latestStatusMessage {
                            Label(status, systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 18)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .accessibilityIdentifier("latestHome")
        .searchable(
            text: $filter.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search latest"
        )
        .sheet(isPresented: $isShowingFilters) {
            LibraryFilterSheet(filter: $filter, isPresented: $isShowingFilters)
        }
        .sheet(isPresented: $isShowingSettings) {
            AppSettingsView(
                settings: appSettings,
                viewModel: viewModel,
                savedItemsStore: savedItemsStore,
                playedItemsStore: playedItemsStore
            )
        }
        .task {
            await viewModel.loadLatestIfNeeded()
            let changedItems = savedItemsStore.refreshUpdateMarkers(with: viewModel.latestItems)
            if appSettings.updateAlertsEnabled,
               let batch = NotificationBatch.make(
                items: changedItems,
                notificationsEnabled: { item in savedItemsStore.notificationsEnabled(for: item) }
               ) {
                await NotificationCoordinator.shared.schedule(batch)
            }
            BackgroundRefreshScheduler.schedule()
        }
    }

    private var continueWatching: [PlayedRecord] {
        ContinueWatchingProjector.records(from: playedItemsStore.items)
    }

    private var documents: [LibraryDocument] {
        AiyifanCategory.allCases.flatMap { category in
            (viewModel.latestItems[category] ?? []).map { item in
                LibraryDocument(
                    item: item,
                    category: category,
                    watchState: watchState(for: item),
                    hasNewUpdate: savedItemsStore.hasNewUpdate(item)
                )
            }
        }
    }

    private var searchResults: [LibraryDocument] {
        LibrarySearchEngine.results(in: documents, matching: filter)
    }

    private var newForYou: [AiyifanItem] {
        documents.filter(\.hasNewUpdate).map(\.item)
    }

    private func watchState(for item: AiyifanItem) -> LibraryWatchState {
        let records = playedItemsStore.items.filter { $0.item.id == item.id }
        if records.isEmpty {
            return .unplayed
        }
        return records.contains(where: { !$0.isCompleted }) ? .inProgress : .watched
    }

    private func toggleSaved(_ item: AiyifanItem) {
        savedItemsStore.toggle(item)
        savedItemsStore.refreshUpdateMarkers(with: viewModel.latestItems)
    }
}

private struct ContinueWatchingSection: View {
    let records: [PlayedRecord]
    let onResume: (PlayedRecord) -> Void
    let onRestart: (PlayedRecord) -> Void
    let onMarkWatched: (PlayedRecord) -> Void
    let onRemove: (PlayedRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(records) { record in
                        Button {
                            onResume(record)
                        } label: {
                            HStack(spacing: 10) {
                                PosterImage(item: record.item)
                                    .frame(width: 66, height: 92)

                                VStack(alignment: .leading, spacing: 7) {
                                    Text(record.item.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    if let episode = record.episodeTitle {
                                        Text("Episode \(episode)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: record.duration > 0 ? record.position / record.duration : 0)
                                        .tint(.cyan)
                                }
                                .frame(width: 150, alignment: .leading)
                            }
                            .padding(10)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("continueItem-\(record.item.id)")
                        .contextMenu {
                            Button("Restart", systemImage: "arrow.counterclockwise") { onRestart(record) }
                            Button("Mark Watched", systemImage: "checkmark.circle") { onMarkWatched(record) }
                            Button("Remove", systemImage: "trash", role: .destructive) { onRemove(record) }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct NewForYouSection: View {
    let items: [AiyifanItem]
    let onPlay: (AiyifanItem) -> Void
    let onMarkSeen: (AiyifanItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New for You")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        LatestItemCard(
                            item: item,
                            isSaved: true,
                            onTap: { onPlay(item) },
                            onToggleSaved: { onMarkSeen(item) }
                        )
                        .overlay(alignment: .topLeading) {
                            Text("NEW")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .foregroundStyle(.black)
                                .background(.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(7)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct SearchResultsSection: View {
    let documents: [LibraryDocument]
    let onSelectItem: (AiyifanItem) -> Void
    let isSaved: (AiyifanItem) -> Bool
    let onToggleSaved: (AiyifanItem) -> Void
    let onClearSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Results")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 36, height: 36)
                }
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("clearSearch")
            }
            .padding(.horizontal, 18)

            if documents.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(documents) { document in
                        HStack(spacing: 8) {
                            Button {
                                onSelectItem(document.item)
                            } label: {
                                HStack(spacing: 12) {
                                    PosterImage(item: document.item)
                                        .frame(width: 58, height: 82)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(document.item.title).font(.headline).lineLimit(2)
                                        Text("\(document.category.title) · \(document.item.updateLabel)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("searchItem-\(document.item.id)")

                            Button {
                                onToggleSaved(document.item)
                            } label: {
                                Image(systemName: isSaved(document.item) ? "bookmark.fill" : "bookmark")
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel(isSaved(document.item) ? "Remove from Saved" : "Save for Later")
                            .accessibilityIdentifier("saveSearchItem-\(document.item.id)")
                        }
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Button("All") { filter.category = nil }
                        .accessibilityIdentifier("filterCategory-All")
                    ForEach(AiyifanCategory.allCases) { category in
                        Button {
                            filter.category = category
                        } label: {
                            HStack {
                                Text(category.title)
                                Spacer()
                                if filter.category == category { Image(systemName: "checkmark") }
                            }
                        }
                        .accessibilityIdentifier("filterCategory-\(category.id)")
                    }
                }

                Section("Language") {
                    Picker("Language", selection: $filter.language) {
                        Text("All").tag(ContentLanguage?.none)
                        ForEach(ContentLanguage.allCases) { language in
                            Text(language.title).tag(Optional(language))
                        }
                    }
                }

                Section("Watch State") {
                    Picker("Watch State", selection: $filter.watchState) {
                        ForEach(WatchStateFilter.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        let query = filter.query
                        filter = LibraryFilter(query: query)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { isPresented = false }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("applyFilters")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct LatestCategorySection: View {
    let category: AiyifanCategory
    let items: [AiyifanItem]
    let onSelectCategory: () -> Void
    let onSelectItem: (AiyifanItem) -> Void
    let isSaved: (AiyifanItem) -> Bool
    let onToggleSaved: (AiyifanItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.latestTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Button(action: onSelectCategory) {
                    HStack(spacing: 4) {
                        Text("全部")
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityIdentifier("browseCategory-\(category.id)")
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        LatestItemCard(
                            item: item,
                            isSaved: isSaved(item),
                            onTap: { onSelectItem(item) },
                            onToggleSaved: { onToggleSaved(item) }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct LatestItemCard: View {
    let item: AiyifanItem
    let isSaved: Bool
    let onTap: () -> Void
    let onToggleSaved: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 7) {
                    AsyncImage(url: item.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white.opacity(0.08))
                        case .empty:
                            ProgressView()
                                .tint(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white.opacity(0.08))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 132, height: 184)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.92))

                    Text(item.updateLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(width: 132, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("latestItem-\(item.id)")

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
            .accessibilityIdentifier("saveItem-\(item.id)")
        }
        .frame(width: 132, alignment: .leading)
    }
}

private struct BrowserToolbar: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 22) {
            Button {
                viewModel.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!viewModel.canGoBack)

            Button {
                viewModel.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!viewModel.canGoForward)

            Button {
                viewModel.goHome()
            } label: {
                Image(systemName: "house")
            }

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Spacer()

            Button {
                viewModel.openInSafari()
            } label: {
                Image(systemName: "safari")
            }
        }
        .font(.system(size: 19, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
