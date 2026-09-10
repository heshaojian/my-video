import AVFoundation
import Foundation

struct PlaybackVariantDescriptor: Equatable, Sendable {
    let width: Int
    let height: Int
    let averageBitRate: Double?
    let peakBitRate: Double?
}

struct PlaybackTrackDescriptor: Equatable, Sendable {
    let width: Int
    let height: Int
    let estimatedBitRate: Double?
    let isPlayable: Bool
}

struct ProviderPlaybackSource: Equatable, Identifiable, Sendable {
    let url: URL
    let tierHeight: Int

    var id: Int { tierHeight }
    var title: String { "\(tierHeight)p" }
}

struct PlaybackQualityOption: Equatable, Identifiable, Sendable {
    let width: Int
    let height: Int
    let averageBitRate: Double?
    let peakBitRate: Double?

    var tierHeight: Int {
        PlaybackQualityProjector.tierHeight(width: width, height: height) ?? height
    }

    var id: Int { tierHeight }
    var title: String { "\(tierHeight)p" }
}

struct PlaybackQualityMenuOption: Equatable, Identifiable, Sendable {
    let tierHeight: Int
    let adaptiveOption: PlaybackQualityOption?
    let providerSource: ProviderPlaybackSource?

    var id: Int { tierHeight }
    var title: String { "\(tierHeight)p" }
    var isSelectable: Bool { adaptiveOption != nil || providerSource != nil }
}

enum PlaybackQualityProjector {
    private static let providerTiers: Set<Int> = [144, 240, 360, 480, 576, 720, 1_080, 1_440, 2_160]

    static func options(from descriptors: [PlaybackVariantDescriptor]) -> [PlaybackQualityOption] {
        let valid = descriptors.compactMap(option(from:))
        let grouped = Dictionary(grouping: valid, by: \.tierHeight)
        return grouped.values
            .compactMap { variants in
                variants.max { effectiveBitRate($0) < effectiveBitRate($1) }
            }
            .sorted { $0.tierHeight > $1.tierHeight }
    }

    static func options(
        from descriptors: [PlaybackVariantDescriptor],
        fallbackTracks: [PlaybackTrackDescriptor]
    ) -> [PlaybackQualityOption] {
        let variantOptions = options(from: descriptors)
        guard variantOptions.isEmpty else {
            return variantOptions
        }

        let fallbackDescriptors = fallbackTracks.compactMap { track -> PlaybackVariantDescriptor? in
            guard track.isPlayable else { return nil }
            return PlaybackVariantDescriptor(
                width: track.width,
                height: track.height,
                averageBitRate: track.estimatedBitRate,
                peakBitRate: nil
            )
        }
        return options(from: fallbackDescriptors)
    }

    static func tierHeight(width: Int, height: Int) -> Int? {
        let landscapeWidth = max(width, height)
        let landscapeHeight = min(width, height)
        guard landscapeHeight >= 144 else { return nil }
        let aspectRatio = Double(landscapeWidth) / Double(landscapeHeight)
        guard aspectRatio <= 3 else { return nil }

        switch (landscapeWidth, landscapeHeight) {
        case let (width, height) where width >= 3_840 || height >= 2_160:
            return 2_160
        case let (width, height) where width >= 2_560 || height >= 1_440:
            return 1_440
        case let (width, height) where width >= 1_920 || height >= 1_080:
            return 1_080
        case let (width, height) where width >= 1_280 || height >= 720:
            return 720
        case let (width, height) where width >= 1_024 && height >= 576:
            return 576
        case let (width, height) where width >= 854 || height >= 480:
            return 480
        case let (width, height) where width >= 640 || height >= 360:
            return 360
        case let (width, height) where width >= 426 || height >= 240:
            return 240
        case let (width, height) where width >= 256 || height >= 144:
            return 144
        default:
            return nil
        }
    }

    static func normalizedTier(from providerValue: Int) -> Int? {
        providerTiers.contains(providerValue) ? providerValue : nil
    }

    private static func option(from descriptor: PlaybackVariantDescriptor) -> PlaybackQualityOption? {
        guard
            (1...8_192).contains(descriptor.width),
            (1...4_320).contains(descriptor.height),
            tierHeight(width: descriptor.width, height: descriptor.height) != nil,
            valid(bitRate: descriptor.averageBitRate),
            valid(bitRate: descriptor.peakBitRate)
        else {
            return nil
        }
        return PlaybackQualityOption(
            width: descriptor.width,
            height: descriptor.height,
            averageBitRate: descriptor.averageBitRate,
            peakBitRate: descriptor.peakBitRate
        )
    }

    private static func valid(bitRate: Double?) -> Bool {
        guard let bitRate else { return true }
        return bitRate.isFinite && bitRate > 0 && bitRate <= 1_000_000_000
    }

    private static func effectiveBitRate(_ option: PlaybackQualityOption) -> Double {
        option.peakBitRate ?? option.averageBitRate ?? 0
    }
}

