import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var selectedTitle: String?
    @Published var selectedURL: URL?
    @Published var latestItems: [YfspCategory: [YfspItem]] = [:]
    @Published var isLoadingLatest = false
    @Published var latestErrorMessage: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var estimatedProgress = 0.0
    @Published var errorMessage: String?

    private let feedService = YfspFeedService()
    weak var webView: WKWebView?

    var currentURL: URL? {
        selectedURL
    }

    var isBrowsing: Bool {
        selectedURL != nil
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
        selectedTitle = nil
        selectedURL = nil
        errorMessage = nil
        webView = nil
        canGoBack = false
        canGoForward = false
        estimatedProgress = 0.0
    }

    func selectCategory(_ category: YfspCategory) {
        selectedTitle = category.title
        selectedURL = category.url
        errorMessage = nil
    }

    func selectItem(_ item: YfspItem) {
        selectedTitle = item.title
        selectedURL = item.playURL
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

    func loadLatestIfNeeded() async {
        guard latestItems.isEmpty, !isLoadingLatest else {
            return
        }

        isLoadingLatest = true
        latestErrorMessage = nil

        do {
            let pairs = try await withThrowingTaskGroup(of: (YfspCategory, [YfspItem]).self) { group in
                for category in YfspCategory.allCases {
                    group.addTask { [feedService] in
                        (category, try await feedService.fetchLatest(category: category))
                    }
                }

                var result: [(YfspCategory, [YfspItem])] = []
                for try await pair in group {
                    result.append(pair)
                }
                return result
            }

            latestItems = Dictionary(uniqueKeysWithValues: pairs)
        } catch {
            latestErrorMessage = error.localizedDescription
        }

        isLoadingLatest = false
    }
}
