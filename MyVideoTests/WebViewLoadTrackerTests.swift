import XCTest
@testable import MyVideo

final class WebViewLoadTrackerTests: XCTestCase {
    func testProviderWebURLPolicyAllowsOnlySecureProviderPages() throws {
        XCTAssertTrue(ProviderWebURLPolicy.isAllowed(try XCTUnwrap(URL(string: "https://m.yfsp.tv/play/media-key"))))
        XCTAssertTrue(ProviderWebURLPolicy.isAllowed(try XCTUnwrap(URL(string: "https://www.aiyifan.tv/play/media-key"))))

        let rejected = [
            "http://m.yfsp.tv/play/media-key",
            "https://example.com/play/media-key",
            "https://user:password@m.yfsp.tv/play/media-key",
            "https://m.yfsp.tv:8443/play/media-key",
            "data:text/html,unsafe",
            "about:blank"
        ]
        for rawURL in rejected {
            XCTAssertFalse(ProviderWebURLPolicy.isAllowed(try XCTUnwrap(URL(string: rawURL))))
        }
    }

#if DEBUG
    func testProviderWebURLPolicyAllowsDataOnlyForFixtureFeedLaunches() throws {
        let fixtureURL = try XCTUnwrap(URL(string: "data:text/html,fixture"))

        XCTAssertFalse(ProviderWebURLPolicy.isAllowed(fixtureURL, processArguments: []))
        XCTAssertTrue(
            ProviderWebURLPolicy.isAllowed(
                fixtureURL,
                processArguments: ["MyVideo", "-MyVideoUseFixtureFeed"]
            )
        )
    }
#endif

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
