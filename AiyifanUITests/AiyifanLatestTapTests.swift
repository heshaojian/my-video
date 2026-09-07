import XCTest

@MainActor
final class AiyifanLatestTapTests: XCTestCase {
    private func launchFixtureApp() -> XCUIApplication {
        launchFixtureApp(resetSavedItems: true)
    }

    private func launchFixtureApp(resetSavedItems: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-AiyifanUseFixtureFeed")
        if resetSavedItems {
            app.launchArguments.append("-AiyifanResetSavedItems")
        }
        app.launch()
        return app
    }

    func testTappingLatestItemOpensNativePlayerWithoutBrowser() {
        let app = launchFixtureApp()

        let latestItem = app.buttons["latestItem-fixture-电影"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
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

        let fallbackButton = app.buttons["openWebsiteFallback"]
        XCTAssertTrue(fallbackButton.waitForExistence(timeout: 5))
        fallbackButton.tap()

        let popupButton = app.buttons["Open popup"]
        XCTAssertTrue(popupButton.waitForExistence(timeout: 5))
        popupButton.tap()

        XCTAssertTrue(app.staticTexts["Playback page ready"].waitForExistence(timeout: 2))
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

    func testSavedItemOpensNativePlayerAndSurvivesRelaunch() {
        var app = launchFixtureApp(resetSavedItems: true)
        let saveButton = app.buttons["saveItem-fixture-电影"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        app.terminate()

        app = launchFixtureApp(resetSavedItems: false)
        app.tabBars.buttons["Saved"].tap()
        let savedItem = app.buttons["savedItem-fixture-电影"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        savedItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
    }

    func testPlayerCanBeOpenedClosedAndOpenedAgain() {
        let app = launchFixtureApp()
        let latestItem = app.buttons["latestItem-fixture-电影"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()
        XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
    }

    func testAllCategoryButtonOpensBrowserExplicitly() {
        let app = launchFixtureApp()
        let categoryButton = app.buttons["browseCategory-电影"]
        XCTAssertTrue(categoryButton.waitForExistence(timeout: 5))

        categoryButton.tap()

        XCTAssertTrue(app.webViews["browserWebView"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["nativePlayer"].exists)
    }
}
