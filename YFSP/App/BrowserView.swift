import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        if viewModel.selectedCategory == nil {
            CategoryLandingView(viewModel: viewModel)
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

            Text(viewModel.selectedCategory?.title ?? "m.yfsp.tv")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct CategoryLandingView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.055, blue: 0.085),
                    Color(red: 0.12, green: 0.095, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 34) {
                ForEach(YfspCategory.allCases) { category in
                    Button {
                        viewModel.selectCategory(category)
                    } label: {
                        HStack(spacing: 18) {
                            Text(category.title)
                                .font(.system(size: 25, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.5))

                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 62)
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
