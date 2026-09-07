import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

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

private struct HeaderView: View {
    var body: some View {
        HStack {
            Text("YFSP")
                .font(.headline)

            Spacer()

            Text("m.yfsp.tv")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
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
