import CoreFoundation
import Foundation

struct PlaybackCertificate: Equatable, Sendable {
    let publicKey: String
    let privateKey: String
}

struct NativePlaybackEntry: Equatable, Sendable {
    let url: URL
    let isAdvertisement: Bool
}

struct NativePlayback: Equatable, Sendable {
    let entries: [NativePlaybackEntry]
    let episodes: [Episode]
    let selectedEpisode: Episode?
    let metrics: ViewerMetrics?

    var episodeTitle: String? {
        selectedEpisode?.title
    }

    init(
        entries: [NativePlaybackEntry],
        episodes: [Episode] = [],
        selectedEpisode: Episode? = nil,
        metrics: ViewerMetrics? = nil
    ) {
        self.entries = entries
        self.episodes = episodes
        self.selectedEpisode = selectedEpisode
        self.metrics = metrics
    }
}

struct ViewerMetrics: Equatable, Sendable {
    let likes: Int?
    let favorites: Int?
    let score: Double?
    let views: Int?

    var isEmpty: Bool {
        likes == nil && favorites == nil && score == nil && views == nil
    }
}

struct VideoPlaybackContext: Equatable, Sendable {
    let isSerial: Bool
    let categoryID: String
    let metrics: ViewerMetrics
}

enum SerialPlaybackIntent {
    static func infer(
        providerIsSerial: Bool,
        item: AiyifanItem,
        preferredEpisodeKey: String? = nil
    ) -> Bool {
        if providerIsSerial || item.isSerial == true || preferredEpisodeKey != nil {
            return true
        }
        if item.isSerial == false {
            return false
        }
        if item.latestEpisodeKey != nil {
            return true
        }
        let categoryParts = item.categoryPath?.split(separator: ",").map(String.init) ?? []
        return categoryParts.count >= 3 && ["4", "5", "6"].contains(categoryParts[2])
    }
}

struct EpisodeSelection: Codable, Equatable, Sendable {
    let mediaKey: String
    let title: String
}

enum EpisodeNumberParser {
    static func number(in providerTitle: String) -> Int? {
        let trimmed = providerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed) {
            return number
        }
        if trimmed.hasPrefix("第"), trimmed.hasSuffix("集") {
            let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(inner)
        }
        let components = trimmed.split(whereSeparator: \.isWhitespace)
        guard
            components.count == 2,
            components[0].caseInsensitiveCompare("Episode") == .orderedSame
        else {
            return nil
        }
        return Int(components[1])
    }
}

enum NativePlaybackError: Error, Equatable {
    case invalidMediaKey
    case unsupportedSite
    case missingConfiguration
    case invalidResponse
    case loginRequired
    case previewOnly
    case unsupportedMedia
}

enum ProviderRegion {
    static let fallback = "US"

    static var device: String {
        normalized(Locale.current.region?.identifier)
    }

    static func normalized(_ candidate: String?) -> String {
        guard let candidate else { return fallback }
        let normalized = candidate.uppercased()
        guard
            normalized.utf8.count == 2,
            normalized.utf8.allSatisfy({ (65...90).contains($0) })
        else {
            return fallback
        }
        return normalized
    }
}

extension NativePlaybackError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidMediaKey:
            return "This title has an invalid media identifier."
        case .unsupportedSite:
            return "This title is not hosted by a supported Aiyifan site."
        case .missingConfiguration:
            return "Aiyifan did not provide the playback configuration."
        case .invalidResponse:
            return "Aiyifan returned an invalid playback response."
        case .loginRequired:
            return "This title requires you to sign in on the website."
        case .previewOnly:
            return "Only a preview is available for this title."
        case .unsupportedMedia:
            return "A compatible full-length stream is not available."
        }
    }
}

