import XCTest
import SwiftUI
import UIKit
@testable import Aiyifan

final class AiyifanItemURLTests: XCTestCase {
    @MainActor
    func testLibraryChromeTextMeetsContrastOnDarkBackground() {
        let background = RGBAColor(LibraryScreenChrome.background)
        let primary = RGBAColor(LibraryScreenChrome.primaryText)
        let secondary = RGBAColor(LibraryScreenChrome.secondaryText, compositedOver: background)

        XCTAssertGreaterThanOrEqual(primary.contrastRatio(with: background), 7.0)
        XCTAssertGreaterThanOrEqual(secondary.contrastRatio(with: background), 4.5)
    }

    @MainActor
    func testPosterArtworkContainerKeepsUniformFrameForWideAndTallArtwork() throws {
        let wideSize = try renderedPosterSize(
            content: Color.red.frame(width: 900, height: 100)
        )
        let tallSize = try renderedPosterSize(
            content: Color.blue.frame(width: 100, height: 900)
        )

        XCTAssertEqual(wideSize.width, 144, accuracy: 0.5)
        XCTAssertEqual(wideSize.height, 200, accuracy: 0.5)
        XCTAssertEqual(tallSize.width, wideSize.width, accuracy: 0.5)
        XCTAssertEqual(tallSize.height, wideSize.height, accuracy: 0.5)
    }

    func testPlayURLUsesExplicitRelativePlayPath() {
        let item = AiyifanItem(
            listPath: "ignored",
            title: "Drama",
            url: "/play/drama-media-key"
        )

        XCTAssertEqual(item.playURL.absoluteString, "https://m.yfsp.tv/play/drama-media-key")
    }

    func testPlayURLUsesRawMediaKeyWhenNoURLIsPresent() {
        let item = AiyifanItem(listPath: "raw-media-key", title: "Movie")

        XCTAssertEqual(item.playURL.absoluteString, "https://m.yfsp.tv/play/raw-media-key")
    }

    func testThumbnailURLNormalizesProtocolRelativeImageURL() {
        let item = AiyifanItem(
            listPath: "raw-media-key",
            title: "Movie",
            verticalImg: "//static.yfsp.tv/poster.jpg"
        )

        XCTAssertEqual(item.thumbnailURL?.absoluteString, "https://static.yfsp.tv/poster.jpg")
    }

    func testPosterImageRequestUsesProviderCompatibleHeaders() throws {
        let url = try XCTUnwrap(URL(string: "https://static.yfsp.tv/poster.jpg"))

        let request = try PosterImageLoader.makeRequest(for: url)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://m.yfsp.tv/")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("iPhone") == true)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
    }

    func testPosterImageRequestRejectsUnsupportedArtworkHost() throws {
        let url = try XCTUnwrap(URL(string: "https://attacker.invalid/poster.jpg"))

        XCTAssertThrowsError(try PosterImageLoader.makeRequest(for: url))
    }

