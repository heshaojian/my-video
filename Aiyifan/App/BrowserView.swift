import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @StateObject private var savedItemsStore = SavedItemsStore()

    var body: some View {
        if let selectedItem = viewModel.selectedItem {
            NativePlayerScreen(
                item: selectedItem,
                onClose: viewModel.closePlayer,
                onOpenWebsite: { viewModel.openWebsiteFallback(for: selectedItem) }
            )
        } else if !viewModel.isBrowsing {
            LibraryView(viewModel: viewModel, savedItemsStore: savedItemsStore)
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
}

private struct LibraryView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore

    var body: some View {
        TabView {
            LatestHomeView(viewModel: viewModel, savedItemsStore: savedItemsStore)
                .tabItem {
                    Label("Latest", systemImage: "sparkles.tv")
                }

            SavedItemsView(viewModel: viewModel, savedItemsStore: savedItemsStore)
                .tabItem {
                    Label("Saved", systemImage: "bookmark.fill")
                }
        }
        .tint(.cyan)
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.052, blue: 0.073)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("最新更新")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)

                            Text("中文 / English")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                        if viewModel.isLoadingLatest {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else if let message = viewModel.latestErrorMessage {
                            ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(message))
                                .foregroundStyle(.white)
                                .padding(.horizontal)
                        } else {
                            ForEach(AiyifanCategory.allCases) { category in
                                LatestCategorySection(
                                    category: category,
                                    items: viewModel.latestItems[category] ?? [],
                                    onSelectCategory: { viewModel.selectCategory(category) },
                                    onSelectItem: { viewModel.selectItem($0) },
                                    isSaved: { savedItemsStore.contains($0) },
                                    onToggleSaved: { savedItemsStore.toggle($0) }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .accessibilityIdentifier("latestHome")
        .task {
            await viewModel.loadLatestIfNeeded()
        }
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

private struct SavedItemsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.052, blue: 0.073)
                    .ignoresSafeArea()

                if savedItemsStore.items.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "bookmark",
                        description: Text("Save something from Latest and it will appear here.")
                    )
                    .foregroundStyle(.white)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(savedItemsStore.items) { item in
                                SavedItemCard(
                                    item: item,
                                    onTap: { viewModel.selectItem(item) },
                                    onRemove: { savedItemsStore.toggle(item) }
                                )
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("Saved")
        }
    }
}

private struct SavedItemCard: View {
    let item: AiyifanItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 7) {
                    AsyncImage(url: item.thumbnailURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white.opacity(0.08))
                        }
                    }
                    .aspectRatio(0.72, contentMode: .fit)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("savedItem-\(item.id)")

            Button(action: onRemove) {
                Image(systemName: "bookmark.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.cyan)
                    .clipShape(Circle())
            }
            .padding(7)
            .accessibilityLabel("Remove from Saved")
            .accessibilityIdentifier("removeSavedItem-\(item.id)")
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