enum PlaybackCertificateParser {
    static func parse(_ data: Data) throws -> PlaybackCertificate {
        guard
            data.count <= 1_000_000,
            let html = String(data: data, encoding: .utf8),
            let start = html.range(of: "var injectJson = ")?.upperBound,
            let end = html[start...].range(of: "};")?.lowerBound
        else {
            throw NativePlaybackError.missingConfiguration
        }

        let json = String(html[start...end])
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let pageCertificate = pConfig(in: root),
            let publicKey = pageCertificate["publicKey"] as? String,
            let privateKey = (pageCertificate["privateKey"] as? [String])?.first,
            !publicKey.isEmpty,
            publicKey.count <= 1_024,
            !privateKey.isEmpty,
            privateKey.count <= 1_024
        else {
            throw NativePlaybackError.missingConfiguration
        }

        return PlaybackCertificate(publicKey: publicKey, privateKey: privateKey)
    }

    private static func pConfig(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let pageCertificate = dictionary["pConfig"] as? [String: Any] {
                return pageCertificate
            }
            for nested in dictionary.values {
                if let pageCertificate = pConfig(in: nested) {
                    return pageCertificate
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for nested in array {
                if let pageCertificate = pConfig(in: nested) {
                    return pageCertificate
                }
            }
        }
        return nil
    }
}

enum NativePlaybackRequestBuilder {
    static func makeURL(
        mediaKey: String,
        albumMode: Bool = true,
        siteHost: String,
        certificate: PlaybackCertificate,
        region: String = ProviderRegion.device
    ) throws -> URL {
        let region = ProviderRegion.normalized(region)
        let parameters = [
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "id", value: mediaKey),
            URLQueryItem(name: "a", value: albumMode ? "1" : "0"),
            URLQueryItem(name: "usersign", value: "1"),
            URLQueryItem(name: "region", value: region),
            URLQueryItem(name: "device", value: "1"),
            URLQueryItem(name: "isMasterSupport", value: "1"),
            URLQueryItem(name: "lang", value: "none")
        ]
        try validateMediaKey(mediaKey)
        return try ProviderRequestSigner.makeSignedURL(
            path: "/v3/video/play",
            parameters: parameters,
            siteHost: siteHost,
            certificate: certificate
        )
    }

    static func makeDetailURL(
        mediaKey: String,
        siteHost: String,
        certificate: PlaybackCertificate,
        region: String = ProviderRegion.device
    ) throws -> URL {
        let region = ProviderRegion.normalized(region)
        let parameters = [
            URLQueryItem(name: "ispath", value: "false"),
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "device", value: "1"),
            URLQueryItem(name: "player", value: "CkPlayer"),
            URLQueryItem(name: "tech", value: "HLS"),
            URLQueryItem(name: "country", value: "HU"),
            URLQueryItem(name: "lang", value: "cns"),
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: mediaKey),
            URLQueryItem(name: "region", value: region)
        ]
        try validateMediaKey(mediaKey)
        return try ProviderRequestSigner.makeSignedURL(
            path: "/v3/video/detail",
            parameters: parameters,
            siteHost: siteHost,
            certificate: certificate
        )
    }

    static func makePlaylistURL(
        seriesKey: String,
        categoryID: String,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        guard categoryID.range(of: #"^[0-9,]{1,128}$"#, options: .regularExpression) != nil else {
            throw NativePlaybackError.invalidResponse
        }
        let parameters = [
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "vid", value: seriesKey),
            URLQueryItem(name: "lsk", value: "1"),
            URLQueryItem(name: "taxis", value: "0"),
            URLQueryItem(name: "cid", value: categoryID)
        ]
        try validateMediaKey(seriesKey)
        return try ProviderRequestSigner.makeSignedURL(
            path: "/v3/video/languagesplaylist",
            parameters: parameters,
            siteHost: siteHost,
            certificate: certificate
        )
    }

    private static func validateMediaKey(_ mediaKey: String) throws {
        guard mediaKey.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            throw NativePlaybackError.invalidMediaKey
        }
    }
}

