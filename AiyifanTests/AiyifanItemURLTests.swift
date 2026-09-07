import XCTest
@testable import Aiyifan

final class AiyifanItemURLTests: XCTestCase {
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
}
