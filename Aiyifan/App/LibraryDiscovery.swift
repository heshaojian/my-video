import Foundation

enum ContentLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case chinese
    case english
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese:
            "中文"
        case .english:
            "English"
        case .unknown:
            "Other / Unknown"
        }
    }

    static func classify(_ item: AiyifanItem) -> ContentLanguage {
        let value = [item.title, item.subTitle, item.addTime]
            .compactMap { $0 }
            .joined(separator: " ")
        let hasHan = value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
                (0x4E00...0x9FFF).contains(scalar.value)
        }
        if hasHan {
            return .chinese
        }
        if value.range(of: "[A-Za-z]", options: .regularExpression) != nil {
            return .english
        }
        return .unknown
    }
}

enum LibraryWatchState: String, CaseIterable, Codable, Identifiable, Sendable {
    case unplayed
    case inProgress
    case watched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unplayed:
            "Unplayed"
        case .inProgress:
            "In Progress"
        case .watched:
            "Watched"
        }
    }
}

enum WatchStateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unplayed
    case inProgress
    case watched
    case newUpdate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .unplayed:
            "Unplayed"
        case .inProgress:
            "In Progress"
        case .watched:
            "Watched"
        case .newUpdate:
            "New Update"
        }
    }
}

struct LibraryDocument: Equatable, Identifiable, Sendable {
    let item: AiyifanItem
    let category: AiyifanCategory
    let watchState: LibraryWatchState
    let hasNewUpdate: Bool

    var id: String { item.id }
    var language: ContentLanguage { ContentLanguage.classify(item) }
    var year: Int? { LibraryMetadata.year(for: item) }
}

struct LibraryFilter: Equatable, Sendable {
    var query = ""
    var category: AiyifanCategory?
    var language: ContentLanguage?
    var year: Int?
    var watchState: WatchStateFilter = .all

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            category != nil || language != nil || year != nil || watchState != .all
    }
}

enum LibraryMetadata {
    static func year(for item: AiyifanItem) -> Int? {
        let source = [item.title, item.subTitle, item.addTime]
            .compactMap { $0 }
            .joined(separator: " ")
        guard let range = source.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) else {
            return nil
        }
        return Int(source[range])
    }
}

enum LibrarySearchEngine {
    static func results(
        in documents: [LibraryDocument],
        matching filter: LibraryFilter
    ) -> [LibraryDocument] {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)

        return documents.filter { document in
            if !query.isEmpty {
                let searchable = [document.item.title, document.item.updateLabel, document.category.title]
                    .joined(separator: " ")
                guard searchable.localizedCaseInsensitiveContains(query) else {
                    return false
                }
            }
            if let category = filter.category, document.category != category {
                return false
            }
            if let language = filter.language, document.language != language {
                return false
            }
            if let year = filter.year, document.year != year {
                return false
            }
            switch filter.watchState {
            case .all:
                return true
            case .unplayed:
                return document.watchState == .unplayed
            case .inProgress:
                return document.watchState == .inProgress
            case .watched:
                return document.watchState == .watched
            case .newUpdate:
                return document.hasNewUpdate
            }
        }
    }
}

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