enum VideoDetailResponseDecoder {
    static func decode(_ data: Data) throws -> VideoPlaybackContext {
        let info = try APIResponseParser.firstInfo(from: data)
        guard
            let isSerial = APIResponseParser.boolean(info["isSerial"]),
            let categoryID = info["cid"] as? String,
            !categoryID.isEmpty
        else {
            throw NativePlaybackError.invalidResponse
        }
        return VideoPlaybackContext(
            isSerial: isSerial,
            categoryID: categoryID,
            metrics: ViewerMetrics(
                likes: APIResponseParser.nonnegativeCount(info["good"]),
                favorites: APIResponseParser.nonnegativeCount(info["favoriteCount"]),
                score: APIResponseParser.score(info["score"]),
                views: APIResponseParser.nonnegativeCount(info["view"])
            )
        )
    }
}

enum EpisodePlaylistResponseDecoder {
    static func decodeEpisodes(_ data: Data) throws -> [Episode] {
        let info = try APIResponseParser.firstInfo(from: data)
        guard
            let episodes = info["playList"] as? [[String: Any]],
            !episodes.isEmpty,
            episodes.count <= 2_000
        else {
            if let episodes = info["playList"] as? [[String: Any]], episodes.count > 2_000 {
                throw NativePlaybackError.invalidResponse
            }
            throw NativePlaybackError.unsupportedMedia
        }

        let decoded = episodes.compactMap { raw -> Episode? in
            guard
                let mediaKey = raw["key"] as? String,
                let title = raw["name"] as? String,
                mediaKey.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
                !title.isEmpty,
                title.count <= 200,
                title.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                return nil
            }
            let rawDate = raw["updateDate"] as? String
            guard rawDate?.count ?? 0 <= 64 else {
                return nil
            }
            return Episode(
                mediaKey: mediaKey,
                title: title,
                updateDate: rawDate?.isEmpty == false ? rawDate : nil
            )
        }
        guard !decoded.isEmpty else {
            throw NativePlaybackError.unsupportedMedia
        }

        let firstIndexes = Dictionary(
            decoded.enumerated().map { ($0.element.mediaKey, $0.offset) },
            uniquingKeysWith: min
        )
        let sortableEpisodes: [(index: Int, episode: Episode, date: Date?, number: Int?)] = decoded.enumerated().compactMap { index, episode in
            guard firstIndexes[episode.mediaKey] == index else {
                return nil
            }
            return (
                index: index,
                episode: episode,
                date: parsedDate(episode.updateDate),
                number: episodeNumber(episode.title)
            )
        }

        return sortableEpisodes.sorted { left, right in
            if
                let leftDate = left.date,
                let rightDate = right.date,
                leftDate != rightDate
            {
                return leftDate > rightDate
            }
            let leftNumber = left.number
            let rightNumber = right.number
            if let leftNumber, let rightNumber, leftNumber != rightNumber {
                return leftNumber > rightNumber
            }
            if (leftNumber != nil) != (rightNumber != nil) {
                return leftNumber != nil
            }
            return left.index < right.index
        }
        .map { $0.episode }
    }

    static func selectEpisode(from episodes: [Episode], preferredKey: String?) -> Episode? {
        guard let preferredKey else {
            return episodes.first
        }
        return episodes.first { $0.mediaKey == preferredKey } ?? episodes.first
    }

    static func decodeLatestEpisode(_ data: Data) throws -> EpisodeSelection {
        guard let episode = selectEpisode(from: try decodeEpisodes(data), preferredKey: nil) else {
            throw NativePlaybackError.unsupportedMedia
        }
        return EpisodeSelection(mediaKey: episode.mediaKey, title: episode.title)
    }

    private static func episodeNumber(_ title: String) -> Int? {
        EpisodeNumberParser.number(in: title)
    }

    private static func parsedDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: rawValue) {
            return date
        }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }
        return nil
    }
}

private enum APIResponseParser {
    static func firstInfo(from data: Data) throws -> [String: Any] {
        guard data.count <= 2_000_000 else {
            throw NativePlaybackError.invalidResponse
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NativePlaybackError.invalidResponse
        }
        guard
            let envelope = object as? [String: Any],
            integer(envelope["ret"]) == 200,
            let payload = envelope["data"] as? [String: Any],
            integer(payload["code"]) == 0,
            let info = (payload["info"] as? [[String: Any]])?.first
        else {
            throw NativePlaybackError.invalidResponse
        }
        return info
    }

