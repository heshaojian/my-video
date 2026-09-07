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

        XCTAssertTrue(app.images["aiyifanBrandMark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Aiyifan"].exists)
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

    func testAllCategoryButtonOpensNativeCatalogWithoutBrowser() {
        let app = launchFixtureApp()
        let categoryButton = app.buttons["browseCategory-电影"]
        XCTAssertTrue(categoryButton.waitForExistence(timeout: 5))

        categoryButton.tap()

        XCTAssertTrue(app.otherElements["nativeCategoryCatalog-电影"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-电影-1"].exists)
        XCTAssertFalse(app.webViews["browserWebView"].exists)
        XCTAssertFalse(app.otherElements["nativePlayer"].exists)
    }

    func testEveryAllButtonOpensMatchingNativeCatalog() {
        let app = launchFixtureApp()

        for category in ["电影", "电视剧", "综艺", "动漫"] {
            let categoryButton = app.buttons["browseCategory-\(category)"]
            if !categoryButton.exists {
                app.swipeUp()
                app.swipeUp()
            }
            XCTAssertTrue(categoryButton.waitForExistence(timeout: 3))
            categoryButton.tap()
            XCTAssertTrue(app.otherElements["nativeCategoryCatalog-\(category)"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.webViews["browserWebView"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testCatalogItemCanBeSavedAndPlayedNatively() {
        let app = launchFixtureApp()
        app.buttons["browseCategory-电影"].tap()

        let saveButton = app.buttons["saveCatalogItem-fixture-catalog-电影-1"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let item = app.buttons["catalogItem-fixture-catalog-电影-1"]
        XCTAssertTrue(item.exists)
        item.tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
        app.buttons["closeNativePlayer"].tap()

        XCTAssertTrue(app.buttons["closeCategoryCatalog"].waitForExistence(timeout: 5))
        app.buttons["closeCategoryCatalog"].tap()

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["savedItem-fixture-catalog-电影-1"].waitForExistence(timeout: 5))
    }

    func testCatalogSavedItemSurvivesRelaunch() {
        var app = launchFixtureApp(resetSavedItems: true)
        app.buttons["browseCategory-电影"].tap()
        let saveButton = app.buttons["saveCatalogItem-fixture-catalog-电影-1"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        app.terminate()

        app = launchFixtureApp(resetSavedItems: false)
        app.tabBars.buttons["Saved"].tap()

        XCTAssertTrue(app.buttons["savedItem-fixture-catalog-电影-1"].waitForExistence(timeout: 5))
    }

    func testCatalogScrollingLoadsSecondPageWithoutDuplicates() {
        let app = launchFixtureApp()
        app.buttons["browseCategory-电视剧"].tap()

        let secondPageItem = app.buttons["catalogItem-fixture-catalog-电视剧-25"]
        for _ in 0..<8 where !secondPageItem.exists {
            app.swipeUp()
        }

        XCTAssertTrue(secondPageItem.waitForExistence(timeout: 5))
        let endMarker = app.staticTexts["已显示全部"]
        for _ in 0..<4 where !endMarker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(endMarker.waitForExistence(timeout: 3))
    }

    func testCatalogInitialFailureCanRetryWithoutOpeningBrowser() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanFixtureCatalogInitialFailure"
        ]
        app.launch()
        app.buttons["browseCategory-电影"].tap()

        let retry = app.buttons["retryCatalogInitial"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()

        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-电影-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
    }

    func testCatalogLoadMoreFailureCanRetryWithoutLosingItems() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanFixtureCatalogLoadMoreFailure"
        ]
        app.launch()
        app.buttons["browseCategory-电视剧"].tap()

        let retry = app.buttons["retryCatalogLoadMore"]
        for _ in 0..<8 where !retry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-电视剧-24"].exists)
        retry.tap()

        let secondPageItem = app.buttons["catalogItem-fixture-catalog-电视剧-25"]
        for _ in 0..<4 where !secondPageItem.exists {
            app.swipeUp()
        }
        XCTAssertTrue(secondPageItem.waitForExistence(timeout: 5))
    }

    func testPlayedIsThirdTabAndSeededEpisodeOpensNativePlayer() {
        let app = launchFixtureAppWithPlayedHistory()

        XCTAssertEqual(app.tabBars.buttons.count, 3)
        let playedTab = app.tabBars.buttons["Played"]
        XCTAssertTrue(playedTab.exists)
        playedTab.tap()

        let playedItem = app.buttons["playedItem-fixture-电视剧::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        let playedPosition = app.staticTexts["playedPosition-fixture-电视剧::episode-4"]
        XCTAssertEqual(playedPosition.label, "Paused at 00:40 / 01:40")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(playedPosition.label, "Paused at 00:40 / 01:40")
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

    func testAdvertisementIsRemovedFromNativePlayback() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-电影"].tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Advertisement · Muted"].waitForExistence(timeout: 2))
    }

    func testFullscreenRoundTripKeepsNativePlayerSessionAlive() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanUsePlayableFixtureMedia",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems"
        ]
        app.launch()
        app.buttons["latestItem-fixture-电影"].tap()
        let player = app.otherElements["nativePlayer"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))

        let loading = app.activityIndicators["Loading video"]
        if loading.exists {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: loading
            )
            XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 12), .completed)
        }

        player.tap()
        let enterFullScreen = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'full screen'")
        ).firstMatch
        XCTAssertTrue(enterFullScreen.waitForExistence(timeout: 3), app.debugDescription)
        enterFullScreen.tap()

        XCTAssertFalse(app.buttons["closeNativePlayer"].exists)
        app.swipeDown()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
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

    func testSerialPlayerOffersEpisodeContinuityAndPlaybackSettings() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-电视剧"].tap()

        XCTAssertTrue(app.buttons["previousEpisode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nextEpisode"].exists)
        XCTAssertTrue(app.buttons["playbackSettings"].exists)
        XCTAssertTrue(app.buttons["showEpisodes"].exists)
    }

    func testSettingsAreAvailableWithoutAddingAFourthTab() {
        let app = launchFixtureApp()

        XCTAssertTrue(app.buttons["appSettings"].waitForExistence(timeout: 5))
        app.buttons["appSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["updateAlertsToggle"].exists)
        XCTAssertTrue(app.switches["cloudSyncToggle"].exists)
        XCTAssertTrue(app.buttons["clearFeedCache"].exists)
    }

    func testSimulatedCastSessionOffersPersistentAndExpandedControls() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanSimulateCastSession"
        ]
        app.launch()

        let miniController = app.otherElements["castMiniController"]
        XCTAssertTrue(miniController.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Living Room TV"].exists)
        app.buttons["expandCastController"].tap()

        XCTAssertTrue(app.otherElements["castExpandedController"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["toggleCastPlayback"].exists)
        XCTAssertTrue(app.buttons["skipCastBackward"].exists)
        XCTAssertTrue(app.buttons["skipCastForward"].exists)
        XCTAssertTrue(app.buttons["toggleCastMute"].exists)

        app.buttons["toggleCastPlayback"].tap()
        XCTAssertEqual(app.buttons["toggleCastPlayback"].label, "Pause Cast")
        app.buttons["skipCastForward"].tap()
        app.buttons["toggleCastMute"].tap()
        XCTAssertEqual(app.buttons["toggleCastMute"].label, "Unmute Cast")

        app.buttons["stopCasting"].tap()
        XCTAssertFalse(miniController.waitForExistence(timeout: 2))
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

    func testFiftyActionHeavyUserSessionRemainsConsistent() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanSeedPlayedItems",
            "-AiyifanSimulateCastSession"
        ]
        app.launch()

        let latestItem = app.buttons["latestItem-fixture-电影"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-电影"].tap()

        for _ in 0..<5 {
            latestItem.tap()
            XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Saved"].tap()
        let savedItem = app.buttons["savedItem-fixture-电影"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            savedItem.tap()
            XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Played"].tap()
        let playedItem = app.buttons["playedItem-fixture-电视剧::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            playedItem.tap()
            XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Latest"].tap()
        app.buttons["expandCastController"].tap()
        XCTAssertTrue(app.otherElements["castExpandedController"].waitForExistence(timeout: 3))
        for _ in 0..<10 {
            app.buttons["toggleCastPlayback"].tap()
        }
        for _ in 0..<5 {
            app.buttons["skipCastForward"].tap()
        }
        for _ in 0..<5 {
            app.buttons["skipCastBackward"].tap()
        }
        app.buttons["toggleCastMute"].tap()
        app.buttons["toggleCastMute"].tap()
        app.buttons["Done"].tap()

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(savedItem.exists)
        app.tabBars.buttons["Played"].tap()
        XCTAssertTrue(playedItem.exists)
        app.tabBars.buttons["Latest"].tap()
        XCTAssertTrue(latestItem.exists)
        XCTAssertTrue(app.otherElements["castMiniController"].exists)

        app.buttons["browseCategory-电影"].tap()
        let catalogItem = app.buttons["catalogItem-fixture-catalog-电影-25"]
        for _ in 0..<8 where !catalogItem.exists {
            app.swipeUp()
        }
        XCTAssertTrue(catalogItem.waitForExistence(timeout: 5))
        app.buttons["saveCatalogItem-fixture-catalog-电影-25"].tap()
        catalogItem.tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()
        XCTAssertTrue(app.buttons["closeCategoryCatalog"].waitForExistence(timeout: 5))
        app.buttons["closeCategoryCatalog"].tap()

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["savedItem-fixture-catalog-电影-25"].waitForExistence(timeout: 5))
    }
}
