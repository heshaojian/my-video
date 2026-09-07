import Foundation

@MainActor
final class SavedItemsStore: ObservableObject {
    @Published private(set) var items: [AiyifanItem]

    private static let storageKey = "savedAiyifanItems"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if ProcessInfo.processInfo.arguments.contains("-AiyifanResetSavedItems") {
            defaults.removeObject(forKey: Self.storageKey)
        }

        if let data = defaults.data(forKey: Self.storageKey),
           let decodedItems = try? JSONDecoder().decode([AiyifanItem].self, from: data) {
            items = decodedItems
        } else {
            items = []
        }
    }

    func contains(_ item: AiyifanItem) -> Bool {
        items.contains { $0.id == item.id }
    }

    func toggle(_ item: AiyifanItem) {
        let updatedItems: [AiyifanItem]

        if contains(item) {
            updatedItems = items.filter { $0.id != item.id }
        } else {
            updatedItems = [item] + items
        }

        items = updatedItems
        persist(updatedItems)
    }

    private func persist(_ items: [AiyifanItem]) {
        guard let data = try? encoder.encode(items) else {
            return
        }

        defaults.set(data, forKey: Self.storageKey)
    }
}