    static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return nil
            }
            let exactValue = value.doubleValue
            guard exactValue.isFinite, exactValue.rounded(.towardZero) == exactValue else {
                return nil
            }
            return Int(exactly: exactValue)
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            switch value.doubleValue {
            case 0: return false
            case 1: return true
            default: return nil
            }
        }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    static func nonnegativeCount(_ value: Any?) -> Int? {
        guard let value = integer(value), (0...1_000_000_000).contains(value) else {
            return nil
        }
        return value
    }

    static func score(_ value: Any?) -> Double? {
        let decoded: Double?
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return nil
            }
            decoded = value.doubleValue
        } else if let value = value as? String {
            decoded = Double(value)
        } else {
            decoded = nil
        }
        guard let decoded, decoded.isFinite, (0...10).contains(decoded) else {
            return nil
        }
        return decoded
    }
}

enum NativePlaybackResponseDecoder {
    private struct Media {
        let raw: [String: Any]

        var duration: Double {
            (raw["duration"] as? NSNumber)?.doubleValue ?? 0
        }

        var isHLS: Bool {
            (raw["isHls"] as? NSNumber)?.boolValue == true
        }

        var bitrate: Int {
            (raw["bitrate"] as? NSNumber)?.intValue ?? 0
        }

        var secureURL: URL? {
            guard
                let rawURL = (raw["result"] as? String) ?? (raw["rtmp"] as? String),
                let url = URL(string: rawURL),
                url.scheme?.lowercased() == "https",
                let host = url.host,
                url.user == nil,
                url.password == nil,
                RemoteResourceHostValidator.isAllowedMediaHost(host)
            else {
                return nil
            }
            return url
        }
    }

    static func decode(_ data: Data) throws -> NativePlayback {
        guard data.count <= 2_000_000 else {
            throw NativePlaybackError.invalidResponse
        }
        let info = try APIResponseParser.firstInfo(from: data)
        guard let rawMedia = info["flvPathList"] as? [[String: Any]] else {
            throw NativePlaybackError.invalidResponse
        }
        guard APIResponseParser.integer(info["needLogin"]) == 0 else {
            throw NativePlaybackError.loginRequired
        }
        guard let isPreview = APIResponseParser.boolean(info["isPreView"]) else {
            throw NativePlaybackError.invalidResponse
        }
        guard !isPreview else {
            throw NativePlaybackError.previewOnly
        }
        let media = rawMedia.map(Media.init(raw:))
        guard let programIndex = media.firstIndex(where: {
            $0.isHLS && $0.bitrate > 0
        }), let programURL = media[programIndex].secureURL else {
            throw NativePlaybackError.unsupportedMedia
        }

        let program = NativePlaybackEntry(url: programURL, isAdvertisement: false)
        return NativePlayback(entries: [program])
    }

}

protocol NativePlaybackResolving: Sendable {
    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback
}

protocol EpisodePlaylistResolving: Sendable {
    func loadEpisodes(for item: AiyifanItem, expectedEpisodeKey: String?) async throws -> [Episode]
}

extension NativePlaybackResolving {
    func resolve(item: AiyifanItem) async throws -> NativePlayback {
        try await resolve(item: item, preferredEpisodeKey: nil)
    }
}

struct NativePlaybackResolver: NativePlaybackResolving, EpisodePlaylistResolving {
    private let session: URLSession
    private let playlistRetryDelays: [Duration]
    private let certificateCache: ProviderCertificateCache
    private let region: String

    init(
        session: URLSession? = nil,
        playlistRetryDelays: [Duration] = [.milliseconds(500), .milliseconds(1_500), .seconds(3)],
        certificateCache: ProviderCertificateCache? = nil,
        region: String = ProviderRegion.device
    ) {
        self.session = session ?? ProviderSessionFactory.make()
        self.playlistRetryDelays = playlistRetryDelays
        self.certificateCache = certificateCache ?? (session == nil ? .shared : ProviderCertificateCache())
        self.region = ProviderRegion.normalized(region)
    }

