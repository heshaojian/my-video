import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var selectedTitle: String?
    @Published var selectedURL: URL?
    @Published var selectedItem: AiyifanItem?
    @Published var selectedCategory: AiyifanCategory?
    @Published var selectedEpisodeKey: String?
    @Published var latestItems: [AiyifanCategory: [AiyifanItem]] = [:]
    @Published var isLoadingLatest = false
    @Published var latestErrorMessage: String?
    @Published var latestStatusMessage: String?
    @Published var lastFeedRefresh: Date?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var estimatedProgress = 0.0
    @Published var hasCommittedContent = false
    @Published var errorMessage: String?

    private let feedRepository: FeedRepository
    weak var webView: WKWebView?

    init(feedRepository: FeedRepository = FeedRepository()) {
        self.feedRepository = feedRepository
    }

    var currentURL: URL? {
        selectedURL
    }

    var isBrowsing: Bool {
        selectedURL != nil
    }

    var isPlaying: Bool {
        selectedItem != nil
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
        selectedItem = nil
        selectedCategory = nil
        selectedEpisodeKey = nil
        errorMessage = nil
        webView = nil
        canGoBack = false
        canGoForward = false
        estimatedProgress = 0.0
        hasCommittedContent = false
    }

    func selectCategory(_ category: AiyifanCategory) {
        selectedTitle = category.title
        selectedURL = nil
        selectedItem = nil
        selectedCategory = category
        selectedEpisodeKey = nil
        errorMessage = nil
    }

    func closeCategory() {
        selectedTitle = nil
        selectedCategory = nil
    }

    func selectItem(_ item: AiyifanItem) {
        selectedTitle = item.title
        selectedURL = nil
        selectedEpisodeKey = nil
        errorMessage = nil
        selectedItem = item
    }

    func selectPlayed(_ record: PlayedRecord) {
        selectedTitle = record.item.title
        selectedURL = nil
        selectedEpisodeKey = record.episodeKey
        errorMessage = nil
        selectedItem = record.item
    }

    func closePlayer() {
        selectedTitle = nil
        selectedItem = nil
        selectedEpisodeKey = nil
    }

    func openWebsiteFallback(for item: AiyifanItem) {
        selectedTitle = item.title
        selectedItem = nil
        selectedEpisodeKey = nil
        selectedURL = item.playURL
        selectedCategory = nil
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

    func loadLatestIfNeeded(force: Bool = false) async {
        guard (force || latestItems.isEmpty), !isLoadingLatest else {
            return
        }

        isLoadingLatest = true
        latestErrorMessage = nil
        latestStatusMessage = nil

        let result = await feedRepository.refresh()
        latestItems = result.items
        latestErrorMessage = result.totalFailureMessage
        latestStatusMessage = result.statusMessage
        lastFeedRefresh = result.refreshedAt

        isLoadingLatest = false
    }

    func clearFeedCache() async {
        await feedRepository.clearCache()
        lastFeedRefresh = nil
        latestStatusMessage = "Feed cache cleared"
    }

    func openDeepLink(_ destination: AiyifanDeepLinkDestination) {
        selectedTitle = destination.item.title
        selectedURL = nil
        selectedItem = destination.item
        selectedCategory = nil
        selectedEpisodeKey = destination.episodeKey
        errorMessage = nil
    }
}
