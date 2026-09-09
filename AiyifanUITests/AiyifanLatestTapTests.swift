import XCTest

@MainActor
final class AiyifanLatestTapTests: XCTestCase {
    private func launchFixtureApp() -> XCUIApplication {
        launchFixtureApp(resetSavedItems: true, resetCatalogPreferences: true)
    }

    private func launchFixtureApp(
        resetSavedItems: Bool,
        resetCatalogPreferences: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-AiyifanUseFixtureFeed")
        app.launchArguments.append("-AiyifanResetPlayedItems")
        if resetCatalogPreferences {
            app.launchArguments.append("-AiyifanResetCatalogPreferences")
        }
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
            "-AiyifanResetCatalogPreferences",
            "-AiyifanSeedPlayedItems"
        ]
        app.launch()
        return app
    }

    func testTappingLatestItemOpensNativePlayerWithoutBrowser() {
        let app = launchFixtureApp()

        let latestItem = app.buttons["latestItem-fixture-movie"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
    }

    func testHomePageContainsOnlyTheFourRequestedSections() {
        let app = launchFixtureApp()

        XCTAssertTrue(app.images["homeScreenTitle-brandMark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Aiyifan"].exists)
        XCTAssertTrue(app.staticTexts["Home"].exists)
        XCTAssertTrue(app.staticTexts["homeScreenTitle"].exists)
        XCTAssertTrue(app.images["homeScreenTitle-brandMark"].exists)
        XCTAssertFalse(app.textFields["providerSearchField"].exists)
        XCTAssertTrue(app.buttons["showSearch"].exists)
        XCTAssertTrue(app.staticTexts["Latest Movies"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Latest Series"].exists)
        XCTAssertTrue(app.staticTexts["latestScore-fixture-movie"].exists)

        app.swipeUp()
        app.swipeUp()

        XCTAssertTrue(app.staticTexts["Latest Variety"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Latest Anime"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Latest'")).count, 4)
    }

    func testPopupDoesNotReplacePlaybackPage() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-movie"].tap()

        app.buttons["playbackSettings"].tap()
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

        let saveButton = app.buttons["saveItem-fixture-movie"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        app.tabBars.buttons["Saved"].tap()

        let savedItem = app.buttons["savedItem-fixture-movie"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))

        let removeButton = app.buttons["removeSavedItem-fixture-movie"]
        XCTAssertTrue(removeButton.exists)
        removeButton.tap()

        XCTAssertFalse(savedItem.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].exists)
    }

    func testLibraryTabTitlesRemainVisibleInDarkTheme() {
        let app = launchFixtureAppWithPlayedHistory()
        XCTAssertTrue(app.buttons["saveItem-fixture-movie"].waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-movie"].tap()

        let homeTitle = app.staticTexts["homeScreenTitle"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 5))
        let homeTitleTop = homeTitle.frame.minY

        app.tabBars.buttons["Saved"].tap()
        let savedTitle = app.staticTexts["savedScreenTitle"]
        let savedBrandMark = app.images["savedScreenTitle-brandMark"]
        XCTAssertTrue(savedTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(savedBrandMark.exists)
        XCTAssertGreaterThan(savedTitle.frame.width, 40)
        XCTAssertGreaterThan(savedTitle.frame.height, 20)
        XCTAssertLessThan(abs(savedTitle.frame.midY - savedBrandMark.frame.midY), 20)
        XCTAssertEqual(savedTitle.frame.minY, homeTitleTop, accuracy: 2)

        app.tabBars.buttons["Played"].tap()
        let playedTitle = app.staticTexts["playedScreenTitle"]
        let playedBrandMark = app.images["playedScreenTitle-brandMark"]
        XCTAssertTrue(playedTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(playedBrandMark.exists)
        XCTAssertGreaterThan(playedTitle.frame.width, 40)
        XCTAssertGreaterThan(playedTitle.frame.height, 20)
        XCTAssertLessThan(abs(playedTitle.frame.midY - playedBrandMark.frame.midY), 20)
        XCTAssertEqual(playedTitle.frame.minY, homeTitleTop, accuracy: 2)
    }

    func testSavedGridKeepsAdjacentCardsInUniformNonOverlappingColumns() {
        let app = launchFixtureApp()
        XCTAssertTrue(app.buttons["saveItem-fixture-movie"].waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-movie"].tap()
        app.buttons["saveItem-fixture-drama"].tap()
        app.tabBars.buttons["Saved"].tap()

        let movie = app.buttons["savedItem-fixture-movie"]
        let drama = app.buttons["savedItem-fixture-drama"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        XCTAssertTrue(drama.exists)
        XCTAssertEqual(movie.frame.width, drama.frame.width, accuracy: 0.5)

        let left = movie.frame.minX < drama.frame.minX ? movie.frame : drama.frame
        let right = movie.frame.minX < drama.frame.minX ? drama.frame : movie.frame
        XCTAssertLessThan(left.maxX, right.minX)
    }

    func testSavedGridCanScrollClearOfFloatingTabBar() {
        let app = launchFixtureApp()
        XCTAssertTrue(app.buttons["saveItem-fixture-movie"].waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-movie"].tap()
        app.buttons["saveItem-fixture-drama"].tap()
        app.tabBars.buttons["Saved"].tap()

        let lowerCard = app.buttons["savedItem-fixture-drama"]
        XCTAssertTrue(lowerCard.waitForExistence(timeout: 5))

        assertCanScrollClearOfTabBar(lowerCard, in: app)
    }

    func testSavedItemOpensNativePlayerAndSurvivesRelaunch() {
        var app = launchFixtureApp(resetSavedItems: true)
        let saveButton = app.buttons["saveItem-fixture-movie"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        app.terminate()

        app = launchFixtureApp(resetSavedItems: false)
        app.tabBars.buttons["Saved"].tap()
        let savedItem = app.buttons["savedItem-fixture-movie"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        savedItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
    }

    func testPlayerCanBeOpenedClosedAndOpenedAgain() {
        let app = launchFixtureApp()
        let latestItem = app.buttons["latestItem-fixture-movie"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()
        XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
    }

    func testBackCollapsesPlaybackAndKeepsNavigationAvailable() {
        let app = launchFixtureApp()
        let latestItem = app.buttons["latestItem-fixture-movie"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))

        latestItem.tap()
        XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()

        XCTAssertTrue(app.otherElements["nativeMiniPlayer"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.otherElements["nativeMiniPlayer"].exists)
        app.buttons["expandMiniPlayer"].tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()
        app.buttons["closeMiniPlayer"].tap()
        XCTAssertFalse(app.otherElements["nativeMiniPlayer"].exists)
    }

    func testAllCategoryButtonOpensNativeCatalogWithoutBrowser() {
        let app = launchFixtureApp()
        let categoryButton = app.buttons["browseCategory-movie"]
        XCTAssertTrue(categoryButton.waitForExistence(timeout: 5))

        categoryButton.tap()

        XCTAssertTrue(app.otherElements["nativeCategoryCatalog-movie"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-movie-1"].exists)
        XCTAssertFalse(app.webViews["browserWebView"].exists)
        XCTAssertFalse(app.otherElements["nativePlayer"].exists)
    }

    func testEveryAllButtonOpensMatchingNativeCatalog() {
        let app = launchFixtureApp()

        for category in ["movie", "drama", "variety", "anime"] {
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
        app.buttons["browseCategory-movie"].tap()

        let saveButton = app.buttons["saveCatalogItem-fixture-catalog-movie-1"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let item = app.buttons["catalogItem-fixture-catalog-movie-1"]
        XCTAssertTrue(item.exists)
        item.tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
        app.buttons["closeNativePlayer"].tap()

        XCTAssertTrue(app.buttons["closeCategoryCatalog"].waitForExistence(timeout: 5))
        app.buttons["closeCategoryCatalog"].tap()

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["savedItem-fixture-catalog-movie-1"].waitForExistence(timeout: 5))
    }

    func testCatalogGridKeepsRightColumnSaveActionInsideItsCard() {
        let app = launchFixtureApp()
        app.buttons["browseCategory-variety"].tap()

        for index in 1...2 {
            let item = app.buttons["catalogItem-fixture-catalog-variety-\(index)"]
            let save = app.buttons["saveCatalogItem-fixture-catalog-variety-\(index)"]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertTrue(save.isHittable)
            XCTAssertGreaterThanOrEqual(save.frame.minX, item.frame.minX - 1)
            XCTAssertLessThanOrEqual(save.frame.maxX, item.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(save.frame.minY, item.frame.minY - 1)
            XCTAssertLessThanOrEqual(save.frame.maxY, item.frame.maxY + 1)
        }
    }

    func testCatalogSavedItemSurvivesRelaunch() {
        var app = launchFixtureApp(resetSavedItems: true)
        app.buttons["browseCategory-movie"].tap()
        let saveButton = app.buttons["saveCatalogItem-fixture-catalog-movie-1"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        app.terminate()

        app = launchFixtureApp(resetSavedItems: false)
        app.tabBars.buttons["Saved"].tap()

        XCTAssertTrue(app.buttons["savedItem-fixture-catalog-movie-1"].waitForExistence(timeout: 5))
    }

    func testCatalogScrollingLoadsSecondPageWithoutDuplicates() {
        let app = launchFixtureApp()
        app.buttons["browseCategory-drama"].tap()

        let secondPageItem = app.buttons["catalogItem-fixture-catalog-drama-25"]
        for _ in 0..<8 where !secondPageItem.exists {
            app.swipeUp()
        }

        XCTAssertTrue(secondPageItem.waitForExistence(timeout: 5))
        let endMarker = app.staticTexts["All results shown"]
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
            "-AiyifanResetCatalogPreferences",
            "-AiyifanFixtureCatalogInitialFailure"
        ]
        app.launch()
        app.buttons["browseCategory-movie"].tap()

        let retry = app.buttons["retryCatalogInitial"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()

        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-movie-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews["browserWebView"].exists)
    }

    func testCatalogLoadMoreFailureCanRetryWithoutLosingItems() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanResetCatalogPreferences",
            "-AiyifanFixtureCatalogLoadMoreFailure"
        ]
        app.launch()
        app.buttons["browseCategory-drama"].tap()

        let retry = app.buttons["retryCatalogLoadMore"]
        for _ in 0..<8 where !retry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 5))

        let firstPageItem = app.buttons["catalogItem-fixture-catalog-drama-1"]
        for _ in 0..<8 where !firstPageItem.exists {
            app.swipeDown()
        }
        XCTAssertTrue(firstPageItem.waitForExistence(timeout: 3))
        for _ in 0..<8 where !retry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        retry.tap()

        let secondPageItem = app.buttons["catalogItem-fixture-catalog-drama-25"]
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

        let playedItem = app.buttons["playedItem-fixture-drama::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        let playedPosition = app.staticTexts["playedPosition-fixture-drama::episode-4"]
        XCTAssertEqual(playedPosition.label, "Paused at 00:40 / 01:40")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(playedPosition.label, "Paused at 00:40 / 01:40")
        playedItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        let episodeControl = app.buttons["showEpisodes"]
        XCTAssertTrue(episodeControl.waitForExistence(timeout: 5))
        XCTAssertTrue(episodeControl.label.contains("4"))
    }

    func testSavedPageShowsReadyToWatchAboveUnchangedSavedGridAndPlaysExactEpisode() {
        let app = launchFixtureAppWithPlayedHistory()
        XCTAssertTrue(app.buttons["saveItem-fixture-drama"].waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-drama"].tap()
        app.tabBars.buttons["Saved"].tap()

        let readyHeading = app.staticTexts["readyToWatchHeading"]
        let allSavedHeading = app.staticTexts["allSavedHeading"]
        XCTAssertTrue(readyHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(allSavedHeading.exists)
        XCTAssertLessThan(readyHeading.frame.minY, allSavedHeading.frame.minY)
        XCTAssertTrue(app.buttons["savedItem-fixture-drama"].exists)

        let readyItem = app.buttons["readyItem-fixture-drama"]
        XCTAssertTrue(readyItem.exists)
        readyItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["showEpisodes"].label.contains("4/10"))
    }

    private func assertCanScrollClearOfTabBar(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tabBar = app.tabBars.element
        XCTAssertTrue(tabBar.exists, file: file, line: line)

        for _ in 0..<5 where element.frame.maxY > tabBar.frame.minY - 12 {
            app.swipeUp()
        }

        XCTAssertLessThanOrEqual(element.frame.maxY, tabBar.frame.minY - 12, file: file, line: line)
    }

    func testReadyQueueMenuActionsUpdateVisibleEntries() {
        let app = launchFixtureAppWithPlayedHistory()
        XCTAssertTrue(app.buttons["saveItem-fixture-movie"].waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-movie"].tap()
        app.buttons["saveItem-fixture-drama"].tap()
        app.tabBars.buttons["Saved"].tap()

        let savedMovie = app.buttons["savedItem-fixture-movie"]
        XCTAssertTrue(savedMovie.waitForExistence(timeout: 5))
        savedMovie.press(forDuration: 1)
        let addToReady = app.buttons["Add to Ready to Watch"]
        XCTAssertTrue(addToReady.waitForExistence(timeout: 3))
        addToReady.tap()

        let seeAll = app.buttons["readyToWatchSeeAll"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 3))
        seeAll.tap()
        XCTAssertTrue(app.descendants(matching: .any)["readyToWatchQueue"].waitForExistence(timeout: 3))

        let automaticDrama = app.buttons["readyQueueItem-fixture-drama"]
        let manualMovie = app.buttons["readyQueueItem-fixture-movie"]
        XCTAssertTrue(automaticDrama.waitForExistence(timeout: 3))
        XCTAssertTrue(manualMovie.exists)

        app.buttons["readyOptions-fixture-drama"].tap()
        app.buttons["Mark Watched"].tap()
        XCTAssertFalse(app.buttons["readyQueueItem-fixture-drama"].waitForExistence(timeout: 1))

        app.buttons["readyOptions-fixture-movie"].tap()
        app.buttons["Remove from Up Next"].tap()
        XCTAssertFalse(app.buttons["readyQueueItem-fixture-movie"].waitForExistence(timeout: 1))
    }

    func testEpisodePickerShowsNewestFirstAndSwitchesEpisode() {
        let app = launchFixtureApp()
        let item = app.buttons["latestItem-fixture-drama"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        let episodesButton = app.buttons["showEpisodes"]
        XCTAssertTrue(episodesButton.waitForExistence(timeout: 5))
        XCTAssertTrue(episodesButton.label.contains("10/10"))
        episodesButton.tap()

        let newest = app.buttons["episodeRow-episode-10"]
        let older = app.buttons["episodeRow-episode-2"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertTrue(older.exists)
        XCTAssertLessThan(newest.frame.minY, older.frame.minY)

        older.tap()
        XCTAssertTrue(app.buttons["showEpisodes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["showEpisodes"].label.contains("2/10"))
    }

    func testAdvertisementIsRemovedFromNativePlayback() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-movie"].tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Advertisement · Muted"].waitForExistence(timeout: 2))
    }

    func testFullscreenRoundTripKeepsNativePlayerSessionAlive() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanUsePlayableFixtureMedia",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanResetCatalogPreferences"
        ]
        app.launch()
        app.buttons["latestItem-fixture-movie"].tap()
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

        XCTAssertFalse(app.buttons["enterFullScreen"].exists)
        player.tap()
        let enterFullScreen = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'full screen'")
        ).firstMatch
        XCTAssertTrue(enterFullScreen.waitForExistence(timeout: 3), app.debugDescription)
        enterFullScreen.tap()

        XCTAssertFalse(app.buttons["enterFullScreen"].exists)
        XCTAssertFalse(app.buttons["exitFullScreen"].exists)
        XCTAssertFalse(app.buttons["exitFullScreen"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["closeNativePlayer"].isHittable)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let nativeExit = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label CONTAINS[c] %@", "Close", "full screen")
        ).firstMatch
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 5), app.debugDescription)
        nativeExit.tap()

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

    func testPlayerKeepsAppSpecificControlsOutsideNativePlaybackChrome() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-movie"].tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["closeNativePlayer"].exists)
        XCTAssertTrue(app.buttons["googleCastButton"].exists)
        XCTAssertTrue(app.buttons["playbackSettings"].exists)
        XCTAssertFalse(app.buttons["airPlayButton"].exists)
        XCTAssertEqual(app.otherElements["viewerMetric-likes"].label, "76 Likes")
        XCTAssertEqual(app.otherElements["viewerMetric-favorites"].label, "221 Favorites")
        XCTAssertEqual(app.otherElements["viewerMetric-score"].label, "9.6 Score")
        XCTAssertEqual(app.otherElements["viewerMetric-views"].label, "170K Views")
    }

    func testSerialPlayerOffersEpisodeContinuityAndPlaybackSettings() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-drama"].tap()

        XCTAssertTrue(app.buttons["showEpisodes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["googleCastButton"].exists)
        let more = app.buttons["playbackSettings"]
        XCTAssertTrue(more.exists)
        XCTAssertEqual(app.buttons["showEpisodes"].frame.midY, more.frame.midY, accuracy: 2)
        XCTAssertFalse(app.buttons["airPlayButton"].exists)
        XCTAssertFalse(app.buttons["previousEpisode"].exists)
        XCTAssertFalse(app.buttons["nextEpisode"].exists)
        XCTAssertFalse(app.sliders["playbackTimeline"].exists)
        XCTAssertFalse(app.buttons["enterFullScreen"].exists)
        XCTAssertFalse(app.buttons["skipBackward10Seconds"].exists)
        XCTAssertFalse(app.buttons["toggleNativePlayback"].exists)
        XCTAssertFalse(app.buttons["skipForward10Seconds"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "More")).count, 1)

        more.tap()
        XCTAssertTrue(app.buttons["playbackQuality"].waitForExistence(timeout: 2))
    }

    func testCatalogOffersProviderFiltersSortAndResultCount() {
        let app = launchFixtureApp()
        app.buttons["browseCategory-drama"].tap()

        XCTAssertTrue(app.buttons["catalogFilter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalogSort"].exists)
        XCTAssertEqual(app.staticTexts["catalogResultCount"].label, "30 results")

        app.buttons["catalogFilter"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["applyCatalogFilters"].exists)
        XCTAssertTrue(app.buttons["resetCatalogFilters"].exists)
        XCTAssertTrue(app.buttons["cancelCatalogFilters"].exists)

        app.buttons["catalogFilter-Language"].tap()
        XCTAssertTrue(app.buttons["英语"].waitForExistence(timeout: 2))
        app.buttons["英语"].tap()
        app.buttons["applyCatalogFilters"].tap()

        XCTAssertTrue(app.buttons["catalogFilter"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["catalogFilter"].value as? String, "1 selected")
        XCTAssertTrue(app.staticTexts["15 results"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-drama-2"].exists)
        XCTAssertFalse(app.buttons["catalogItem-fixture-catalog-drama-1"].exists)

        app.buttons["catalogSort"].tap()
        XCTAssertTrue(app.buttons["catalogSort-3"].waitForExistence(timeout: 2))
        app.buttons["catalogSort-3"].tap()
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-drama-30"].waitForExistence(timeout: 5))

        app.buttons["catalogSort"].tap()
        XCTAssertTrue(app.buttons["catalogSortDirection"].waitForExistence(timeout: 2))
        app.buttons["catalogSortDirection"].tap()
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-drama-2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["catalogScore-fixture-catalog-drama-2"].exists)
    }

    func testCatalogFilterAndSortSelectionsSurviveRelaunch() {
        var app = launchFixtureApp()
        app.buttons["browseCategory-drama"].tap()
        XCTAssertTrue(app.buttons["catalogFilter"].waitForExistence(timeout: 5))
        app.buttons["catalogFilter"].tap()
        app.buttons["catalogFilter-Language"].tap()
        XCTAssertTrue(app.buttons["英语"].waitForExistence(timeout: 2))
        app.buttons["英语"].tap()
        app.buttons["applyCatalogFilters"].tap()
        XCTAssertTrue(app.staticTexts["15 results"].waitForExistence(timeout: 5))
        app.buttons["catalogSort"].tap()
        app.buttons["catalogSort-3"].tap()
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-drama-30"].waitForExistence(timeout: 5))
        app.terminate()

        app = launchFixtureApp(resetSavedItems: false, resetCatalogPreferences: false)
        app.buttons["browseCategory-drama"].tap()

        XCTAssertTrue(app.staticTexts["15 results"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["catalogFilter"].value as? String, "1 selected")
        XCTAssertEqual(app.buttons["catalogSort"].label, "Sort: Rating")
        XCTAssertTrue(app.buttons["catalogItem-fixture-catalog-drama-30"].exists)
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
            "-AiyifanResetCatalogPreferences",
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

        let continueItem = app.buttons["continueItem-fixture-drama"]
        XCTAssertTrue(continueItem.waitForExistence(timeout: 5))
        continueItem.tap()

        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        let episodeControl = app.buttons["showEpisodes"]
        XCTAssertTrue(episodeControl.waitForExistence(timeout: 5))
        XCTAssertTrue(episodeControl.label.contains("4/10"))
    }

    func testHomeKeepsDiscoverySimpleWithCollapsedAPISearch() {
        let app = launchFixtureApp()
        XCTAssertTrue(app.otherElements["homeView"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["providerSearchField"].exists)
        XCTAssertFalse(app.buttons["filterLatest"].exists)
        XCTAssertTrue(app.buttons["showSearch"].exists)
        XCTAssertTrue(app.buttons["browseCategory-anime"].exists)
    }

    func testGlobalAPISearchUsesTheAllCatalogCardStyle() {
        let app = launchFixtureApp()

        let showSearch = app.buttons["showSearch"]
        XCTAssertTrue(showSearch.waitForExistence(timeout: 5))
        showSearch.tap()

        let searchField = app.textFields["providerSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        let searchContainer = app.otherElements["expandedSearchFieldContainer"]
        XCTAssertTrue(searchContainer.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(searchContainer.frame.height, 50)
        XCTAssertGreaterThan(searchContainer.frame.width, app.frame.width * 0.65)
        XCTAssertTrue(app.buttons["submitSearch"].isHittable)
        XCTAssertTrue(app.buttons["cancelSearch"].isHittable)
        searchField.tap()
        searchField.typeText("Fixture Search")
        app.buttons["submitSearch"].tap()

        let result = app.buttons["catalogItem-fixture-search-movie"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["catalogScore-fixture-search-movie"].exists)
        XCTAssertTrue(app.buttons["saveCatalogItem-fixture-search-movie"].exists)

        app.buttons["cancelSearch"].tap()
        XCTAssertFalse(searchField.exists)
        XCTAssertTrue(app.otherElements["homeView"].exists)
    }

    func testPlayerAlwaysOffersAutomaticQualityControl() {
        let app = launchFixtureApp()
        app.buttons["latestItem-fixture-movie"].tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))

        app.buttons["playbackSettings"].tap()
        let quality = app.buttons["playbackQuality"]
        XCTAssertTrue(quality.waitForExistence(timeout: 3))
        quality.tap()

        let automatic = app.buttons["automaticPlaybackQuality"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        XCTAssertTrue(automatic.label.contains("Automatic"))
    }

    func testPowerUserSessionKeepsNavigationAndCollectionsConsistent() {
        let app = launchFixtureAppWithPlayedHistory()
        let latestItem = app.buttons["latestItem-fixture-movie"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-movie"].tap()
        app.buttons["saveItem-fixture-drama"].tap()

        for _ in 0..<3 {
            latestItem.tap()
            XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Saved"].tap()
        let savedItem = app.buttons["savedItem-fixture-drama"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        savedItem.tap()
        XCTAssertTrue(app.buttons["showEpisodes"].waitForExistence(timeout: 5))
        app.buttons["showEpisodes"].tap()
        app.buttons["episodeRow-episode-2"].tap()
        XCTAssertTrue(app.buttons["showEpisodes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["showEpisodes"].label.contains("2/10"))
        app.buttons["closeNativePlayer"].tap()

        app.tabBars.buttons["Played"].tap()
        let playedItem = app.buttons["playedItem-fixture-drama::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        playedItem.tap()
        XCTAssertTrue(app.buttons["showEpisodes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["showEpisodes"].label.contains("4/10"))
        app.buttons["closeNativePlayer"].tap()
        XCTAssertTrue(app.otherElements["nativeMiniPlayer"].waitForExistence(timeout: 5))

        app.buttons["clearPlayed"].tap()
        XCTAssertTrue(app.alerts["Clear Played History?"].waitForExistence(timeout: 2))
        app.alerts.buttons["Clear All"].tap()
        XCTAssertTrue(app.staticTexts["Nothing played yet"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["savedItem-fixture-movie"].exists)
    }

    func testFiftyActionHeavyUserSessionRemainsConsistent() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AiyifanUseFixtureFeed",
            "-AiyifanResetSavedItems",
            "-AiyifanResetPlayedItems",
            "-AiyifanResetCatalogPreferences",
            "-AiyifanSeedPlayedItems",
            "-AiyifanSimulateCastSession"
        ]
        app.launch()

        let latestItem = app.buttons["latestItem-fixture-movie"]
        XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        app.buttons["saveItem-fixture-movie"].tap()

        for _ in 0..<5 {
            latestItem.tap()
            XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(latestItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Saved"].tap()
        let savedItem = app.buttons["savedItem-fixture-movie"]
        XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            savedItem.tap()
            XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(savedItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Played"].tap()
        let playedItem = app.buttons["playedItem-fixture-drama::episode-4"]
        XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            playedItem.tap()
            XCTAssertTrue(app.buttons["closeNativePlayer"].waitForExistence(timeout: 5))
            app.buttons["closeNativePlayer"].tap()
            XCTAssertTrue(playedItem.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Home"].tap()
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
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(latestItem.exists)
        XCTAssertTrue(app.otherElements["castMiniController"].exists)

        app.buttons["browseCategory-movie"].tap()
        let catalogItem = app.buttons["catalogItem-fixture-catalog-movie-25"]
        for _ in 0..<8 where !catalogItem.exists {
            app.swipeUp()
        }
        XCTAssertTrue(catalogItem.waitForExistence(timeout: 5))
        app.buttons["saveCatalogItem-fixture-catalog-movie-25"].tap()
        catalogItem.tap()
        XCTAssertTrue(app.otherElements["nativePlayer"].waitForExistence(timeout: 5))
        app.buttons["closeNativePlayer"].tap()
        XCTAssertTrue(app.buttons["closeCategoryCatalog"].waitForExistence(timeout: 5))
        app.buttons["closeCategoryCatalog"].tap()

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["savedItem-fixture-catalog-movie-25"].waitForExistence(timeout: 5))
    }
}