    static func validatePage(_ item: AiyifanItem) throws -> String {
        guard
            item.playURL.scheme?.lowercased() == "https",
            let pageHost = item.playURL.host
        else {
            throw NativePlaybackError.unsupportedSite
        }
        _ = try NativePlaybackRequestBuilder.makeURL(
            mediaKey: item.listPath,
            siteHost: pageHost,
            certificate: PlaybackCertificate(publicKey: "validation", privateKey: "validation")
        )
        return pageHost
    }

    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        let pageHost = try Self.validatePage(item)
        return try await withFreshCertificateRetry(pageHost: pageHost) {
            try await resolveOnce(
                item: item,
                preferredEpisodeKey: preferredEpisodeKey,
                pageHost: pageHost
            )
        }
    }

    private func resolveOnce(
        item: AiyifanItem,
        preferredEpisodeKey: String?,
        pageHost: String
    ) async throws -> NativePlayback {
        let certificate = try await certificate(for: item, pageHost: pageHost)
        let detailURL = try NativePlaybackRequestBuilder.makeDetailURL(
            mediaKey: item.listPath,
            siteHost: pageHost,
            certificate: certificate,
            region: region
        )
        let detailData = try await fetch(detailURL, referer: item.playURL)
        let context = try VideoDetailResponseDecoder.decode(detailData)
        let mediaKey: String
        let episodes: [Episode]
        let selectedEpisode: Episode?
        let requestedEpisodeKey = preferredEpisodeKey ?? item.latestEpisodeKey
        let isSerial = SerialPlaybackIntent.infer(
            providerIsSerial: context.isSerial,
            item: item,
            preferredEpisodeKey: preferredEpisodeKey
        )
        if isSerial {
            if preferredEpisodeKey == nil,
               let latestEpisodeKey = item.latestEpisodeKey {
                let episode = Episode(
                    mediaKey: latestEpisodeKey,
                    title: item.latestEpisodeTitle ?? latestEpisodeKey,
                    updateDate: nil
                )
                episodes = []
                mediaKey = episode.mediaKey
                selectedEpisode = episode
            } else {
                let playlistURL = try NativePlaybackRequestBuilder.makePlaylistURL(
                    seriesKey: item.listPath,
                    categoryID: context.categoryID,
                    siteHost: pageHost,
                    certificate: certificate
                )
                episodes = try await fetchEpisodes(
                    playlistURL,
                    referer: item.playURL,
                    expectedEpisodeKey: requestedEpisodeKey
                )
                guard let episode = EpisodePlaylistResponseDecoder.selectEpisode(
                    from: episodes,
                    preferredKey: requestedEpisodeKey
                ) else {
                    throw NativePlaybackError.unsupportedMedia
                }
                mediaKey = episode.mediaKey
                selectedEpisode = episode
            }
        } else {
            mediaKey = item.listPath
            episodes = []
            selectedEpisode = nil
        }
        let playbackURL = try NativePlaybackRequestBuilder.makeURL(
            mediaKey: mediaKey,
            albumMode: !isSerial,
            siteHost: pageHost,
            certificate: certificate,
            region: region
        )
        let playbackData = try await fetch(playbackURL, referer: item.playURL)
        let playback = try NativePlaybackResponseDecoder.decode(playbackData)
        return NativePlayback(
            entries: playback.entries,
            episodes: episodes,
            selectedEpisode: selectedEpisode,
            metrics: context.metrics.isEmpty ? nil : context.metrics
        )
    }

    func loadEpisodes(for item: AiyifanItem, expectedEpisodeKey: String?) async throws -> [Episode] {
        let pageHost = try Self.validatePage(item)
        return try await withFreshCertificateRetry(pageHost: pageHost) {
            try await loadEpisodesOnce(
                for: item,
                expectedEpisodeKey: expectedEpisodeKey,
                pageHost: pageHost
            )
        }
    }

    private func loadEpisodesOnce(
        for item: AiyifanItem,
        expectedEpisodeKey: String?,
        pageHost: String
    ) async throws -> [Episode] {
        let certificate = try await certificate(for: item, pageHost: pageHost)
        let detailURL = try NativePlaybackRequestBuilder.makeDetailURL(
            mediaKey: item.listPath,
            siteHost: pageHost,
            certificate: certificate,
            region: region
        )
        let detailData = try await fetch(detailURL, referer: item.playURL)
        let context = try VideoDetailResponseDecoder.decode(detailData)
        guard SerialPlaybackIntent.infer(providerIsSerial: context.isSerial, item: item) else {
            return []
        }
        let playlistURL = try NativePlaybackRequestBuilder.makePlaylistURL(
            seriesKey: item.listPath,
            categoryID: context.categoryID,
            siteHost: pageHost,
            certificate: certificate
        )
        return try await fetchEpisodes(
            playlistURL,
            referer: item.playURL,
            expectedEpisodeKey: expectedEpisodeKey
        )
    }

    private func withFreshCertificateRetry<T>(
        pageHost: String,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as NativePlaybackError where error == .invalidResponse {
            guard let domain = RemoteResourceHostValidator.matchingProviderDomain(for: pageHost) else {
                throw NativePlaybackError.unsupportedSite
            }
            await certificateCache.invalidate(for: domain)
            try Task.checkCancellation()
            return try await operation()
        }
    }

    private func fetchEpisodes(
        _ url: URL,
        referer: URL,
        expectedEpisodeKey: String?
    ) async throws -> [Episode] {
        var attempt = 0
        while true {
            do {
                let data = try await fetch(url, referer: referer)
                let episodes = try EpisodePlaylistResponseDecoder.decodeEpisodes(data)
                if let expectedEpisodeKey,
                   !episodes.contains(where: { $0.mediaKey == expectedEpisodeKey }) {
                    throw NativePlaybackError.invalidResponse
                }
                return episodes
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < playlistRetryDelays.count, shouldRetryPlaylist(error) else {
                    throw error
                }
                let delay = playlistRetryDelays[attempt]
                attempt += 1
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
            }
        }
    }

    private func shouldRetryPlaylist(_ error: Error) -> Bool {
        if let playbackError = error as? NativePlaybackError {
            return playbackError == .invalidResponse || playbackError == .unsupportedMedia
        }
        return error is URLError
    }

    private func certificate(for item: AiyifanItem, pageHost: String) async throws -> PlaybackCertificate {
        guard let domain = RemoteResourceHostValidator.matchingProviderDomain(for: pageHost) else {
            throw NativePlaybackError.unsupportedSite
        }
        return try await certificateCache.certificate(for: domain) {
            var request = URLRequest(url: item.playURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            try validate(response, maximumBytes: 1_000_000, actualBytes: data.count)
            return try PlaybackCertificateParser.parse(data)
        }
    }

    private func fetch(_ url: URL, referer: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try validate(response, maximumBytes: 2_000_000, actualBytes: data.count)
        return data
    }

    private func validate(_ response: URLResponse, maximumBytes: Int, actualBytes: Int) throws {
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            actualBytes <= maximumBytes
        else {
            throw NativePlaybackError.invalidResponse
        }
        guard
            httpResponse.url?.scheme?.lowercased() == "https",
            let finalHost = httpResponse.url?.host,
            RemoteResourceHostValidator.matchingProviderDomain(for: finalHost) != nil
        else {
            throw NativePlaybackError.unsupportedSite
        }
    }
}

