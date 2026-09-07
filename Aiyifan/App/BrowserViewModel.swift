import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var selectedTitle: String?
    @Published var selectedURL: URL?
    @Published var latestItems: [AiyifanCategory: [AiyifanItem]] = [:]
    @Published var isLoadingLatest = false
    @Published var latestErrorMessage: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var estimatedProgress = 0.0
    @Published var hasCommittedContent = false
    @Published var errorMessage: String?

    private let feedService = AiyifanFeedService()
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
        hasCommittedContent = false
    }

    func selectCategory(_ category: AiyifanCategory) {
        selectedTitle = category.title
        selectedURL = category.url
        errorMessage = nil
    }

    func selectItem(_ item: AiyifanItem) {
        selectedTitle = item.title
        selectedURL = item.playURL
        errorMessage = nil
    }

    func markLoadingStarted() {
        errorMessage = nil
        hasCommittedContent = false
        updateNavigationState()
    }

    func markContentCommitted() {
        hasCommittedContent = true
        updateNavigationState()
    }

    func markLoadingFailed(_ error: Error) {
        hasCommittedContent = false
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
            let pairs = try await withThrowingTaskGroup(of: (AiyifanCategory, [AiyifanItem]).self) { group in
                for category in AiyifanCategory.allCases {
                    group.addTask { [feedService] in
                        (category, try await feedService.fetchLatest(category: category))
                    }
                }

                var result: [(AiyifanCategory, [AiyifanItem])] = []
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