enum PlaybackQualityMenuProjector {
    static func options(
        adaptiveOptions: [PlaybackQualityOption],
        providerSources: [ProviderPlaybackSource]
    ) -> [PlaybackQualityMenuOption] {
        let adaptiveByTier = firstAdaptiveOptionByTier(adaptiveOptions)
        let providerByTier = firstProviderSourceByTier(providerSources)
        let tiers = Set(adaptiveByTier.keys).union(providerByTier.keys)
        return tiers
            .sorted(by: >)
            .map { tier in
                PlaybackQualityMenuOption(
                    tierHeight: tier,
                    adaptiveOption: adaptiveByTier[tier],
                    providerSource: providerByTier[tier]
                )
            }
    }

    private static func firstAdaptiveOptionByTier(
        _ options: [PlaybackQualityOption]
    ) -> [Int: PlaybackQualityOption] {
        options.reduce(into: [:]) { tiers, option in
            guard tiers[option.tierHeight] == nil else { return }
            tiers[option.tierHeight] = option
        }
    }

    private static func firstProviderSourceByTier(
        _ sources: [ProviderPlaybackSource]
    ) -> [Int: ProviderPlaybackSource] {
        sources.reduce(into: [:]) { tiers, source in
            guard tiers[source.tierHeight] == nil else { return }
            tiers[source.tierHeight] = source
        }
    }

    static func maximumTier(from catalogQuality: String?) -> Int? {
        guard let catalogQuality else { return nil }
        let normalized = catalogQuality
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if normalized.contains("4K") {
            return 2_160
        }
        let digits = normalized.filter(\.isNumber)
        guard let height = Int(digits), height > 0 else {
            return nil
        }
        return PlaybackQualityProjector.tierHeight(
            width: Int((Double(height) * 16 / 9).rounded()),
            height: height
        )
    }
}

enum PlaybackQualitySelector {
    static func select(
        from options: [PlaybackQualityOption],
        targetHeight: Int,
        fallbackToHighest: Bool = false
    ) -> PlaybackQualityOption? {
        guard !options.isEmpty else { return nil }
        if let exact = options.first(where: { $0.tierHeight == targetHeight }) {
            return exact
        }
        if fallbackToHighest {
            return options.first
        }
        return options.first(where: { $0.tierHeight < targetHeight }) ?? options.first
    }
}

protocol PlaybackQualityLoading: Sendable {
    func loadOptions(for url: URL) async throws -> [PlaybackQualityOption]
}

struct AVAssetPlaybackQualityLoader: PlaybackQualityLoading {
    func loadOptions(for url: URL) async throws -> [PlaybackQualityOption] {
        let asset = AVURLAsset(url: url)
        let variants = try await asset.load(.variants)
        let variantDescriptors = variants.compactMap { variant -> PlaybackVariantDescriptor? in
            guard let size = variant.videoAttributes?.presentationSize else {
                return nil
            }
            guard let dimensions = dimensions(from: size) else { return nil }
            return PlaybackVariantDescriptor(
                width: dimensions.width,
                height: dimensions.height,
                averageBitRate: variant.averageBitRate,
                peakBitRate: variant.peakBitRate
            )
        }

        let variantOptions = PlaybackQualityProjector.options(from: variantDescriptors)
        guard variantOptions.isEmpty else {
            return variantOptions
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        var fallbackTracks: [PlaybackTrackDescriptor] = []
        for track in tracks {
            let isPlayable = try await track.load(.isPlayable)
            guard isPlayable else { continue }

            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let presentationSize = naturalSize.applying(transform)
            guard let dimensions = dimensions(from: presentationSize) else { continue }

            let estimatedDataRate = Double(try await track.load(.estimatedDataRate))
            fallbackTracks.append(PlaybackTrackDescriptor(
                width: dimensions.width,
                height: dimensions.height,
                estimatedBitRate: estimatedDataRate > 0 ? estimatedDataRate : nil,
                isPlayable: true
            ))
        }

        return PlaybackQualityProjector.options(
            from: variantDescriptors,
            fallbackTracks: fallbackTracks
        )
    }

    private func dimensions(from size: CGSize) -> (width: Int, height: Int)? {
        let width = abs(size.width).rounded()
        let height = abs(size.height).rounded()
        guard
            width.isFinite,
            height.isFinite,
            let exactWidth = Int(exactly: width),
            let exactHeight = Int(exactly: height)
        else {
            return nil
        }
        return (exactWidth, exactHeight)
    }
}

@MainActor
final class PlaybackQualityPreferenceStore {
    private struct Payload: Codable {
        let version: Int
        let targetHeight: Int
        let isManualSelection: Bool?
    }

    static let defaultTargetHeight = 1_080

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "aiyifanPlaybackQualityV1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    var targetHeight: Int {
        guard
            let data = defaults.data(forKey: storageKey),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.version == 1,
            Self.isValid(height: payload.targetHeight)
        else {
            return Self.defaultTargetHeight
        }
        return payload.targetHeight
    }

    var hasManualSelection: Bool {
        guard
            let data = defaults.data(forKey: storageKey),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.version == 1,
            Self.isValid(height: payload.targetHeight)
        else {
            return false
        }
        return payload.isManualSelection ?? true
    }

    func setTargetHeight(_ height: Int) {
        guard Self.isValid(height: height) else { return }
        let payload = Payload(version: 1, targetHeight: height, isManualSelection: true)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func setAutomatic() {
        let payload = Payload(
            version: 1,
            targetHeight: Self.defaultTargetHeight,
            isManualSelection: false
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func isValid(height: Int) -> Bool {
        (144...4_320).contains(height)
    }
}