extension NativePlaybackResolver: SavedEpisodeResolving {
    func episodesForSavedUpdate(
        for item: AiyifanItem,
        expectedEpisodeKey: String?
    ) async throws -> [EpisodeSelection]? {
        let pageHost = try Self.validatePage(item)
        return try await withFreshCertificateRetry(pageHost: pageHost) {
            try await episodesForSavedUpdateOnce(
                for: item,
                expectedEpisodeKey: expectedEpisodeKey,
                pageHost: pageHost
            )
        }
    }

    private func episodesForSavedUpdateOnce(
        for item: AiyifanItem,
        expectedEpisodeKey: String?,
        pageHost: String
    ) async throws -> [EpisodeSelection]? {
        let certificate = try await certificate(for: item, pageHost: pageHost)
        let detailURL = try NativePlaybackRequestBuilder.makeDetailURL(
            mediaKey: item.listPath,
            siteHost: pageHost,
            certificate: certificate,
            region: region
        )
        let detailData = try await fetch(detailURL, referer: item.playURL)
        let context = try VideoDetailResponseDecoder.decode(detailData)
        let isSerial = SerialPlaybackIntent.infer(providerIsSerial: context.isSerial, item: item)
        guard isSerial else { return nil }

        let playlistURL = try NativePlaybackRequestBuilder.makePlaylistURL(
            seriesKey: item.listPath,
            categoryID: context.categoryID,
            siteHost: pageHost,
            certificate: certificate
        )
        let episodes = try await fetchEpisodes(
            playlistURL,
            referer: item.playURL,
            expectedEpisodeKey: expectedEpisodeKey
        )
        guard !episodes.isEmpty else {
            throw NativePlaybackError.unsupportedMedia
        }
        return episodes.map { EpisodeSelection(mediaKey: $0.mediaKey, title: $0.title) }
    }
}

