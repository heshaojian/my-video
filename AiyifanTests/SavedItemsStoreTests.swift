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

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "SavedItemsStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
