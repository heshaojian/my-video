import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        if !viewModel.isBrowsing {
            LatestHomeView(viewModel: viewModel)
        } else {
            VStack(spacing: 0) {
                HeaderView(viewModel: viewModel)

                ZStack {
                    WebView(viewModel: viewModel)

                    if let errorMessage = viewModel.errorMessage {
                        ContentUnavailableView("Could not load YFSP", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                            .padding()
                            .background(.background)
                    } else if viewModel.estimatedProgress < 1 {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading yfsp.tv")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if viewModel.estimatedProgress > 0 && viewModel.estimatedProgress < 1 {
                    ProgressView(value: viewModel.estimatedProgress)
                        .progressViewStyle(.linear)
                }

                BrowserToolbar(viewModel: viewModel)
            }
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack {
            Text("YFSP")
                .font(.headline)

            Spacer()

            Text(viewModel.selectedTitle ?? "m.yfsp.tv")
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
                            ForEach(YfspCategory.allCases) { category in
                                LatestCategorySection(
                                    category: category,
                                    items: viewModel.latestItems[category] ?? [],
                                    onSelectCategory: { viewModel.selectCategory(category) },
                                    onSelectItem: { viewModel.selectItem($0) }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            await viewModel.loadLatestIfNeeded()
        }
    }
}

private struct LatestCategorySection: View {
    let category: YfspCategory
    let items: [YfspItem]
    let onSelectCategory: () -> Void
    let onSelectItem: (YfspItem) -> Void

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
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        LatestItemCard(item: item) {
                            onSelectItem(item)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

private struct LatestItemCard: View {
    let item: YfspItem
    let onTap: () -> Void

    var body: some View {
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
        }
        .buttonStyle(.plain)
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
