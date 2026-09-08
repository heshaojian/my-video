import SwiftUI

struct SavedItemsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @ObservedObject var readyToWatchStore: ReadyToWatchOverridesStore
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
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ReadyToWatchRail(
                                entries: readyEntries,
                                onPlay: play,
                                onDismiss: dismiss,
                                onPin: pin,
                                destination: queueDestination
                            )

                            Text("All Saved")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("allSavedHeading")

                            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                                ForEach(savedItemsStore.items) { item in
                                    SavedItemCard(
                                        item: item,
                                        hasNewUpdate: savedItemsStore.hasNewUpdate(item),
                                        onTap: { viewModel.selectItem(item) },
                                        onRemove: { savedItemsStore.toggle(item) },
                                        onAddToReady: addToReadyAction(for: item),
                                        notificationsEnabled: appSettings.updateAlertsEnabled && savedItemsStore.notificationsEnabled(for: item),
                                        onToggleNotifications: { toggleNotifications(for: item) },
                                        onMarkSeen: { savedItemsStore.markUpdateSeen(item) }
                                    )
                                }
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("Saved")
            .onChange(of: savedItemsStore.items.map(\.id)) { _, ids in
                readyToWatchStore.prune(savedTitleIDs: Set(ids))
            }
        }
    }

    private var readyEntries: [ReadyToWatchEntry] {
        ReadyToWatchProjector.project(
            savedItems: savedItemsStore.items,
            updates: savedItemsStore.readyToWatchUpdates,
            playedRecords: playedItemsStore.items,
            overrides: readyToWatchStore.overrides
        )
    }

    private func play(_ entry: ReadyToWatchEntry) {
        viewModel.selectItem(entry.item, episodeKey: entry.episodeKey)
    }

    private func pin(_ entry: ReadyToWatchEntry) {
        readyToWatchStore.pin(titleID: entry.item.id, episodeKey: entry.episodeKey)
    }

    private func dismiss(_ entry: ReadyToWatchEntry) {
        if entry.source == .manual {
            readyToWatchStore.unpin(titleID: entry.item.id)
        } else {
            readyToWatchStore.dismiss(titleID: entry.item.id, episodeKey: entry.episodeKey)
        }
    }

    private func markWatched(_ entry: ReadyToWatchEntry) {
        let episode = entry.episodeKey.map {
            Episode(mediaKey: $0, title: entry.episodeTitle ?? $0, updateDate: nil)
        }
        playedItemsStore.markWatched(item: entry.item, episode: episode)
        if entry.isNew {
            savedItemsStore.markEpisodeUpdateSeen(entry.item, episodeKey: entry.episodeKey)
        }
        if entry.source == .manual {
            readyToWatchStore.unpin(titleID: entry.item.id)
            if entry.episodeKey != nil {
                readyToWatchStore.dismiss(titleID: entry.item.id, episodeKey: entry.episodeKey)
            }
        } else {
            readyToWatchStore.dismiss(titleID: entry.item.id, episodeKey: entry.episodeKey)
        }
    }

    private func addToReadyAction(for item: AiyifanItem) -> (() -> Void)? {
        let episodeKey = savedItemsStore.episodeUpdateState(for: item).flatMap { state in
            state.episodes.first(where: { $0.mediaKey == state.latestEpisodeKey })?.mediaKey
        }
        return { readyToWatchStore.pin(titleID: item.id, episodeKey: episodeKey) }
    }

    private func queueDestination() -> ReadyToWatchQueueView {
        ReadyToWatchQueueView(
            savedItemsStore: savedItemsStore,
            playedItemsStore: playedItemsStore,
            readyToWatchStore: readyToWatchStore,
            onPlay: play,
            onDismiss: dismiss,
            onMarkWatched: markWatched,
            onReorderPins: { readyToWatchStore.reorder(titleIDs: $0) }
        )
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
    let onAddToReady: (() -> Void)?
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
            if let onAddToReady {
                Button("Add to Ready to Watch", systemImage: "pin") { onAddToReady() }
            }
            Button("Remove", systemImage: "bookmark.slash", role: .destructive) { onRemove() }
        }
    }
}
