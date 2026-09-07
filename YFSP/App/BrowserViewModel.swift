import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var selectedCategory: YfspCategory?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var estimatedProgress = 0.0
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    var currentURL: URL? {
        selectedCategory?.url
    }

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
        selectedCategory = nil
        errorMessage = nil
        webView = nil
        canGoBack = false
        canGoForward = false
        estimatedProgress = 0.0
    }

    func selectCategory(_ category: YfspCategory) {
        selectedCategory = category
        errorMessage = nil
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
        guard let url = webView?.url ?? currentURL else {
            return
        }

        UIApplication.shared.open(url)
    }
}
