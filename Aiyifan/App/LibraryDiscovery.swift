import Foundation

enum ContinueWatchingProjector {
    static func records(from records: [PlayedRecord]) -> [PlayedRecord] {
        let sorted = records
            .filter { !$0.isCompleted }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        var seenItemIDs = Set<String>()
        return sorted.filter { record in
            seenItemIDs.insert(record.item.id).inserted
        }
    }
}

struct UpdateMarker: Codable, Equatable, Sendable {
    let itemID: String
    let updateKey: String
}

enum UpdateTracker {
    static func changedItemIDs(
        previous: [String: UpdateMarker]?,
        current: [String: UpdateMarker],
        savedItemIDs: Set<String>
    ) -> Set<String> {
        guard let previous else {
            return []
        }
        return Set(savedItemIDs.filter { itemID in
            guard
                let old = previous[itemID],
                let new = current[itemID],
                !new.updateKey.isEmpty
            else {
                return false
            }
            return old.updateKey != new.updateKey
        })
    }
}
