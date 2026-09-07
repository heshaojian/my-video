import AVFoundation
import Foundation

struct PlaybackVariantDescriptor: Equatable, Sendable {
    let width: Int
    let height: Int
    let averageBitRate: Double?
    let peakBitRate: Double?
}

struct PlaybackQualityOption: Equatable, Identifiable, Sendable {
    let width: Int
    let height: Int
    let averageBitRate: Double?
    let peakBitRate: Double?

    var id: Int { height }
    var title: String { "\(height)p" }
}

enum PlaybackQualityProjector {
    static func options(from descriptors: [PlaybackVariantDescriptor]) -> [PlaybackQualityOption] {
        let valid = descriptors.compactMap(option(from:))
        let grouped = Dictionary(grouping: valid, by: \.height)
        return grouped.values
            .compactMap { variants in
                variants.max { effectiveBitRate($0) < effectiveBitRate($1) }
            }
            .sorted { $0.height > $1.height }
    }

    private static func option(from descriptor: PlaybackVariantDescriptor) -> PlaybackQualityOption? {
        guard
            (1...8_192).contains(descriptor.width),
            (1...4_320).contains(descriptor.height),
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

enum PlaybackQualitySelector {
    static func select(
        from options: [PlaybackQualityOption],
        targetHeight: Int,
        fallbackToHighest: Bool = false
    ) -> PlaybackQualityOption? {
        guard !options.isEmpty else { return nil }
        if let exact = options.first(where: { $0.height == targetHeight }) {
            return exact
        }
        if fallbackToHighest {
            return options.first
        }
        return options.first(where: { $0.height < targetHeight }) ?? options.first
    }
}

protocol PlaybackQualityLoading: Sendable {
    func loadOptions(for url: URL) async throws -> [PlaybackQualityOption]
}

struct AVAssetPlaybackQualityLoader: PlaybackQualityLoading {
    func loadOptions(for url: URL) async throws -> [PlaybackQualityOption] {
        let asset = AVURLAsset(url: url)
        let variants = try await asset.load(.variants)
        let descriptors = variants.compactMap { variant -> PlaybackVariantDescriptor? in
            guard let size = variant.videoAttributes?.presentationSize else {
                return nil
            }
            let width = size.width.rounded()
            let height = size.height.rounded()
            guard
                width.isFinite,
                height.isFinite,
                let exactWidth = Int(exactly: width),
                let exactHeight = Int(exactly: height)
            else {
                return nil
            }
            return PlaybackVariantDescriptor(
                width: exactWidth,
                height: exactHeight,
                averageBitRate: variant.averageBitRate,
                peakBitRate: variant.peakBitRate
            )
        }
        return PlaybackQualityProjector.options(from: descriptors)
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

    private static func isValid(height: Int) -> Bool {
        (144...4_320).contains(height)
    }
}
