import XCTest
@testable import Aiyifan

@MainActor
final class SavedItemsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SavedItemsStoreTests")
        defaults.removePersistentDomain(forName: "SavedItemsStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SavedItemsStoreTests")
        defaults = nil
        super.tearDown()
    }

    func testTogglePersistsSavedItemAcrossStoreInstances() {
        let item = AiyifanItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)

        store.toggle(item)

        XCTAssertTrue(store.contains(item))
        XCTAssertEqual(SavedItemsStore(defaults: defaults).items, [item])
    }

    func testToggleRemovesExistingSavedItem() {
        let item = AiyifanItem(listPath: "saved-drama", title: "Saved Drama")
        let store = SavedItemsStore(defaults: defaults)
        store.toggle(item)

        store.toggle(item)

        XCTAssertFalse(store.contains(item))
        XCTAssertTrue(store.items.isEmpty)
    }
}
