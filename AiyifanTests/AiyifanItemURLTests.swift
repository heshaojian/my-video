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
}
