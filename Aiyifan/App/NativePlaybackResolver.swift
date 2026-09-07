import CryptoKit
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

    var episodeTitle: String? {
        selectedEpisode?.title
    }

    init(entries: [NativePlaybackEntry], episodes: [Episode] = [], selectedEpisode: Episode? = nil) {
        self.entries = entries
        self.episodes = episodes
        self.selectedEpisode = selectedEpisode
    }
}

struct VideoPlaybackContext: Equatable, Sendable {
    let isSerial: Bool
    let categoryID: String
}

struct EpisodeSelection: Equatable, Sendable {
    let mediaKey: String
    let title: String
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
            let configuration = (root["config"] as? [[String: Any]])?.first,
            let pageCertificate = configuration["pConfig"] as? [String: Any],
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
}

enum NativePlaybackRequestBuilder {
    private static let supportedDomains = [
        "yfsp.tv", "yifan.tv", "yfsp.me", "ayf.tv", "aiyifan.tv",
        "wyav.tv", "flyv.tv", "jssp.tv", "iyf.tv", "lgsp.tv",
        "tripdata.app", "kubb.tv"
    ]

    static func makeURL(
        mediaKey: String,
        albumMode: Bool = true,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        let parameters = [
            URLQueryItem(name: "cinema", value: "1"),
            URLQueryItem(name: "id", value: mediaKey),
            URLQueryItem(name: "a", value: albumMode ? "1" : "0"),
            URLQueryItem(name: "usersign", value: "1"),
            URLQueryItem(name: "region", value: "GL."),
            URLQueryItem(name: "device", value: "1"),
            URLQueryItem(name: "isMasterSupport", value: "1")
        ]
        return try makeSignedURL(
            path: "/v3/video/play",
            parameters: parameters,
            mediaKey: mediaKey,
            siteHost: siteHost,
            certificate: certificate
        )
    }

    static func makeDetailURL(
        mediaKey: String,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
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
            URLQueryItem(name: "region", value: "GL.")
        ]
        return try makeSignedURL(
            path: "/v3/video/detail",
            parameters: parameters,
            mediaKey: mediaKey,
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
        return try makeSignedURL(
            path: "/v3/video/languagesplaylist",
            parameters: parameters,
            mediaKey: seriesKey,
            siteHost: siteHost,
            certificate: certificate
        )
    }

    private static func makeSignedURL(
        path: String,
        parameters: [URLQueryItem],
        mediaKey: String,
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        guard mediaKey.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            throw NativePlaybackError.invalidMediaKey
        }
        let normalizedHost = siteHost.lowercased()
        guard let domain = supportedDomains.first(where: {
            normalizedHost == $0 || normalizedHost.hasSuffix(".\($0)")
        }) else {
            throw NativePlaybackError.unsupportedSite
        }

        let unsignedQuery = parameters
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let signatureSource = "\(certificate.publicKey)&\(unsignedQuery.lowercased())&\(certificate.privateKey)"
        let signature = Insecure.MD5.hash(data: Data(signatureSource.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "m10.\(domain)"
        components.path = path
        components.queryItems = parameters + [
            URLQueryItem(name: "vv", value: signature),
            URLQueryItem(name: "pub", value: certificate.publicKey)
        ]

        guard let url = components.url else {
            throw NativePlaybackError.invalidResponse
        }
        return url
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
        return VideoPlaybackContext(isSerial: isSerial, categoryID: categoryID)
    }
}

enum EpisodePlaylistResponseDecoder {
    static func decodeEpisodes(_ data: Data) throws -> [Episode] {
        let info = try APIResponseParser.firstInfo(from: data)
        guard let episodes = info["playList"] as? [[String: Any]], !episodes.isEmpty else {
            throw NativePlaybackError.unsupportedMedia
        }

        let decoded = episodes.compactMap { raw -> Episode? in
            guard
                let mediaKey = raw["key"] as? String,
                let title = raw["name"] as? String,
                !mediaKey.isEmpty,
                !title.isEmpty
            else {
                return nil
            }
            let rawDate = raw["updateDate"] as? String
            return Episode(
                mediaKey: mediaKey,
                title: title,
                updateDate: rawDate?.isEmpty == false ? rawDate : nil
            )
        }
        guard !decoded.isEmpty else {
            throw NativePlaybackError.unsupportedMedia
        }

        return decoded.enumerated().sorted { left, right in
            if
                let leftDate = parsedDate(left.element.updateDate),
                let rightDate = parsedDate(right.element.updateDate),
                leftDate != rightDate
            {
                return leftDate > rightDate
            }
            let leftNumber = episodeNumber(left.element.title)
            let rightNumber = episodeNumber(right.element.title)
            if let leftNumber, let rightNumber, leftNumber != rightNumber {
                return leftNumber > rightNumber
            }
            if (leftNumber != nil) != (rightNumber != nil) {
                return leftNumber != nil
            }
            return left.offset < right.offset
        }
        .map(\.element)
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
        title.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.last
    }

