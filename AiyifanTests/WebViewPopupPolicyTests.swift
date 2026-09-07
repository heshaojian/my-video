import XCTest
@testable import Aiyifan

final class WebViewPopupPolicyTests: XCTestCase {
    func testPopupNeverReplacesCurrentPlaybackPage() {
        XCTAssertFalse(WebViewPopupPolicy.shouldReplaceCurrentPage)
    }
}
