import XCTest
@testable import Aiyifan

final class WebViewLoadTrackerTests: XCTestCase {
    func testSelectedURLLoadsOnlyOnceAcrossRedirectedWebViewUpdates() {
        var tracker = WebViewLoadTracker()
        let selectedURL = URL(string: "https://m.yfsp.tv/play/media-key")!

        XCTAssertTrue(tracker.shouldLoad(selectedURL))
        XCTAssertFalse(tracker.shouldLoad(selectedURL))
    }

    func testNewSelectionStillLoads() {
        var tracker = WebViewLoadTracker()
        let firstURL = URL(string: "https://m.yfsp.tv/play/first")!
        let secondURL = URL(string: "https://m.yfsp.tv/play/second")!

        XCTAssertTrue(tracker.shouldLoad(firstURL))
        XCTAssertTrue(tracker.shouldLoad(secondURL))
    }
}
