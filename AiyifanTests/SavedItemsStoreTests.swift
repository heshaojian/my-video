import XCTest
@testable import Aiyifan

@MainActor
final class SavedItemsStoreTests: XCTestCase {
    func testTogglePersistsSavedItemAcrossStoreInstances() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)

        store.toggle(item)

        XCTAssertTrue(store.contains(item))
        XCTAssertEqual(SavedItemsStore(defaults: defaults).items, [item])
    }

    func testToggleRemovesExistingSavedItem() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)

        store.toggle(item)

        XCTAssertFalse(store.contains(item))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testFeedRefreshDetectsNewUpdateAfterBaselineAndCanMarkItSeen() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = AiyifanItem(listPath: "saved-drama", title: "Saved Drama", subTitle: "Episode 3")
        let updated = AiyifanItem(listPath: "saved-drama", title: "Saved Drama", subTitle: "Episode 4")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(original)

        store.refreshUpdateMarkers(with: [.drama: [original]])
        XCTAssertFalse(store.hasNewUpdate(original))

        store.refreshUpdateMarkers(with: [.drama: [updated]])
        XCTAssertTrue(store.hasNewUpdate(updated))

        store.markUpdateSeen(updated)
        XCTAssertFalse(store.hasNewUpdate(updated))
    }

    func testPerTitleNotificationPreferencePersists() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = AiyifanItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)

        store.setNotificationsEnabled(false, for: item)

        XCTAssertFalse(SavedItemsStore(defaults: defaults).notificationsEnabled(for: item))
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "SavedItemsStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