    private static func parsedDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: rawValue) {
            return date
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
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
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
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
            return value.boolValue
        }
        if let value = value as? String {
            return ["true", "1"].contains(value.lowercased())
        }
        return nil
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
                isPublicMediaHost(host)
            else {
                return nil
            }
            return url
        }

        private func isPublicMediaHost(_ host: String) -> Bool {
            let normalized = host.lowercased()
            guard
                normalized != "localhost",
                normalized != "::1",
                !normalized.hasSuffix(".local"),
                !normalized.hasSuffix(".internal"),
                !normalized.contains(":")
            else {
                return false
            }

            let octets = normalized.split(separator: ".").compactMap { Int($0) }
            guard octets.count == 4 else {
                return true
            }
            guard octets.allSatisfy({ (0...255).contains($0) }) else {
                return false
            }
            return octets[0] != 0
                && octets[0] != 10
                && octets[0] != 127
                && !(octets[0] == 169 && octets[1] == 254)
                && !(octets[0] == 172 && (16...31).contains(octets[1]))
                && !(octets[0] == 192 && octets[1] == 168)
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
        guard APIResponseParser.boolean(info["isPreView"]) != true else {
            throw NativePlaybackError.previewOnly
        }
        let media = rawMedia.map(Media.init(raw:))
        guard let programIndex = media.firstIndex(where: {
            $0.isHLS && $0.bitrate > 0
        }), let programURL = media[programIndex].secureURL else {
            throw NativePlaybackError.unsupportedMedia
        }

        let advertisements = try media[..<programIndex].compactMap { media -> NativePlaybackEntry? in
            guard media.duration > 0 else {
                return nil
            }
            guard let url = media.secureURL else {
                throw NativePlaybackError.unsupportedMedia
            }
            return NativePlaybackEntry(url: url, isAdvertisement: true)
        }
        let program = NativePlaybackEntry(url: programURL, isAdvertisement: false)
        return NativePlayback(entries: advertisements + [program])
    }

}

protocol NativePlaybackResolving: Sendable {
    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback
}

extension NativePlaybackResolving {
    func resolve(item: AiyifanItem) async throws -> NativePlayback {
        try await resolve(item: item, preferredEpisodeKey: nil)
    }
}

struct NativePlaybackResolver: NativePlaybackResolving {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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

        var pageRequest = URLRequest(url: item.playURL)
        pageRequest.timeoutInterval = 15
        pageRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let (pageData, pageResponse) = try await session.data(for: pageRequest)
        try validate(pageResponse, maximumBytes: 1_000_000, actualBytes: pageData.count)

        let certificate = try PlaybackCertificateParser.parse(pageData)
        let detailURL = try NativePlaybackRequestBuilder.makeDetailURL(
            mediaKey: item.listPath,
            siteHost: pageHost,
            certificate: certificate
        )
        let detailData = try await fetch(detailURL, referer: item.playURL)
        let context = try VideoDetailResponseDecoder.decode(detailData)
        let mediaKey: String
        let episodes: [Episode]
        let selectedEpisode: Episode?
        if context.isSerial {
            let playlistURL = try NativePlaybackRequestBuilder.makePlaylistURL(
                seriesKey: item.listPath,
                categoryID: context.categoryID,
                siteHost: pageHost,
                certificate: certificate
            )
            let playlistData = try await fetch(playlistURL, referer: item.playURL)
            episodes = try EpisodePlaylistResponseDecoder.decodeEpisodes(playlistData)
            guard let episode = EpisodePlaylistResponseDecoder.selectEpisode(
                from: episodes,
                preferredKey: preferredEpisodeKey
            ) else {
                throw NativePlaybackError.unsupportedMedia
            }
            mediaKey = episode.mediaKey
            selectedEpisode = episode
        } else {
            mediaKey = item.listPath
            episodes = []
            selectedEpisode = nil
        }
        let playbackURL = try NativePlaybackRequestBuilder.makeURL(
            mediaKey: mediaKey,
            albumMode: !context.isSerial,
            siteHost: pageHost,
            certificate: certificate
        )
        let playbackData = try await fetch(playbackURL, referer: item.playURL)
        let playback = try NativePlaybackResponseDecoder.decode(playbackData)
        return NativePlayback(
            entries: playback.entries,
            episodes: episodes,
            selectedEpisode: selectedEpisode
        )
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
    }
}

struct FixtureNativePlaybackResolver: NativePlaybackResolving {
    func resolve(item: AiyifanItem, preferredEpisodeKey: String?) async throws -> NativePlayback {
        let episodes = [
            Episode(mediaKey: "episode-10", title: "10", updateDate: "2026-09-07T10:00:00Z"),
            Episode(mediaKey: "episode-4", title: "04", updateDate: "2026-09-06T15:00:00Z"),
            Episode(mediaKey: "episode-2", title: "02", updateDate: "2026-09-06T10:00:00Z")
        ]
        let selected = episodes.first { $0.mediaKey == preferredEpisodeKey } ?? episodes[0]
        return NativePlayback(
            entries: [
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/advertisement.mp4")!,
                    isAdvertisement: true
                ),
                NativePlaybackEntry(
                    url: URL(string: "https://media.example.com/\(selected.mediaKey).m3u8")!,
                    isAdvertisement: false
                )
            ],
            episodes: episodes,
            selectedEpisode: selected
        )
    }
}
