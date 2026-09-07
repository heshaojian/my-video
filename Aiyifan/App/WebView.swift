import SwiftUI
import WebKit

enum WebViewPopupPolicy {
    static let shouldReplaceCurrentPage = false
}

struct WebViewLoadTracker {
    private var lastRequestedURL: URL?

    mutating func shouldLoad(_ url: URL) -> Bool {
        guard lastRequestedURL != url else {
            return false
        }

        lastRequestedURL = url
        return true
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.accessibilityIdentifier = "browserWebView"
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: [.new], context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: [.new], context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: [.new], context: nil)

        viewModel.bind(webView: webView)
        loadCurrentURL(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        viewModel.bind(webView: webView)
        loadCurrentURL(in: webView, coordinator: context.coordinator)
    }

    private func loadCurrentURL(in webView: WKWebView, coordinator: Coordinator) {
        guard let url = viewModel.currentURL, coordinator.loadTracker.shouldLoad(url) else {
            return
        }

        webView.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        webView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.canGoForward))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private weak var viewModel: BrowserViewModel?
        var loadTracker = WebViewLoadTracker()

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            Task { @MainActor in
                self.viewModel?.updateNavigationState()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel?.updateNavigationState()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel?.markLoadingStarted()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel?.markContentCommitted()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel?.markLoadingFailed(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel?.markLoadingFailed(error)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil && WebViewPopupPolicy.shouldReplaceCurrentPage {
                webView.load(navigationAction.request)
            }

            return nil
        }
    }
}
