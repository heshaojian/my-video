import Foundation
import UIKit
import UserNotifications

enum AppCapabilities {
    #if MYVIDEO_ICLOUD
    static let iCloudSyncAvailable = true
    #else
    static let iCloudSyncAvailable = false
    #endif
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var updateAlertsEnabled: Bool
    @Published private(set) var cloudSyncEnabled: Bool

    private static let alertsKey = "myvideoUpdateAlertsEnabled"
    private static let cloudKey = "myvideoCloudSyncEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        updateAlertsEnabled = defaults.bool(forKey: Self.alertsKey)
        cloudSyncEnabled = AppCapabilities.iCloudSyncAvailable && defaults.bool(forKey: Self.cloudKey)
    }

    func setUpdateAlertsEnabled(_ enabled: Bool) {
        updateAlertsEnabled = enabled
        defaults.set(enabled, forKey: Self.alertsKey)
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        let supportedValue = AppCapabilities.iCloudSyncAvailable && enabled
        cloudSyncEnabled = supportedValue
        defaults.set(supportedValue, forKey: Self.cloudKey)
    }
}

struct MyVideoDeepLinkDestination: Equatable, Sendable {
    let item: MyVideoItem
    let episodeKey: String?
}

enum MyVideoDeepLink {
    static func makeURL(item: MyVideoItem, episodeKey: String?) -> URL? {
        guard let data = try? JSONEncoder().encode(item), data.count <= 16_384 else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "myvideo"
        components.host = "play"
        components.queryItems = [
            URLQueryItem(name: "item", value: data.base64EncodedString()),
            URLQueryItem(name: "episode", value: episodeKey)
        ].filter { $0.value != nil }
        return components.url
    }

    static func parse(_ url: URL) -> MyVideoDeepLinkDestination? {
        guard
            url.scheme == "myvideo",
            url.host == "play",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == "item" })?.value,
            encoded.count <= 24_000,
            let data = Data(base64Encoded: encoded),
            data.count <= 16_384,
            let item = try? JSONDecoder().decode(MyVideoItem.self, from: data)
        else {
            return nil
        }
        let episode = components.queryItems?.first(where: { $0.name == "episode" })?.value
        return MyVideoDeepLinkDestination(item: item, episodeKey: episode)
    }
}

struct CloudLibraryPayload: Codable, Equatable, Sendable {
    let savedItems: [MyVideoItem]
    let playedItems: [PlayedRecord]
}

enum CloudLibraryMerger {
    static func merge(local: CloudLibraryPayload, cloud: CloudLibraryPayload) -> CloudLibraryPayload {
        let saved = (local.savedItems + cloud.savedItems).reduce(into: [MyVideoItem]()) { result, item in
            if !result.contains(where: { $0.id == item.id }) {
                result.append(item)
            }
        }
        let playedByID = (local.playedItems + cloud.playedItems).reduce(into: [String: PlayedRecord]()) { result, record in
            guard let current = result[record.id] else {
                result[record.id] = record
                return
            }
            if record.lastPlayedAt > current.lastPlayedAt ||
                (record.lastPlayedAt == current.lastPlayedAt && record.position > current.position) {
                result[record.id] = record
            }
        }
        return CloudLibraryPayload(
            savedItems: saved,
            playedItems: playedByID.values.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        )
    }
}

struct NotificationBatch: Equatable, Sendable {
    let title: String
    let body: String
    let deepLink: URL

    static func make(
        items: [MyVideoItem],
        notificationsEnabled: (MyVideoItem) -> Bool
    ) -> NotificationBatch? {
        let enabled = items.filter(notificationsEnabled)
        guard let first = enabled.first, let deepLink = MyVideoDeepLink.makeURL(item: first, episodeKey: nil) else {
            return nil
        }
        let count = enabled.count
        let title = "MyVideo: \(count) new update\(count == 1 ? "" : "s")"
        let names = enabled.prefix(3).map(\.title).joined(separator: ", ")
        let suffix = count > 3 ? " and \(count - 3) more" : ""
        return NotificationBatch(title: title, body: names + suffix, deepLink: deepLink)
    }

    static func make(
        episodeUpdates: [SavedEpisodeUpdate],
        notificationsEnabled: (MyVideoItem) -> Bool
    ) -> NotificationBatch? {
        let enabled = episodeUpdates.filter { notificationsEnabled($0.item) }
        guard
            let first = enabled.first,
            let deepLink = MyVideoDeepLink.makeURL(
                item: first.item,
                episodeKey: first.episode.mediaKey
            )
        else {
            return nil
        }
        let count = enabled.count
        let title = "MyVideo: \(count) new episode\(count == 1 ? "" : "s")"
        let names = enabled.prefix(3).map { "\($0.item.title) Episode \($0.episode.title)" }
            .joined(separator: ", ")
        let suffix = count > 3 ? " and \(count - 3) more" : ""
        return NotificationBatch(title: title, body: names + suffix, deepLink: deepLink)
    }
}

enum NotificationPermissionState: String, Sendable {
    case notDetermined = "Not requested"
    case denied = "Denied"
    case authorized = "Allowed"
    case provisional = "Provisional"
}

@MainActor
final class NotificationCoordinator: ObservableObject {
    static let shared = NotificationCoordinator()

    @Published private(set) var permissionState: NotificationPermissionState = .notDetermined
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        permissionState = Self.state(for: settings.authorizationStatus)
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshPermission()
            return granted
        } catch {
            await refreshPermission()
            return false
        }
    }

    func schedule(_ batch: NotificationBatch) async {
        let content = UNMutableNotificationContent()
        content.title = batch.title
        content.body = batch.body
        content.sound = .default
        content.threadIdentifier = "myvideo-updates"
        content.userInfo = ["deepLink": batch.deepLink.absoluteString]
        let request = UNNotificationRequest(
            identifier: "myvideo-updates-\(batch.deepLink.absoluteString.hashValue)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private static func state(for status: UNAuthorizationStatus) -> NotificationPermissionState {
        switch status {
        case .denied: .denied
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

final class NotificationResponseRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationResponseRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let value = response.notification.request.content.userInfo["deepLink"] as? String
        if let value, let url = URL(string: value), MyVideoDeepLink.parse(url) != nil {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}

@MainActor
final class CloudLibrarySync: ObservableObject {
    static let shared = CloudLibrarySync()

    @Published private(set) var status = "Off"
    private let key = "myvideoLibraryPayloadV1"
    #if MYVIDEO_ICLOUD
    private let store = NSUbiquitousKeyValueStore.default
    #endif

    private init() {}

    func synchronize(savedItems: [MyVideoItem], playedItems: [PlayedRecord], enabled: Bool) -> CloudLibraryPayload {
        let local = CloudLibraryPayload(savedItems: savedItems, playedItems: playedItems)
        guard enabled else {
            status = "Off"
            return local
        }
        guard AppCapabilities.iCloudSyncAvailable else {
            status = "Unavailable"
            return local
        }
        #if MYVIDEO_ICLOUD
        let cloud = store.data(forKey: key).flatMap { try? JSONDecoder().decode(CloudLibraryPayload.self, from: $0) }
        let merged = cloud.map { CloudLibraryMerger.merge(local: local, cloud: $0) } ?? local
        if let data = try? JSONEncoder().encode(merged) {
            store.set(data, forKey: key)
            _ = store.synchronize()
            status = "Synced"
        } else {
            status = "Unavailable"
        }
        return merged
        #else
        return local
        #endif
    }
}
