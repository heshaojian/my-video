import SwiftUI

struct SavedItemsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var appSettings: AppSettingsStore

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
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
                        LazyVGrid(columns: columns, spacing: 20) {
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
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 7) {
                    PosterImage(item: item)
                        .aspectRatio(0.72, contentMode: .fit)

                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.92))

                    Text(item.updateLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("savedItem-\(item.id)")
            .contextMenu {
                Button(notificationsEnabled ? "Disable Alerts" : "Enable Alerts", systemImage: notificationsEnabled ? "bell.slash" : "bell") {
                    onToggleNotifications()
                }
                if hasNewUpdate {
                    Button("Mark Update Seen", systemImage: "eye") { onMarkSeen() }
                }
                Button("Remove", systemImage: "bookmark.slash", role: .destructive) { onRemove() }
            }

            Button(action: onRemove) {
                Image(systemName: "bookmark.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.cyan)
                    .clipShape(Circle())
            }
            .padding(7)
            .accessibilityLabel("Remove from Saved")
            .accessibilityIdentifier("removeSavedItem-\(item.id)")

            if hasNewUpdate {
                Text("NEW")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .foregroundStyle(.black)
                    .background(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(7)
                    .allowsHitTesting(false)
            }
        }
    }
}
