import SwiftUI

struct PlayedItemsView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var playedItemsStore: PlayedItemsStore

    @State private var isConfirmingClear = false
    @State private var filter = PlayedFilter.all

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryScreenChrome.background
                    .ignoresSafeArea()

                if playedItemsStore.items.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            LibraryScreenHeader(title: "Played", accessibilityIdentifier: "playedScreenTitle")

                            ContentUnavailableView(
                                "Nothing played yet",
                                systemImage: "clock.arrow.circlepath",
                                description: Text("Movies and episodes you start will appear here.")
                            )
                            .foregroundStyle(LibraryScreenChrome.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 360)
                        }
                        .padding(18)
                        .padding(.bottom, LibraryScreenChrome.scrollBottomClearance)
                    }
                } else {
                    VStack(spacing: 0) {
                        LibraryScreenHeader(title: "Played", accessibilityIdentifier: "playedScreenTitle") {
                            Button(role: .destructive) {
                                isConfirmingClear = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .accessibilityLabel("Clear Played History")
                            .accessibilityIdentifier("clearPlayed")
                        }
                            .padding(.horizontal, 18)
                            .padding(.top, 18)

                        Picker("Played Filter", selection: $filter) {
                            ForEach(PlayedFilter.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredItems) { record in
                                    PlayedItemRow(
                                        record: record,
                                        onPlay: { viewModel.selectPlayed(record) },
                                        onRemove: { playedItemsStore.remove(record) },
                                        onRestart: { playedItemsStore.restart(record) },
                                        onToggleWatched: {
                                            if record.isCompleted {
                                                playedItemsStore.markUnwatched(record)
                                            } else {
                                                playedItemsStore.markWatched(record)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(16)
                            .padding(.bottom, LibraryScreenChrome.scrollBottomClearance)
                        }
                    }
                }
            }
            .alert("Clear Played History?", isPresented: $isConfirmingClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive, action: playedItemsStore.removeAll)
            } message: {
                Text("This removes all local watch progress.")
            }
        }
    }

    private var filteredItems: [PlayedRecord] {
        switch filter {
        case .all:
            playedItemsStore.items
        case .inProgress:
            playedItemsStore.items.filter { !$0.isCompleted }
        case .watched:
            playedItemsStore.items.filter(\.isCompleted)
        }
    }
}

private enum PlayedFilter: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case watched

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .inProgress: "In Progress"
        case .watched: "Watched"
        }
    }
}

private struct PlayedItemRow: View {
    let record: PlayedRecord
    let onPlay: () -> Void
    let onRemove: () -> Void
    let onRestart: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
        ProgressMediaCard(
            item: record.item,
            subtitle: record.episodeTitle.map { "Episode \($0)" },
            progress: progress,
            progressLabel: PlayedPositionFormatter.label(
                position: record.position,
                duration: record.duration
            ),
            progressLabelIdentifier: "playedPosition-\(record.id)",
            itemIdentifier: "playedItem-\(record.id)",
            onTap: onPlay
        ) {
            HStack(spacing: 0) {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove from Played")
                .accessibilityIdentifier("removePlayed-\(record.id)")

                Menu {
                    Button(record.isCompleted ? "Mark Unwatched" : "Mark Watched", systemImage: record.isCompleted ? "circle" : "checkmark.circle", action: onToggleWatched)
                    Button("Restart", systemImage: "arrow.counterclockwise", action: onRestart)
                    Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Played Options")
                .accessibilityIdentifier("playedOptions-\(record.id)")
            }
        }
    }

    private var progress: Double {
        guard record.duration > 0 else {
            return 0
        }
        return min(max(record.position / record.duration, 0), 1)
    }
}