    @MainActor
    func testPosterImageLoaderRetriesTransientFailureAndCachesImage() async throws {
        PosterImageLoader.resetCache()
        PosterImageURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/retry-poster.png"))
        let imageData = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))
        let requestCounter = LockedCounter()
        PosterImageURLProtocol.setHandler { request in
            let requestCount = requestCounter.increment()
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://m.yfsp.tv/")
            let statusCode = requestCount == 1 ? 503 : 200
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url ?? url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, imageData)
        }
        let session = Self.makePosterImageTestSession()
        let loader = PosterImageLoader(session: session)

        await loader.load(from: url)

        XCTAssertEqual(requestCounter.value, 2)
        XCTAssertNotNil(loader.image)
        XCTAssertNotNil(PosterImageLoader.cachedImage(for: url))
    }

    @MainActor
    func testPosterImageLoaderUsesCachedImageWithoutNetworkRequest() async throws {
        PosterImageLoader.resetCache()
        PosterImageURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/cached-poster.png"))
        let cachedImage = try XCTUnwrap(UIImage(data: try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))))
        let requestCounter = LockedCounter()
        PosterImageLoader.store(cachedImage, for: url)
        PosterImageURLProtocol.setHandler { request in
            _ = requestCounter.increment()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url ?? url,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let loader = PosterImageLoader(session: Self.makePosterImageTestSession())

        await loader.load(from: url)

        XCTAssertEqual(requestCounter.value, 0)
        XCTAssertEqual(loader.image?.pngData(), cachedImage.pngData())
    }

    @MainActor
    func testPosterImageLoaderDoesNotRetryPermanentHTTPFailure() async throws {
        PosterImageLoader.resetCache()
        PosterImageURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/not-found.png"))
        let requestCounter = LockedCounter()
        PosterImageURLProtocol.setHandler { request in
            _ = requestCounter.increment()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url ?? url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let loader = PosterImageLoader(session: Self.makePosterImageTestSession())

        await loader.load(from: url)

        XCTAssertEqual(requestCounter.value, 1)
        XCTAssertNil(loader.image)
        XCTAssertNil(PosterImageLoader.cachedImage(for: url))
    }

    @MainActor
    func testPosterImageLoaderRejectsInvalidImageDataWithoutCaching() async throws {
        PosterImageLoader.resetCache()
        PosterImageURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/broken-poster.png"))
        let requestCounter = LockedCounter()
        PosterImageURLProtocol.setHandler { request in
            _ = requestCounter.increment()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url ?? url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, Data("not an image".utf8))
        }
        let loader = PosterImageLoader(session: Self.makePosterImageTestSession())

        await loader.load(from: url)

        XCTAssertEqual(requestCounter.value, 1)
        XCTAssertNil(loader.image)
        XCTAssertNil(PosterImageLoader.cachedImage(for: url))
    }

    @MainActor
    func testPosterImageLoaderClearsExistingImageWhenURLBecomesNil() async throws {
        PosterImageLoader.resetCache()
        PosterImageURLProtocol.reset()
        let url = try XCTUnwrap(URL(string: "https://images.example.com/initial-poster.png"))
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(Data(base64Encoded: Self.onePixelPNGBase64))))
        PosterImageLoader.store(image, for: url)
        let loader = PosterImageLoader(session: Self.makePosterImageTestSession())

        await loader.load(from: url)
        XCTAssertNotNil(loader.image)

        await loader.load(from: nil)

        XCTAssertNil(loader.image)
    }

    @MainActor
    func testSelectingItemRoutesToNativePlayerWithoutOpeningBrowser() {
        let item = AiyifanItem(
            listPath: "native-media-key",
            title: "Native Movie"
        )
        let viewModel = BrowserViewModel()

        viewModel.selectItem(item)

        XCTAssertEqual(viewModel.selectedItem, item)
        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertFalse(viewModel.isBrowsing)
        XCTAssertNil(viewModel.selectedURL)
    }

    @MainActor
    func testSelectingCategoryRoutesToNativeCatalogWithoutOpeningBrowser() {
        let viewModel = BrowserViewModel()

        viewModel.selectCategory(.drama)

        XCTAssertEqual(viewModel.selectedCategory, .drama)
        XCTAssertFalse(viewModel.isBrowsing)
        XCTAssertNil(viewModel.selectedURL)
        XCTAssertNil(viewModel.selectedItem)
    }

    @MainActor
    func testWebsiteFallbackRequiresExplicitStateTransition() {
        let item = AiyifanItem(
            listPath: "fallback-media-key",
            title: "Fallback Movie",
            url: "/play/fallback-media-key"
        )
        let viewModel = BrowserViewModel()
        viewModel.selectItem(item)

        viewModel.openWebsiteFallback(for: item)

        XCTAssertNil(viewModel.selectedItem)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.isBrowsing)
        XCTAssertEqual(viewModel.selectedURL, item.playURL)
    }

    @MainActor
    func testWebsiteFallbackRejectsUnsafeProviderURLValues() {
        let unsafeURLs = [
            "http://m.yfsp.tv/play/media-key",
            "https://example.com/play/media-key",
            "https://user:password@m.yfsp.tv/play/media-key",
            "https://m.yfsp.tv:8443/play/media-key",
            "data:text/html,<script>alert(1)</script>",
            "about:blank"
        ]

        for unsafeURL in unsafeURLs {
            let item = AiyifanItem(
                listPath: "safe-media-key",
                title: "Fallback Movie",
                url: unsafeURL
            )
            let viewModel = BrowserViewModel()

            viewModel.openWebsiteFallback(for: item)

            XCTAssertNil(viewModel.selectedURL)
            XCTAssertEqual(viewModel.errorMessage, "Website fallback is unavailable for this address.")
        }
    }

    private static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="

    private static func makePosterImageTestSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PosterImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @MainActor
    private func renderedPosterSize<Content: View>(content: Content) throws -> CGSize {
        let renderer = ImageRenderer(
            content: PosterArtworkContainer { content }
                .frame(width: 144)
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage).size
    }
}

private struct RGBAColor {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    @MainActor
    init(_ color: Color) {
        let uiColor = UIColor(color)
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var alpha = CGFloat.zero
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.alpha = Double(alpha)
    }

    @MainActor
    init(_ color: Color, compositedOver background: RGBAColor) {
        let foreground = RGBAColor(color)
        red = foreground.red * foreground.alpha + background.red * (1 - foreground.alpha)
        green = foreground.green * foreground.alpha + background.green * (1 - foreground.alpha)
        blue = foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha)
        alpha = 1
    }

    func contrastRatio(with other: RGBAColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ value: Double) -> Double {
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock {
            count
        }
    }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class PosterImageURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func setHandler(_ newHandler: @escaping Handler) {
        lock.withLock {
            handler = newHandler
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.lock.withLock({ Self.handler }) else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
