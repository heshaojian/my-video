import SwiftUI

struct ReadyToWatchRail: View {
    let entries: [ReadyToWatchEntry]
    let onPlay: (ReadyToWatchEntry) -> Void
    let onDismiss: (ReadyToWatchEntry) -> Void
    let onPin: (ReadyToWatchEntry) -> Void
    let destination: () -> ReadyToWatchQueueView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ready to Watch", systemImage: "play.square.stack.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("readyToWatchHeading")

                Spacer()

                if !entries.isEmpty {
                    NavigationLink(destination: destination()) {
                        Text("See All")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("readyToWatchSeeAll")
                }
            }

            if entries.isEmpty {
                Label("New and unfinished saved episodes will appear here.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("readyToWatchEmpty")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(entries.prefix(8)) { entry in
                            PosterMediaCard(
                                item: entry.item,
                                layout: .compact,
                                actionStyle: .play,
                                itemIdentifier: "readyItem-\(entry.item.id)",
                                actionIdentifier: "playReadyItem-\(entry.item.id)",
                                scoreIdentifier: "readyScore-\(entry.item.id)",
                                status: status(for: entry),
                                onTap: { onPlay(entry) },
                                onAction: { onPlay(entry) }
                            )
                            .contextMenu {
                                if entry.source == .manual {
                                    Button("Remove from Ready to Watch", systemImage: "pin.slash") {
                                        onDismiss(entry)
                                    }
                                } else {
                                    Button("Keep at Front", systemImage: "pin") { onPin(entry) }
                                    Button("Not Now", systemImage: "xmark") { onDismiss(entry) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func status(for entry: ReadyToWatchEntry) -> String? {
        if entry.isNew { return "NEW" }
        if let position = entry.resumePosition { return "RESUME \(time(position))" }
        return entry.source == .manual ? "UP NEXT" : nil
    }

    private func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct ReadyToWatchQueueView: View {
    @ObservedObject var savedItemsStore: SavedItemsStore
    @ObservedObject var playedItemsStore: PlayedItemsStore
    @ObservedObject var readyToWatchStore: ReadyToWatchOverridesStore
    let onPlay: (ReadyToWatchEntry) -> Void
    let onDismiss: (ReadyToWatchEntry) -> Void
    let onMarkWatched: (ReadyToWatchEntry) -> Void
    let onReorderPins: ([String]) -> Void

    private var entries: [ReadyToWatchEntry] {
        ReadyToWatchProjector.project(
            savedItems: savedItemsStore.items,
            updates: savedItemsStore.readyToWatchUpdates,
            playedRecords: playedItemsStore.items,
            overrides: readyToWatchStore.overrides
        )
    }

    private var pinnedEntries: [ReadyToWatchEntry] {
        entries.filter { $0.source == .manual }
    }

    private var suggestedEntries: [ReadyToWatchEntry] {
        entries.filter { $0.source != .manual }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Nothing ready", systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
            }

            if !pinnedEntries.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedEntries) { entry in
                        queueRow(entry)
                    }
                    .onMove { source, destination in
                        var reordered = pinnedEntries.map(\.item.id)
                        reordered.move(fromOffsets: source, toOffset: destination)
                        onReorderPins(reordered)
                    }
                }
            }

            if !suggestedEntries.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestedEntries) { entry in
                        queueRow(entry)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryScreenChrome.background)
        .navigationTitle("Ready to Watch")
        .libraryNavigationChrome()
        .toolbar {
            if pinnedEntries.count > 1 {
                EditButton()
            }
        }
        .accessibilityIdentifier("readyToWatchQueue")
    }

    private func queueRow(_ entry: ReadyToWatchEntry) -> some View {
        ProgressMediaCard(
            item: entry.item,
            subtitle: subtitle(for: entry),
            progress: progress(for: entry),
            progressLabel: progressLabel(for: entry),
            itemIdentifier: "readyQueueItem-\(entry.item.id)",
            onTap: { onPlay(entry) }
        ) {
            Menu {
                Button("Play", systemImage: "play.fill") { onPlay(entry) }
                Button("Mark Watched", systemImage: "checkmark.circle") { onMarkWatched(entry) }
                Button(
                    entry.source == .manual ? "Remove from Up Next" : "Not Now",
                    systemImage: "xmark",
                    role: .destructive
                ) {
                    onDismiss(entry)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Ready to Watch Options")
            .accessibilityIdentifier("readyOptions-\(entry.item.id)")
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func subtitle(for entry: ReadyToWatchEntry) -> String? {
        guard let title = entry.episodeTitle else { return nil }
        return "Episode \(title)"
    }

    private func progress(for entry: ReadyToWatchEntry) -> Double {
        guard let position = entry.resumePosition, let duration = entry.duration, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    private func progressLabel(for entry: ReadyToWatchEntry) -> String? {
        if entry.isNew { return "New episode" }
        guard let position = entry.resumePosition, let duration = entry.duration else {
            return entry.source == .manual ? "Up next" : nil
        }
        return PlayedPositionFormatter.label(position: position, duration: duration)
    }
}
