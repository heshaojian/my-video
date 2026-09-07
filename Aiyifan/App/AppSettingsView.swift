import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @StateObject private var notifications = NotificationCoordinator.shared
    @StateObject private var cloudSync = CloudLibrarySync.shared
    @StateObject private var playback = PlaybackPreferencesStore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Updates") {
                    Toggle("Update Alerts", isOn: alertBinding)
                        .accessibilityIdentifier("updateAlertsToggle")
                    LabeledContent("Permission", value: notifications.permissionState.rawValue)
                    Button("Refresh Latest", systemImage: "arrow.clockwise") {
                        Task { await refreshLatest() }
                    }
                }

                Section("Playback") {
                    Picker("Default Speed", selection: rateBinding) {
                        ForEach(PlaybackPreferencesStore.supportedRates, id: \.self) { rate in
                            Text("\(rate.formatted())x").tag(rate)
                        }
                    }
                    Toggle("Autoplay Next", isOn: autoplayBinding)
                }

                Section("iCloud") {
                    Toggle("Sync Library", isOn: cloudBinding)
                        .accessibilityIdentifier("cloudSyncToggle")
                        .disabled(!AppCapabilities.iCloudSyncAvailable)
                    LabeledContent("Status", value: cloudSync.status)
                    if settings.cloudSyncEnabled {
                        Button("Sync Now", systemImage: "icloud.and.arrow.up") { synchronizeCloud() }
                    }
                }

                Section("Storage") {
                    if let date = viewModel.lastFeedRefresh {
                        LabeledContent("Last Refresh", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Clear Feed Cache", systemImage: "trash", role: .destructive) {
                        Task { await viewModel.clearFeedCache() }
                    }
                    .accessibilityIdentifier("clearFeedCache")
                    Button("Reset Playback Settings", systemImage: "arrow.counterclockwise", role: .destructive) {
                        playback.reset()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await notifications.refreshPermission() }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { settings.updateAlertsEnabled },
            set: { enabled in
                if enabled {
                    Task {
                        let granted = await notifications.requestPermission()
                        settings.setUpdateAlertsEnabled(granted)
                    }
                } else {
                    settings.setUpdateAlertsEnabled(false)
                }
            }
        )
    }

    private var cloudBinding: Binding<Bool> {
        Binding(
            get: { settings.cloudSyncEnabled },
            set: { enabled in
                settings.setCloudSyncEnabled(enabled)
                if enabled { synchronizeCloud() }
            }
        )
    }

    private var rateBinding: Binding<Float> {
        Binding(
            get: { playback.playbackRate },
            set: { value in playback.setPlaybackRate(value) }
        )
    }

    private var autoplayBinding: Binding<Bool> {
        Binding(
            get: { playback.autoplayNext },
            set: { value in playback.setAutoplayNext(value) }
        )
    }

    private func synchronizeCloud() {
        let merged = cloudSync.synchronize(
            savedItems: savedItemsStore.items,
            playedItems: playedItemsStore.items,
            enabled: settings.cloudSyncEnabled
        )
        savedItemsStore.mergeFromCloud(merged.savedItems)
        playedItemsStore.mergeFromCloud(merged.playedItems)
    }

    private func refreshLatest() async {
        await viewModel.loadLatestIfNeeded(force: true)
        let changed = savedItemsStore.refreshUpdateMarkers(with: viewModel.latestItems)
        if settings.updateAlertsEnabled,
           let batch = NotificationBatch.make(
            items: changed,
            notificationsEnabled: { item in savedItemsStore.notificationsEnabled(for: item) }
           ) {
            await notifications.schedule(batch)
        }
    }
}
