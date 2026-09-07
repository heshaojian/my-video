import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    let homeURL = URL(string: "https://m.yfsp.tv/")!

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var estimatedProgress = 0.0
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    func bind(webView: WKWebView) {
        guard self.webView !== webView else {
            return
        }

        self.webView = webView
        Task { @MainActor in
            self.updateNavigationState()
        }
    }

    func updateNavigationState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        estimatedProgress = webView?.estimatedProgress ?? 0
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func goHome() {
        errorMessage = nil
        webView?.load(URLRequest(url: homeURL))
    }

    func markLoadingStarted() {
        errorMessage = nil
        updateNavigationState()
    }

    func markLoadingFailed(_ error: Error) {
        errorMessage = error.localizedDescription
        updateNavigationState()
    }

    func openInSafari() {
        guard let url = webView?.url ?? Optional(homeURL) else {
            return
        }

        UIApplication.shared.open(url)
    }
}
