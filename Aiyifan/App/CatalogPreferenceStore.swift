import Foundation

@MainActor
final class CatalogPreferenceStore {
    static let shared = CatalogPreferenceStore()

    private struct Payload: Codable {
        let version: Int
        let queries: [String: QuerySnapshot]
    }

    private struct QuerySnapshot: Codable {
        let genreCID: String?
        let region: String?
        let language: String?
        let year: String?
        let quality: String?
        let status: String?
        let sort: Int
        let descending: Bool

        init(_ query: CatalogQuery) {
            genreCID = query.genreCID
            region = query.region
            language = query.language
            year = query.year
            quality = query.quality
            status = query.status?.rawValue
            sort = query.sort.rawValue
            descending = query.descending
        }

        func query(for category: AiyifanCategory) -> CatalogQuery? {
            guard let sort = CatalogSort(rawValue: sort) else {
                return nil
            }
            let statusValue: CatalogSerialStatus?
            if let status {
                guard let decoded = CatalogSerialStatus(rawValue: status) else {
                    return nil
                }
                statusValue = decoded
            } else {
                statusValue = nil
            }
            return try? CatalogQuery(
                validating: category,
                genreCID: genreCID,
                region: region,
                language: language,
                year: year,
                quality: quality,
                status: statusValue,
                sort: sort,
                descending: descending
            )
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "aiyifanCatalogPreferencesV1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if ProcessInfo.processInfo.arguments.contains("-AiyifanResetCatalogPreferences") {
            defaults.removeObject(forKey: storageKey)
        }
    }

    func query(for category: AiyifanCategory) -> CatalogQuery? {
        payload()?.queries[category.rawValue]?.query(for: category)
    }

    func save(_ query: CatalogQuery) {
        guard (try? query.validate()) != nil else {
            return
        }
        let current = payload()?.queries ?? [:]
        let updated = current.merging(
            [query.category.rawValue: QuerySnapshot(query)],
            uniquingKeysWith: { _, new in new }
        )
        persist(Payload(version: 1, queries: updated))
    }

    func clearFilters(for category: AiyifanCategory) {
        let current = query(for: category) ?? CatalogQuery(category: category)
        save(CatalogQuery(
            category: category,
            sort: current.sort,
            descending: current.descending
        ))
    }

    private func payload() -> Payload? {
        guard
            let data = defaults.data(forKey: storageKey),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.version == 1
        else {
            return nil
        }
        return payload
    }

    private func persist(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
