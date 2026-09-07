import XCTest

@MainActor
final class AiyifanLatestTapTests: XCTestCase {
    private func launchFixtureApp() -> XCUIApplication {
        launchFixtureApp(resetSavedItems: true)
    }

    private func launchFixtureApp(resetSavedItems: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-AiyifanUseFixtureFeed")
        app.launchArguments.append("-AiyifanResetPlayedItems")
        if resetSavedItems {
            app.launchArguments.append("-AiyifanResetSavedItems")
        }
        app.launch()
        return app
    }

    private func launchFixtureAppWithPlayedHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanSeedPlayedItems"
        ]
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

    func testPlayedIsThirdTabAndSeededEpisodeOpensNativePlayer() {
        let app = launchFixtureAppWithPlayedHistory()

        XCTAssertEqual(app.tabBars.buttons.count, 3)
        let playedTab = app.tabBars.buttons["Played"]
        XCTAssertTrue(playedTab.exists)
        playedTab.tap()

        let playedItem = app.buttons["playedItem-fixture-电视剧::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        playedItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Episode 04"].waitForExistence(timeout: 5))
    }

    func testEpisodePickerShowsNewestFirstAndSwitchesEpisode() {
        let app = launchFixtureApp()
        let item = app.buttons["latestItem-fixture-电影"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        let episodesButton = app.buttons["showEpisodes"]
        XCTAssertTrue(episodesButton.waitForExistence(timeout: 5))
        episodesButton.tap()

        let newest = app.buttons["episodeRow-episode-10"]
        let older = app.buttons["episodeRow-episode-2"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newest.frame.minY, older.frame.minY)

        older.tap()
        XCTAssertTrue(app.staticTexts["Episode 02"].waitForExistence(timeout: 5))
    }

    func testAdvertisementIsVisiblyMuted() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-电影"].tap()

        XCTAssertTrue(app.staticTexts["Advertisement · Muted"].waitForExistence(timeout: 5))
    }

    func testPlayedClearAllRequiresConfirmation() {
        let app = launchFixtureAppWithPlayedHistory()
        app.tabBars.buttons["Played"].tap()
        XCTAssertTrue(app.buttons["clearPlayed"].waitForExistence(timeout: 5))

        app.buttons["clearPlayed"].tap()
        XCTAssertTrue(app.alerts["Clear Played History?"].waitForExistence(timeout: 2))
        app.alerts.buttons["Clear All"].tap()

        XCTAssertTrue(app.staticTexts["Nothing played yet"].waitForExistence(timeout: 3))
    }

    func testPlayerOffersAirPlayAndGoogleCastControls() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-电影"].tap()

        XCTAssertTrue(app.buttons["airPlayButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["googleCastButton"].exists)
    }

    func testContinueWatchingAppearsAndResumesSeededEpisode() {
        let app = launchFixtureAppWithPlayedHistory()

        let continueItem = app.buttons["continueItem-fixture-电视剧"]
        XCTAssertTrue(continueItem.waitForExistence(timeout: 5))
        continueItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Episode 04"].waitForExistence(timeout: 5))
    }

    func testNativeSearchAndCategoryFilterNarrowLatestResults() {
        let app = launchFixtureApp()
        let search = app.searchFields["Search latest"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("电视剧")

        XCTAssertTrue(app.buttons["searchItem-fixture-电视剧"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["searchItem-fixture-电影"].exists)

        app.buttons["clearSearch"].tap()
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        }
        app.buttons["filterLatest"].tap()
        app.buttons["filterCategory-动漫"].tap()
        app.buttons["applyFilters"].tap()

        XCTAssertTrue(app.buttons["searchItem-fixture-动漫"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["searchItem-fixture-电视剧"].exists)
    }

    func testPowerUserSessionKeepsNavigationAndCollectionsConsistent() {
        let app = launchFixtureAppWithPlayedHistory()
        let latestItem = app.buttons["latestItem-fixture-电影"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-电影"].tap()

        for _ in 0..<3 {
            latestItem.tap()
            XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Saved"].tap()
        let savedItem = app.buttons["savedItem-fixture-电影"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        savedItem.tap()
        XCTAssertTrue(app.buttons["showEpisodes"].waitForExistence(timeout: 5))
        app.buttons["showEpisodes"].tap()
        app.buttons["episodeRow-episode-2"].tap()
        XCTAssertTrue(app.staticTexts["Episode 02"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()

        app.tabBars.buttons["Played"].tap()
        let playedItem = app.buttons["playedItem-fixture-电视剧::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        playedItem.tap()
        XCTAssertTrue(app.staticTexts["Episode 04"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()

        app.buttons["clearPlayed"].tap()
        XCTAssertTrue(app.alerts["Clear Played History?"].waitForExistence(timeout: 2))
        app.alerts.buttons["Clear All"].tap()
        XCTAssertTrue(app.staticTexts["Nothing played yet"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["savedItem-fixture-电影"].exists)
    }
}
