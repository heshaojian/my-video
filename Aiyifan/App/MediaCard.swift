import SwiftUI

enum PosterMediaCardLayout: Equatable {
    case compact
    case grid
}

enum PosterMediaCardActionStyle {
    case save(isSaved: Bool)
    case removeSaved
    case markSeen
    case play

    var systemImage: String {
        switch self {
        case .save(let isSaved):
            isSaved ? "bookmark.fill" : "bookmark"
        case .removeSaved:
            "bookmark.slash.fill"
        case .markSeen:
            "eye.fill"
        case .play:
            "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .save(let isSaved):
            isSaved ? "Remove from Saved" : "Save for Later"
        case .removeSaved:
            "Remove from Saved"
        case .markSeen:
            "Mark Update Seen"
        case .play:
            "Play"
        }
    }

    var isHighlighted: Bool {
        switch self {
        case .save(let isSaved):
            isSaved
        case .removeSaved, .markSeen, .play:
            true
        }
    }
}

struct PosterMediaCard: View {
    let item: AiyifanItem
    let layout: PosterMediaCardLayout
    let actionStyle: PosterMediaCardActionStyle
    let itemIdentifier: String
    let actionIdentifier: String
    let scoreIdentifier: String
    let status: String?
    let onTap: () -> Void
    let onAction: () -> Void

    init(
        item: AiyifanItem,
        layout: PosterMediaCardLayout,
        actionStyle: PosterMediaCardActionStyle,
        itemIdentifier: String,
        actionIdentifier: String,
        scoreIdentifier: String,
        status: String? = nil,
        onTap: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) {
        self.item = item
        self.layout = layout
        self.actionStyle = actionStyle
        self.itemIdentifier = itemIdentifier
        self.actionIdentifier = actionIdentifier
        self.scoreIdentifier = scoreIdentifier
        self.status = status
        self.onTap = onTap
        self.onAction = onAction
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 7) {
                    poster

                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.94))

                    Text(item.updateLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.cyan.opacity(0.82))

                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
                .frame(maxWidth: layout == .grid ? .infinity : nil, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(itemIdentifier)

            Button(action: onAction) {
                Image(systemName: actionStyle.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(actionStyle.isHighlighted ? .black : .white)
                    .frame(width: 34, height: 34)
                    .background(actionStyle.isHighlighted ? Color.cyan : Color.black.opacity(0.68))
                    .clipShape(Circle())
            }
            .frame(width: 44, height: 44)
            .padding(2)
            .accessibilityLabel(actionStyle.accessibilityLabel)
            .accessibilityIdentifier(actionIdentifier)

            VStack(alignment: .leading, spacing: 5) {
                if let score = item.score {
                    ProviderScoreBadge(score: score)
                        .accessibilityIdentifier(scoreIdentifier)
                }
                if let status {
                    Text(status)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .foregroundStyle(.black)
                        .background(.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
        .frame(width: layout == .compact ? 132 : nil, alignment: .leading)
        .frame(maxWidth: layout == .grid ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder
    private var poster: some View {
        PosterImage(item: item)
            .aspectRatio(0.72, contentMode: .fit)
            .frame(width: layout == .compact ? 132 : nil)
            .frame(maxWidth: layout == .grid ? .infinity : nil)
    }

    private var metadata: String {
        [item.year, item.region]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}

struct ProgressMediaCard<TrailingActions: View>: View {
    let item: AiyifanItem
    let subtitle: String?
    let progress: Double
    let progressLabel: String?
    let progressLabelIdentifier: String?
    let itemIdentifier: String
    let onTap: () -> Void
    @ViewBuilder let trailingActions: () -> TrailingActions

    init(
        item: AiyifanItem,
        subtitle: String?,
        progress: Double,
        progressLabel: String?,
        progressLabelIdentifier: String? = nil,
        itemIdentifier: String,
        onTap: @escaping () -> Void,
        @ViewBuilder trailingActions: @escaping () -> TrailingActions
    ) {
        self.item = item
        self.subtitle = subtitle
        self.progress = progress
        self.progressLabel = progressLabel
        self.progressLabelIdentifier = progressLabelIdentifier
        self.itemIdentifier = itemIdentifier
        self.onTap = onTap
        self.trailingActions = trailingActions
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    PosterImage(item: item)
                        .frame(width: 58, height: 82)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(.cyan.opacity(0.82))
                        }

                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(.cyan)

                        if let progressLabel {
                            Text(progressLabel)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.48))
                                .accessibilityIdentifier(progressLabelIdentifier ?? "")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(itemIdentifier)

            trailingActions()
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
