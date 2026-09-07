import XCTest

final class AiyifanLatestTapTests: XCTestCase {
    private func launchFixtureApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-AiyifanUseFixtureFeed")
        app.launchArguments.append("-AiyifanResetSavedItems")
        app.launch()
        return app
    }

    func testTappingLatestItemOpensBrowser() {
        let app = launchFixtureApp()

        let latestItem = app.buttons["latestItem-fixture-电影"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()

        XCTAssertTrue(app.webViews["browserWebView"].waitForExistence(timeout: 5))
    }

    func testLatestPageContainsOnlyTheFourRequestedSections() {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["最新电影"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["最新电视剧"].exists)

        app.swipeUp()
        app.swipeUp()

        XCTAssertTrue(app.staticTexts["最新综艺"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["最新动漫"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '最新'")).count, 5)
    }

    func testPopupDoesNotReplacePlaybackPage() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-电影"].tap()

        let popupButton = app.webViews.buttons["Open popup"]
        XCTAssertTrue(popupButton.waitForExistence(timeout: 5))
        popupButton.tap()

        XCTAssertTrue(app.webViews.staticTexts["Playback page ready"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Back"].isEnabled)
    }

    func testSavingLatestItemShowsItInSavedTabAndAllowsRemoval() {
        let app = launchFixtureApp()

        let saveButton = app.buttons["saveItem-fixture-电影"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        app.tabBars.buttons["Saved"].tap()

        let savedItem = app.buttons["savedItem-fixture-电影"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))

        let removeButton = app.buttons["removeSavedItem-fixture-电影"]
        XCTAssertTrue(removeButton.exists)
        removeButton.tap()

        XCTAssertFalse(savedItem.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].exists)
    }
}
