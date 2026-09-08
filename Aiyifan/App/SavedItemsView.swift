import SwiftUI

struct SavedItemsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var appSettings: AppSettingsStore

    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 180), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.052, blue: 0.073)
                    .ignoresSafeArea()

                if savedItemsStore.items.isEmpty {
                    ContentUnavailableView("Nothing saved yet", systemImage: "bookmark")
                        .foregroundStyle(.white)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                            ForEach(savedItemsStore.items) { item in
                                SavedItemCard(
                                    item: item,
                                    hasNewUpdate: savedItemsStore.hasNewUpdate(item),
                                    onTap: { viewModel.selectItem(item) },
                                    onRemove: { savedItemsStore.toggle(item) },
                                    notificationsEnabled: appSettings.updateAlertsEnabled && savedItemsStore.notificationsEnabled(for: item),
                                    onToggleNotifications: { toggleNotifications(for: item) },
                                    onMarkSeen: { savedItemsStore.markUpdateSeen(item) }
                                )
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("Saved")
        }
    }

    private func toggleNotifications(for item: AiyifanItem) {
        let isEnabled = appSettings.updateAlertsEnabled && savedItemsStore.notificationsEnabled(for: item)
        if isEnabled {
            savedItemsStore.setNotificationsEnabled(false, for: item)
            return
        }
        Task {
            let granted = await NotificationCoordinator.shared.requestPermission()
            appSettings.setUpdateAlertsEnabled(granted)
            savedItemsStore.setNotificationsEnabled(granted, for: item)
        }
    }
}

private struct SavedItemCard: View {
    let item: AiyifanItem
    let hasNewUpdate: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let notificationsEnabled: Bool
    let onToggleNotifications: () -> Void
    let onMarkSeen: () -> Void

    var body: some View {
        PosterMediaCard(
            item: item,
            layout: .grid,
            actionStyle: .removeSaved,
            itemIdentifier: "savedItem-\(item.id)",
            actionIdentifier: "removeSavedItem-\(item.id)",
            scoreIdentifier: "savedScore-\(item.id)",
            status: hasNewUpdate ? "NEW" : nil,
            onTap: onTap,
            onAction: onRemove
        )
        .contextMenu {
            Button(notificationsEnabled ? "Disable Alerts" : "Enable Alerts", systemImage: notificationsEnabled ? "bell.slash" : "bell") {
                onToggleNotifications()
            }
            if hasNewUpdate {
                Button("Mark Update Seen", systemImage: "eye") { onMarkSeen() }
            }
            Button("Remove", systemImage: "bookmark.slash", role: .destructive) { onRemove() }
        }
    }
}
