import XCTest
@testable import MyVideo

final class WebViewPopupPolicyTests: XCTestCase {
    func testPopupNeverReplacesCurrentPlaybackPage() {
        XCTAssertFalse(WebViewPopupPolicy.shouldReplaceCurrentPage)
    }
}