struct FixtureNativePlaybackResolver: NativePlaybackResolving, EpisodePlaylistResolving, SavedEpisodeResolving {
    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        let isSerial = item.isSerial == true || item.latestEpisodeKey != nil || preferredEpisodeKey != nil
        let episodes = [
            Episode(mediaKey: "episode-10", title: "10", updateDate: "2026-09-07T10:00:00Z"),
            Episode(mediaKey: "episode-4", title: "04", updateDate: "2026-09-06T15:00:00Z"),
            Episode(mediaKey: "episode-2", title: "02", updateDate: "2026-09-06T10:00:00Z")
        ]
        let selected = isSerial ? (episodes.first { $0.mediaKey == preferredEpisodeKey } ?? episodes[0]) : nil
        let usesPlayableMedia = ProcessInfo.processInfo.arguments.contains("-AiyifanUsePlayableFixtureMedia")
        let programURL = usesPlayableMedia
            ? URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!
            : URL(string: "https://media.example.com/\(selected?.mediaKey ?? item.listPath).m3u8")!
        return NativePlayback(
            entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/advertisement.mp4")!,
                    isAdvertisement: true
                ),
                NativePlaybackEntry(
                    url: programURL,
                    isAdvertisement: false
                )
            ],
            episodes: isSerial ? episodes : [],
            selectedEpisode: selected,
            metrics: ViewerMetrics(likes: 76, favorites: 221, score: 9.6, views: 170_000)
        )
    }

    func episodesForSavedUpdate(
        for item: AiyifanItem,
        expectedEpisodeKey: String?
    ) async throws -> [EpisodeSelection]? {
        guard item.isSerial == true || item.latestEpisodeKey != nil else { return nil }
        return try await loadEpisodes(for: item, expectedEpisodeKey: expectedEpisodeKey)
            .map { EpisodeSelection(mediaKey: $0.mediaKey, title: $0.title) }
    }

    func loadEpisodes(for item: AiyifanItem, expectedEpisodeKey: String?) async throws -> [Episode] {
        guard item.isSerial == true || item.latestEpisodeKey != nil || expectedEpisodeKey != nil else {
            return []
        }
        return [
            Episode(mediaKey: "episode-10", title: "10", updateDate: "2026-09-07T10:00:00Z"),
            Episode(mediaKey: "episode-4", title: "04", updateDate: "2026-09-06T15:00:00Z"),
            Episode(mediaKey: "episode-2", title: "02", updateDate: "2026-09-06T10:00:00Z")
        ]
    }
}
