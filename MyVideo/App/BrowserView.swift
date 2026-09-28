import SwiftUI
import WebKit

private enum LibraryTab: Hashable {
    case home
    case saved
    case played
}

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @StateObject private var savedItemsStore = SavedItemsStore()
    @StateObject private var playedItemsStore = PlayedItemsStore()
    @StateObject private var readyToWatchStore = ReadyToWatchOverridesStore()
    @StateObject private var appSettings = AppSettingsStore()
    @StateObject private var playbackSession = PlaybackSessionController()
    @StateObject private var castManager = GoogleCastManager.shared
    @StateObject private var savedUpdateMonitor = SavedUpdateMonitor()
    @State private var selectedLibraryTab = LibraryTab.home
    @State private var appOpenRefreshCoordinator = AppOpenLibraryRefreshCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            baseContent

            if playbackSession.presentation == .expanded,
               let playerViewModel = playbackSession.viewModel {
                NativePlayerScreen(
                    viewModel: playerViewModel,
                    onClose: playbackSession.collapse,
                    onOpenWebsite: {
                        let item = playerViewModel.item
                        playbackSession.stop()
                        viewModel.openWebsiteFallback(for: item)
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .overlay(alignment: .bottom) {
            if playbackSession.presentation == .collapsed,
               let playerViewModel = playbackSession.viewModel,
               !castManager.isCasting {
                NativeMiniPlayer(
                    viewModel: playerViewModel,
                    onExpand: playbackSession.expand,
                    onClose: playbackSession.stop
                )
                .padding(.horizontal, 10)
                .padding(.bottom, showsLibrary ? 50 : 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playbackSession.presentation)
        .onChange(of: viewModel.selectedItem) { _, item in
            guard let item else { return }
            let monitorsPlayback = !MyVideoFixtureRuntime.usesFixtureFeed
                || MyVideoFixtureRuntime.usesPlayableFixtureMedia
            playbackSession.play(
                item: item,
                episodeKey: viewModel.selectedEpisodeKey,
                playedItemsStore: playedItemsStore,
                monitorPlayback: monitorsPlayback,
                onEpisodesObserved: { episodes in
                    guard savedItemsStore.contains(item) else { return }
                    savedItemsStore.observeEpisodes(itemID: item.id, episodes: episodes)
                }
            )
            viewModel.closePlayer()
        }
        .onOpenURL { url in
            if let destination = MyVideoDeepLink.parse(url) {
                viewModel.openDeepLink(destination)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshLibraryAtAppOpen()
        }
        .task {
            BackgroundRefreshScheduler.schedule()
        }
        .onChange(of: selectedLibraryTab) { _, tab in
            guard tab == .home else { return }
            Task { await refreshHome(force: false) }
        }
    }

    @ViewBuilder
    private var baseContent: some View {
        Group {
            if let selectedCategory = viewModel.selectedCategory {
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
                    readyToWatchStore: readyToWatchStore,
                    appSettings: appSettings,
                    savedUpdateMonitor: savedUpdateMonitor,
                    selectedTab: $selectedLibraryTab,
                    onRefreshHome: refreshHome
                )
            } else {
                VStack(spacing: 0) {
                    HeaderView(viewModel: viewModel)

                    ZStack {
                        WebView(viewModel: viewModel)
                            .accessibilityIdentifier("browserWebView")

                        if let errorMessage = viewModel.errorMessage {
                            ContentUnavailableView(
                                "Could not load MyVideo",
                                systemImage: "wifi.exclamationmark",
                                description: Text(errorMessage)
                            )
                            .padding()
                            .background(.background)
                        } else if !viewModel.hasCommittedContent && viewModel.estimatedProgress < 1 {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading MyVideo")
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
    }

    private var showsLibrary: Bool {
        viewModel.selectedCategory == nil && !viewModel.isBrowsing
    }

    private func refreshHome(force: Bool) async {
        _ = await refreshHomeAndReportSuccess(force: force)
    }

    private func refreshHomeAndReportSuccess(force: Bool) async -> Bool {
        let didRefresh = await viewModel.loadLatestIfNeeded(force: force)
        guard didRefresh else { return false }

        let changedItems = savedItemsStore.refreshUpdateMarkers(with: viewModel.latestItems)
        if appSettings.updateAlertsEnabled,
           let batch = NotificationBatch.make(
               items: changedItems,
               notificationsEnabled: { savedItemsStore.notificationsEnabled(for: $0) }
           ) {
            await NotificationCoordinator.shared.schedule(batch)
        }
        return viewModel.lastLoadProducedFreshContent
    }

    private func refreshLibraryAtAppOpen() async {
        _ = await appOpenRefreshCoordinator.refreshIfNeeded {
            let homeSucceeded = await refreshHomeAndReportSuccess(force: true)
            guard !Task.isCancelled else { return false }
            let savedResult = await savedUpdateMonitor.check(
                savedItemsStore: savedItemsStore,
                settings: appSettings,
                force: true
            )
            return homeSucceeded && savedResult.isComplete
        }
    }
}

private struct LibraryView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @ObservedObject var readyToWatchStore: ReadyToWatchOverridesStore
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var savedUpdateMonitor: SavedUpdateMonitor
    @Binding var selectedTab: LibraryTab
    let onRefreshHome: (Bool) async -> Void
    @StateObject private var castManager = GoogleCastManager.shared
    @State private var isShowingCastControls = false

    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $selectedTab) {
                HomeView(
                    viewModel: viewModel,
                    savedItemsStore: savedItemsStore,
                    playedItemsStore: playedItemsStore,
                    appSettings: appSettings,
                    savedUpdateMonitor: savedUpdateMonitor,
                    onRefreshHome: onRefreshHome
                )
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(LibraryTab.home)

                SavedItemsView(
                    viewModel: viewModel,
                    savedItemsStore: savedItemsStore,
                    playedItemsStore: playedItemsStore,
                    readyToWatchStore: readyToWatchStore,
                    appSettings: appSettings,
                    savedUpdateMonitor: savedUpdateMonitor
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
            Text("MyVideo")
                .font(.headline)

            Spacer()

            Text(viewModel.selectedTitle ?? "MyVideo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct HomeView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var savedUpdateMonitor: SavedUpdateMonitor
    let onRefreshHome: (Bool) async -> Void
    @StateObject private var searchViewModel = ProviderSearchViewModel()
    @State private var isShowingSettings = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryScreenChrome.background
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        LibraryScreenHeader(title: "Home", accessibilityIdentifier: "homeScreenTitle") {
                            if !searchViewModel.isExpanded {
                                Button {
                                    searchViewModel.expand()
                                    DispatchQueue.main.async {
                                        isSearchFocused = true
                                    }
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                .accessibilityLabel("Search")
                                .accessibilityIdentifier("showSearch")
                            }

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
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                        if searchViewModel.isExpanded {
                            searchControls
                        }

                        if searchViewModel.submittedQuery != nil {
                            ProviderSearchResultsView(
                                viewModel: searchViewModel,
                                savedItemsStore: savedItemsStore,
                                onSelectItem: viewModel.selectItem
                            )
                        } else {
                            if !continueWatching.isEmpty {
                                ContinueWatchingSection(
                                    records: continueWatching,
                                    onResume: viewModel.selectPlayed,
                                    onRestart: playedItemsStore.restart,
                                    onMarkWatched: playedItemsStore.markWatched,
                                    onRemove: playedItemsStore.remove
                                )
                            }

                            if !newForYou.isEmpty {
                                NewForYouSection(
                                    items: newForYou,
                                    onPlay: viewModel.selectItem,
                                    onMarkSeen: savedItemsStore.markUpdateSeen
                                )
                            }

                            if let status = viewModel.latestStatusMessage {
                                Label(status, systemImage: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .padding(.horizontal, 18)
                            }

                            if viewModel.isLoadingLatest && !viewModel.latestItems.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.cyan)
                                    Text("Updating Home")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                                .padding(.horizontal, 18)
                                .accessibilityIdentifier("homeRefreshProgress")
                            }

                            if viewModel.isLoadingLatest && viewModel.latestItems.isEmpty {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 80)
                            } else if let message = viewModel.latestErrorMessage {
                                ContentUnavailableView("Unable to Load", systemImage: "wifi.exclamationmark", description: Text(message))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal)
                            } else {
                                ForEach(MyVideoCategory.allCases) { category in
                                    HomeCategorySection(
                                        category: category,
                                        items: viewModel.latestItems[category] ?? [],
                                        onSelectCategory: { viewModel.selectCategory(category) },
                                        onSelectItem: { viewModel.selectItem($0) },
                                        isSaved: { savedItemsStore.contains($0) },
                                        onToggleSaved: toggleSaved
                                    )
                                }
                            }
                        }
                    }
                    .padding(.bottom, LibraryScreenChrome.scrollBottomClearance)
                }
                .refreshable {
                    guard searchViewModel.submittedQuery == nil else { return }
                    await onRefreshHome(true)
                }
            }
        }
        .accessibilityIdentifier("homeView")
        .sheet(isPresented: $isShowingSettings) {
            AppSettingsView(
                settings: appSettings,
                viewModel: viewModel,
                savedItemsStore: savedItemsStore,
                playedItemsStore: playedItemsStore,
                savedUpdateMonitor: savedUpdateMonitor
            )
        }
    }

    private var continueWatching: [PlayedRecord] {
        ContinueWatchingProjector.records(from: playedItemsStore.items)
    }

    private var newForYou: [MyVideoItem] {
        MyVideoCategory.allCases
            .flatMap { viewModel.latestItems[$0] ?? [] }
            .filter(savedItemsStore.hasNewUpdate)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.5))

                    TextField("Search titles", text: $searchViewModel.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .onSubmit(submitSearch)
                        .accessibilityIdentifier("providerSearchField")

                    if !searchViewModel.query.isEmpty {
                        Button {
                            searchViewModel.query = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Clear Search Text")
                    }

                    Button(action: submitSearch) {
                        Image(systemName: "arrow.right")
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.cyan)
                    .accessibilityLabel("Submit Search")
                    .accessibilityIdentifier("submitSearch")
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("expandedSearchFieldContainer")

                Button {
                    isSearchFocused = false
                    searchViewModel.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityLabel("Close Search")
                .accessibilityIdentifier("cancelSearch")
            }

            if let message = searchViewModel.validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityIdentifier("searchValidation")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
    }

    private func submitSearch() {
        isSearchFocused = false
        Task { _ = await searchViewModel.submit() }
    }

    private func toggleSaved(_ item: MyVideoItem) {
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
                        ProgressMediaCard(
                            item: record.item,
                            subtitle: EpisodeDisplayLabel.sanitized(
                                record.episodeTitle,
                                excluding: record.episodeKey.map { [$0] } ?? []
                            ),
                            progress: record.duration > 0 ? record.position / record.duration : 0,
                            progressLabel: nil,
                            itemIdentifier: "continueItem-\(record.item.id)",
                            onTap: { onResume(record) },
                            trailingActions: { EmptyView() }
                        )
                        .frame(width: 250)
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
    let items: [MyVideoItem]
    let onPlay: (MyVideoItem) -> Void
    let onMarkSeen: (MyVideoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New for You")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        PosterMediaCard(
                            item: item,
                            layout: .compact,
                            actionStyle: .markSeen,
                            itemIdentifier: "latestItem-\(item.id)",
                            actionIdentifier: "saveItem-\(item.id)",
                            scoreIdentifier: "latestScore-\(item.id)",
                            status: "NEW",
                            onTap: { onPlay(item) },
                            onAction: { onMarkSeen(item) }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct HomeCategorySection: View {
    let category: MyVideoCategory
    let items: [MyVideoItem]
    let onSelectCategory: () -> Void
    let onSelectItem: (MyVideoItem) -> Void
    let isSaved: (MyVideoItem) -> Bool
    let onToggleSaved: (MyVideoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.latestTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Button(action: onSelectCategory) {
                    HStack(spacing: 4) {
                        Text("All")
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
                        PosterMediaCard(
                            item: item,
                            layout: .compact,
                            actionStyle: .save(isSaved: isSaved(item)),
                            itemIdentifier: "latestItem-\(item.id)",
                            actionIdentifier: "saveItem-\(item.id)",
                            scoreIdentifier: "latestScore-\(item.id)",
                            onTap: { onSelectItem(item) },
                            onAction: { onToggleSaved(item) }
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
        }
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
