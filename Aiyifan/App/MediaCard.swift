import SwiftUI

enum PosterMediaCardLayout: Equatable {
    case compact
    case grid
}

enum EpisodeDisplayLabel {
    static func sanitized(_ value: String?, excluding values: [String] = []) -> String? {
        let excludedValues = Set(values.compactMap(normalized))
        guard let value = normalized(value), !excludedValues.contains(value) else { return nil }
        guard hasRecognizedEpisodeForm(value) || !isOpaqueProviderKey(value) else { return nil }
        return value
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hasRecognizedEpisodeForm(_ value: String) -> Bool {
        if EpisodeNumberParser.number(in: value) != nil {
            return true
        }

        guard value.hasPrefix("第"), value.hasSuffix("期") else { return false }
        let number = value.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(number) != nil
    }

    private static func isOpaqueProviderKey(_ value: String) -> Bool {
        guard
            !value.contains(where: \.isWhitespace),
            (8...128).contains(value.count)
        else {
            return false
        }

        let scalars = value.unicodeScalars
        return scalars.contains(where: CharacterSet.letters.contains)
            && scalars.contains(where: CharacterSet.decimalDigits.contains)
    }
}

struct PosterCardProjection: Equatable, Sendable {
    let title: String
    let detailText: String?

    init(item: AiyifanItem, episodeState: SavedEpisodeUpdateState? = nil) {
        title = item.title
        let details = [
            Self.episodeLabel(item: item, episodeState: episodeState),
            EpisodeDisplayLabel.normalized(item.language),
            EpisodeDisplayLabel.normalized(item.year)
        ].compactMap { $0 }
        detailText = details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private static func episodeLabel(
        item: AiyifanItem,
        episodeState: SavedEpisodeUpdateState?
    ) -> String? {
        guard item.isSerial == true || episodeState != nil else { return nil }

        let synchronizedTitle = episodeState.flatMap { state in
            state.episodes.first(where: { $0.mediaKey == state.latestEpisodeKey })?.title
        }
        let rejectedValues = [
            EpisodeDisplayLabel.normalized(item.listPath),
            EpisodeDisplayLabel.normalized(item.latestEpisodeKey),
            episodeState.flatMap { EpisodeDisplayLabel.normalized($0.latestEpisodeKey) }
        ].compactMap { $0 }

        for candidate in [synchronizedTitle, item.latestEpisodeTitle, item.subTitle] {
            if let candidate = EpisodeDisplayLabel.sanitized(candidate, excluding: rejectedValues) {
                return candidate
            }
        }

        return nil
    }
}

struct PosterArtworkContainer<Artwork: View>: View {
    static var aspectRatio: CGFloat { 0.72 }

    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay {
                artwork()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
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
    let projection: PosterCardProjection
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
        projection: PosterCardProjection? = nil,
        onTap: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) {
        self.item = item
        self.projection = projection ?? PosterCardProjection(item: item)
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

                    VStack(alignment: .leading, spacing: 3) {
                        Text(projection.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.white.opacity(0.94))
                            .accessibilityIdentifier("\(itemIdentifier)-title")

                        if let detailText = projection.detailText {
                            Text(detailText)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.cyan.opacity(0.82))
                                .accessibilityIdentifier("\(itemIdentifier)-detail")
                        }
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
        PosterArtworkContainer {
            PosterImage(item: item)
        }
            .frame(width: layout == .compact ? 132 : nil)
            .frame(maxWidth: layout == .grid ? .infinity : nil)
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

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("\(itemIdentifier)-title")

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.cyan.opacity(0.82))
                                .accessibilityIdentifier("\(itemIdentifier)-detail")
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
