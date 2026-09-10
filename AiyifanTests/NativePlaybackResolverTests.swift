import Foundation
import XCTest
@testable import Aiyifan

final class NativePlaybackResolverTests: XCTestCase {
    override func tearDown() {
        ResolverURLProtocol.reset()
        super.tearDown()
    }

    func testSerialIntentUsesProviderItemEpisodeAndCategorySignals() {
        XCTAssertTrue(SerialPlaybackIntent.infer(
            providerIsSerial: true,
            item: AiyifanItem(listPath: "movie", title: "Provider Serial")
        ))
        XCTAssertTrue(SerialPlaybackIntent.infer(
            providerIsSerial: false,
            item: AiyifanItem(listPath: "series", title: "Series", isSerial: true)
        ))
        XCTAssertTrue(SerialPlaybackIntent.infer(
            providerIsSerial: false,
            item: AiyifanItem(listPath: "anime", title: "Anime", categoryPath: "0,1,6,24")
        ))
        XCTAssertTrue(SerialPlaybackIntent.infer(
            providerIsSerial: false,
            item: AiyifanItem(
                listPath: "stale-provider-serial-flag",
                title: "Series With Stale Provider Flag",
                isSerial: false,
                categoryPath: "0,1,4,152"
            )
        ))
        XCTAssertFalse(SerialPlaybackIntent.infer(
            providerIsSerial: false,
            item: AiyifanItem(listPath: "movie", title: "Movie", categoryPath: "0,1,3,8")
        ))
        XCTAssertFalse(SerialPlaybackIntent.infer(
            providerIsSerial: false,
            item: AiyifanItem(
                listPath: "movie",
                title: "Movie With Quality Row",
                isSerial: false,
                latestEpisodeKey: "quality-row",
                latestEpisodeTitle: "576P"
            )
        ))
    }

    func testCertificateParserReadsCurrentPageConfiguration() throws {
        let html = """
        <script>
        var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};
        </script>
        """

        let certificate = try PlaybackCertificateParser.parse(Data(html.utf8))

        XCTAssertEqual(certificate.publicKey, "public-test")
        XCTAssertEqual(certificate.privateKey, "private-test")
    }

    func testCertificateParserReadsHomeConfigPageConfiguration() throws {
        let html = """
        <script>
        var injectJson = {"home-config":{"ret":200,"data":{"list":{"mustLogin":false,"pConfig":{"publicKey":"public-live","privateKey":["private-live"]}}}}};
        </script>
        """

        let certificate = try PlaybackCertificateParser.parse(Data(html.utf8))

        XCTAssertEqual(certificate.publicKey, "public-live")
        XCTAssertEqual(certificate.privateKey, "private-live")
    }

    func testRequestBuilderSignsGuestPlaybackRequestDeterministically() throws {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        let url = try NativePlaybackRequestBuilder.makeURL(
            mediaKey: "media-key",
            siteHost: "www.yfsp.tv",
            certificate: certificate
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "m10.yfsp.tv")
        XCTAssertEqual(components.path, "/v3/video/play")
        XCTAssertEqual(values["id"], "media-key")
        XCTAssertEqual(values["a"], "1")
        XCTAssertEqual(values["usersign"], "1")
        XCTAssertEqual(values["region"], "US")
        XCTAssertEqual(values["lang"], "none")
        XCTAssertEqual(values["vv"], "16630e264f49d5d36e59e8ae031f965e")
        XCTAssertEqual(values["pub"], "public-test")
    }

    func testProviderRegionAcceptsOnlyTwoASCIILettersAndFallsBackToUS() {
        XCTAssertEqual(ProviderRegion.normalized("ca"), "CA")
        XCTAssertEqual(ProviderRegion.normalized("GB"), "GB")
        XCTAssertEqual(ProviderRegion.normalized(nil), "US")
        XCTAssertEqual(ProviderRegion.normalized("GL."), "US")
        XCTAssertEqual(ProviderRegion.normalized("USA"), "US")
        XCTAssertEqual(ProviderRegion.normalized("中国"), "US")
    }

    func testDetailAndPlaybackRequestsUseSameValidatedRegionAndPlaybackLanguage() throws {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")
        let playbackURL = try NativePlaybackRequestBuilder.makeURL(
            mediaKey: "media-key",
            siteHost: "m.yfsp.tv",
            certificate: certificate,
            region: "ca"
        )
        let detailURL = try NativePlaybackRequestBuilder.makeDetailURL(
            mediaKey: "media-key",
            siteHost: "m.yfsp.tv",
            certificate: certificate,
            region: "ca"
        )
        let playbackItems = URLComponents(url: playbackURL, resolvingAgainstBaseURL: false)?.queryItems
        let detailItems = URLComponents(url: detailURL, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(playbackItems?.first { $0.name == "region" }?.value, "CA")
        XCTAssertEqual(detailItems?.first { $0.name == "region" }?.value, "CA")
        XCTAssertEqual(playbackItems?.first { $0.name == "lang" }?.value, "none")
    }

    func testCertificateCacheInvalidationForcesFreshLoad() async throws {
        let cache = ProviderCertificateCache()
        let loadCount = LockedCounter()
        let first = try await cache.certificate(for: "yfsp.tv") {
            let value = loadCount.increment()
            return PlaybackCertificate(publicKey: "public-\(value)", privateKey: "private-\(value)")
        }

        await cache.invalidate(for: "yfsp.tv")

        let second = try await cache.certificate(for: "yfsp.tv") {
            let value = loadCount.increment()
            return PlaybackCertificate(publicKey: "public-\(value)", privateKey: "private-\(value)")
        }

        XCTAssertEqual(first.publicKey, "public-1")
        XCTAssertEqual(second.publicKey, "public-2")
        XCTAssertEqual(loadCount.value, 2)
    }

    func testCertificateCacheInvalidationCannotBeUndoneByLateCancelledLoad() async throws {
        let cache = ProviderCertificateCache()
        let loadCount = LockedCounter()
        let staleTask = Task {
            try await cache.certificate(for: "yfsp.tv") {
                _ = loadCount.increment()
                try? await Task.sleep(for: .milliseconds(80))
                return PlaybackCertificate(publicKey: "stale", privateKey: "stale")
            }
        }
        for _ in 0..<50 where loadCount.value == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(loadCount.value, 1)

        await cache.invalidate(for: "yfsp.tv")
        let fresh = try await cache.certificate(for: "yfsp.tv") {
            PlaybackCertificate(publicKey: "fresh", privateKey: "fresh")
        }

        do {
            _ = try await staleTask.value
            XCTFail("Expected invalidated in-flight load to be rejected")
        } catch is CancellationError {
            // Expected: an invalidated load cannot become cache state again.
        }
        let cached = try await cache.certificate(for: "yfsp.tv") {
            XCTFail("Fresh certificate should remain cached")
            return PlaybackCertificate(publicKey: "unexpected", privateKey: "unexpected")
        }

        XCTAssertEqual(fresh.publicKey, "fresh")
        XCTAssertEqual(cached.publicKey, "fresh")
    }

    func testRequestBuilderCreatesSignedDetailAndPlaylistEndpoints() throws {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        let detailURL = try NativePlaybackRequestBuilder.makeDetailURL(
            mediaKey: "series-key",
            siteHost: "m.yfsp.tv",
            certificate: certificate
        )
        let playlistURL = try NativePlaybackRequestBuilder.makePlaylistURL(
            seriesKey: "series-key",
            categoryID: "0,1,4,137",
            siteHost: "m.yfsp.tv",
            certificate: certificate
        )

        XCTAssertEqual(detailURL.path, "/v3/video/detail")
        XCTAssertEqual(playlistURL.path, "/v3/video/languagesplaylist")
        XCTAssertNotNil(URLComponents(url: detailURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "vv" })
        XCTAssertNotNil(URLComponents(url: playlistURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "vv" })
    }

    func testEpisodePlaybackRequestUsesEpisodeMode() throws {
        let certificate = PlaybackCertificate(publicKey: "public-test", privateKey: "private-test")

        let url = try NativePlaybackRequestBuilder.makeURL(
            mediaKey: "episode-key",
            albumMode: false,
            siteHost: "m.yfsp.tv",
            certificate: certificate
        )
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(queryItems?.first { $0.name == "a" }?.value, "0")
    }

    func testResolverRejectsCleartextPlaybackPage() {
        let item = AiyifanItem(
            listPath: "media-key",
            title: "Cleartext",
            url: "http://m.yfsp.tv/play/media-key"
        )

        XCTAssertThrowsError(try NativePlaybackResolver.validatePage(item)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedSite)
        }
    }

    func testDetailAndPlaylistDecodersReturnNewestEpisodesFirst() throws {
        let detail = Data("""
        {"ret":200,"data":{"code":0,"info":[{"key":"series-key","cid":"0,1,4,137","isSerial":true,"good":76,"favoriteCount":221,"score":"9.6","view":170000}]}}
        """.utf8)
        let playlist = Data("""
        {"ret":200,"data":{"code":0,"info":[{"playList":[
          {"key":"episode-1","name":"01","updateDate":"2026-09-06T13:34:00"},
          {"key":"episode-4","name":"04","updateDate":"2026-09-06T15:46:00"},
          {"key":"episode-3","name":"03","updateDate":"2026-09-06T13:35:00"}
        ]}]}}
        """.utf8)

        let context = try VideoDetailResponseDecoder.decode(detail)
        let episodes = try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)

        XCTAssertTrue(context.isSerial)
        XCTAssertEqual(context.categoryID, "0,1,4,137")
        XCTAssertEqual(context.metrics, ViewerMetrics(likes: 76, favorites: 221, score: 9.6, views: 170000))
        XCTAssertNil(context.advertisedQuality)
        XCTAssertEqual(episodes.map(\.mediaKey), ["episode-4", "episode-3", "episode-1"])
        XCTAssertEqual(episodes.first?.title, "04")
    }

    func testDetailDecoderExtractsAdvertisedQualityFromProviderFields() throws {
        let vipResource = Data("""
        {"ret":200,"data":{"code":0,"info":[{
          "cid":"0,1,3,27",
          "isSerial":false,
          "vipResource":"1080P"
        }]}}
        """.utf8)
        let lastName = Data("""
        {"ret":200,"data":{"code":0,"info":[{
          "cid":"0,1,3,27",
          "isSerial":false,
          "lastName":"1080P集全"
        }]}}
        """.utf8)

        XCTAssertEqual(try VideoDetailResponseDecoder.decode(vipResource).advertisedQuality, "1080P")
        XCTAssertEqual(try VideoDetailResponseDecoder.decode(lastName).advertisedQuality, "1080P集全")
    }

    func testDetailDecoderOmitsMalformedOptionalMetricsIndependently() throws {
        let detail = Data("""
        {"ret":200,"data":{"code":0,"info":[{
          "cid":"0,1,3,27",
          "isSerial":false,
          "good":-1,
          "favoriteCount":29,
          "score":"10.1",
          "view":"9831"
        }]}}
        """.utf8)

        let context = try VideoDetailResponseDecoder.decode(detail)

        XCTAssertEqual(context.metrics.likes, nil)
        XCTAssertEqual(context.metrics.favorites, 29)
        XCTAssertEqual(context.metrics.score, nil)
        XCTAssertEqual(context.metrics.views, 9831)
    }

    func testEpisodeDecoderUsesNumericLabelsAndStableSourceOrderWhenDatesAreMissing() throws {
        let playlist = Data("""
        {"ret":200,"data":{"code":0,"info":[{"playList":[
          {"key":"special-a","name":"Special","updateDate":""},
          {"key":"episode-2","name":"Episode 2"},
          {"key":"episode-10","name":"Episode 10"},
          {"key":"special-b","name":"Special"}
        ]}]}}
        """.utf8)

        let episodes = try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)

        XCTAssertEqual(episodes.map(\.mediaKey), ["episode-10", "episode-2", "special-a", "special-b"])
    }

    func testEpisodeDecoderUnderstandsProviderTimestampWithoutTimezone() throws {
        let playlist = Data("""
        {"ret":200,"data":{"code":0,"info":[{"playList":[
          {"key":"episode-99","name":"99","updateDate":"2026-09-06T13:34:00"},
          {"key":"special-new","name":"Special","updateDate":"2026-09-07T13:34:00"}
        ]}]}}
        """.utf8)

        let episodes = try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)

        XCTAssertEqual(episodes.map(\.mediaKey), ["special-new", "episode-99"])
    }

    func testEpisodeDecoderDropsInvalidAndDuplicateEpisodeKeys() throws {
        let playlist = Data("""
        {"ret":200,"data":{"code":0,"info":[{"playList":[
          {"key":"episode-10","name":"10"},
          {"key":"episode-10","name":"Duplicate 10"},
          {"key":"bad/key","name":"Bad"},
          {"key":"episode-2","name":"02"}
        ]}]}}
        """.utf8)

        let episodes = try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)

        XCTAssertEqual(episodes.map(\.mediaKey), ["episode-10", "episode-2"])
    }

    func testEpisodeSelectionUsesPreferredEpisodeOrFallsBackToNewest() throws {
        let episodes = [
            Episode(mediaKey: "episode-4", title: "04", updateDate: nil),
            Episode(mediaKey: "episode-3", title: "03", updateDate: nil)
        ]

        XCTAssertEqual(EpisodePlaylistResponseDecoder.selectEpisode(from: episodes, preferredKey: "episode-3")?.mediaKey, "episode-3")
        XCTAssertEqual(EpisodePlaylistResponseDecoder.selectEpisode(from: episodes, preferredKey: "missing")?.mediaKey, "episode-4")
    }

    func testNativePlaybackCarriesOrderedEpisodesAndSelectedEpisode() {
        let newest = Episode(mediaKey: "episode-4", title: "04", updateDate: nil)
        let older = Episode(mediaKey: "episode-3", title: "03", updateDate: nil)

        let metrics = ViewerMetrics(likes: 7, favorites: 8, score: 9.2, views: 1200)
        let playback = NativePlayback(entries: [], episodes: [newest, older], selectedEpisode: older, metrics: metrics)

        XCTAssertEqual(playback.episodes, [newest, older])
        XCTAssertEqual(playback.selectedEpisode, older)
        XCTAssertEqual(playback.episodeTitle, "03")
        XCTAssertEqual(playback.metrics, metrics)
    }

    func testPlaylistDecoderRejectsEmptyEpisodeList() {
        let playlist = Data("""
        {"ret":200,"data":{"code":0,"info":[{"playList":[]}]}}
        """.utf8)

        XCTAssertThrowsError(try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testPlaylistDecoderRejectsUnboundedEpisodeList() throws {
        let rows = (1...2_001).map { episode in
            ["key": "episode-\(episode)", "name": String(episode)]
        }
        let playlist = try JSONSerialization.data(withJSONObject: [
            "ret": 200,
            "data": ["code": 0, "info": [["playList": rows]]]
        ])

        XCTAssertThrowsError(try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .invalidResponse)
        }
    }

    func testResolverTraversesFullSerialFlowAndRequestsSelectedEpisode() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let data: Data

            switch url.path {
            case "/play/series-key":
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,4,152","isSerial":true}]}}"#.utf8)
            case "/v3/video/languagesplaylist":
                let rows = (1...10).map { episode in
                    ["key": "episode-\(episode)", "name": String(episode)]
                }
                data = try JSONSerialization.data(withJSONObject: [
                    "ret": 200,
                    "data": ["code": 0, "info": [["playList": rows]]]
                ])
            case "/v3/video/play":
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first { $0.name == "id" }?.value, "episode-2")
                XCTAssertEqual(query.first { $0.name == "a" }?.value, "0")
                data = Self.responseData(info: """
                {"isPreView":false,"needLogin":0,"flvPathList":[
                  {"result":"https://media.example.com/episode-2.m3u8","isHls":true,"bitrate":576}
                ]}
                """)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }

            return (HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Ten Episode Series",
            url: "https://m.yfsp.tv/play/series-key",
            isSerial: true,
            latestEpisodeKey: "episode-10",
            latestEpisodeTitle: "10"
        )

        let playback = try await NativePlaybackResolver(session: session).resolve(
            item: item,
            preferredEpisodeKey: "episode-2"
        )

        XCTAssertEqual(playback.episodes.count, 10)
        XCTAssertEqual(playback.episodes.first?.mediaKey, "episode-10")
        XCTAssertEqual(playback.selectedEpisode?.mediaKey, "episode-2")
        XCTAssertEqual(playback.entries.map(\.url.absoluteString), ["https://media.example.com/episode-2.m3u8"])
        let captured = requests.values
        XCTAssertEqual(captured.map { $0.url?.path }, [
            "/play/series-key",
            "/v3/video/detail",
            "/v3/video/languagesplaylist",
            "/v3/video/play"
        ])
        for request in captured.dropFirst() {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), item.playURL.absoluteString)
        }
    }

    func testResolverTreatsExplicitMovieWithQualityPlaylistAsMoviePlayback() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/play/movie-key":
                data = Data("""
                <script>var injectJson = {"home-config":{"data":{"list":{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}}}};</script>
                """.utf8)
            case "/v3/video/detail":
                data = Data("""
                {"ret":200,"data":{"code":0,"info":[{
                  "cid":"0,1,3,19",
                  "isSerial":false,
                  "lastName":"1080P集全"
                }]}}
                """.utf8)
            case "/v3/video/play":
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first { $0.name == "id" }?.value, "movie-key")
                XCTAssertEqual(query.first { $0.name == "a" }?.value, "1")
                data = Self.responseData(info: """
                {"isPreView":false,"needLogin":0,"flvPathList":[
                  {"result":"https://media.example.com/movie-576.m3u8","isHls":true,"bitrate":576}
                ]}
                """)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "movie-key",
            title: "Movie",
            url: "https://m.yfsp.tv/play/movie-key",
            isSerial: false,
            latestEpisodeKey: "quality-row",
            latestEpisodeTitle: "576P"
        )

        let playback = try await NativePlaybackResolver(session: session).resolve(item: item)

        XCTAssertNil(playback.selectedEpisode)
        XCTAssertTrue(playback.episodes.isEmpty)
        XCTAssertEqual(playback.advertisedQuality, "1080P集全")
        XCTAssertEqual(playback.entries.map(\.url.absoluteString), ["https://media.example.com/movie-576.m3u8"])
        XCTAssertEqual(playback.qualitySources.map(\.tierHeight), [576])
        XCTAssertFalse(requests.values.contains { $0.url?.path == "/v3/video/languagesplaylist" })
    }

    func testResolverRetriesFullThirtyEpisodeResolutionOnceWithFreshCertificate() async throws {
        let requests = LockedRequests()
        let pageLoads = LockedCounter()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let publicKey = query.first { $0.name == "pub" }?.value
            let data: Data

            switch url.path {
            case "/play/NjvfTz4MVG6":
                let version = pageLoads.increment()
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-\(version)","privateKey":["private-\(version)"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                XCTAssertEqual(query.first { $0.name == "region" }?.value, "US")
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,5,39","isSerial":true,"score":"8.4"}]}}"#.utf8)
            case "/v3/video/languagesplaylist":
                let rows = (1...30).map { episode in
                    [
                        "key": "pijing-\(episode)",
                        "name": episode == 30 ? "20260906(加更版)" : "第\(episode)期",
                        "updateDate": String(format: "2026-08-%02d", min(episode, 31))
                    ]
                }
                data = try JSONSerialization.data(withJSONObject: [
                    "ret": 200,
                    "data": ["code": 0, "info": [["playList": rows]]]
                ])
            case "/v3/video/play":
                XCTAssertEqual(query.first { $0.name == "region" }?.value, "US")
                XCTAssertEqual(query.first { $0.name == "lang" }?.value, "none")
                if publicKey == "public-1" {
                    data = Data(#"{"ret":200,"data":{"code":1,"info":[]}}"#.utf8)
                } else {
                    data = Self.responseData(info: """
                    {"isPreView":false,"needLogin":0,"flvPathList":[
                      {"result":"https://media.example.com/pijing-30.m3u8","isHls":true,"bitrate":1080}
                    ]}
                    """)
                }
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "NjvfTz4MVG6",
            title: "披荆斩棘2026",
            url: "https://m.yfsp.tv/play/NjvfTz4MVG6",
            isSerial: true
        )

        let playback = try await NativePlaybackResolver(
            session: session,
            playlistRetryDelays: [.zero],
            region: "GL."
        ).resolve(item: item, preferredEpisodeKey: "pijing-30")

        XCTAssertEqual(playback.episodes.count, 30)
        XCTAssertEqual(playback.selectedEpisode?.mediaKey, "pijing-30")
        XCTAssertEqual(playback.entries.first?.url.absoluteString, "https://media.example.com/pijing-30.m3u8")
        XCTAssertEqual(pageLoads.value, 2)
        XCTAssertEqual(requests.values.filter { $0.url?.path == "/v3/video/detail" }.count, 2)
        XCTAssertEqual(requests.values.filter { $0.url?.path == "/v3/video/languagesplaylist" }.count, 2)
        XCTAssertEqual(requests.values.filter { $0.url?.path == "/v3/video/play" }.count, 2)
    }

    func testEpisodeLoadingRetriesInvalidDetailWithFreshCertificate() async throws {
        let pageLoads = LockedCounter()
        ResolverURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let publicKey = query.first { $0.name == "pub" }?.value
            let data: Data
            switch url.path {
            case "/play/series-key":
                let version = pageLoads.increment()
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-\(version)","privateKey":["private-\(version)"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = publicKey == "public-1"
                    ? Data(#"{"ret":200,"data":{"code":1,"info":[]}}"#.utf8)
                    : Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,4,152","isSerial":true}]}}"#.utf8)
            case "/v3/video/languagesplaylist":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"playList":[{"key":"episode-2","name":"2"},{"key":"episode-1","name":"1"}]}]}}"#.utf8)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Series",
            url: "https://m.yfsp.tv/play/series-key",
            isSerial: true
        )

        let episodes = try await NativePlaybackResolver(
            session: session,
            playlistRetryDelays: []
        ).loadEpisodes(for: item, expectedEpisodeKey: "episode-2")

        XCTAssertEqual(episodes.map(\.mediaKey), ["episode-2", "episode-1"])
        XCTAssertEqual(pageLoads.value, 2)
    }

    func testSavedUpdateCheckRetriesInvalidDetailWithFreshCertificate() async throws {
        let pageLoads = LockedCounter()
        ResolverURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let publicKey = query.first { $0.name == "pub" }?.value
            let data: Data
            switch url.path {
            case "/play/series-key":
                let version = pageLoads.increment()
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-\(version)","privateKey":["private-\(version)"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = publicKey == "public-1"
                    ? Data(#"{"ret":200,"data":{"code":1,"info":[]}}"#.utf8)
                    : Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,4,152","isSerial":true}]}}"#.utf8)
            case "/v3/video/languagesplaylist":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"playList":[{"key":"episode-2","name":"2"},{"key":"episode-1","name":"1"}]}]}}"#.utf8)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Series",
            url: "https://m.yfsp.tv/play/series-key",
            isSerial: true
        )

        let episodes = try await NativePlaybackResolver(
            session: session,
            playlistRetryDelays: []
        ).episodesForSavedUpdate(for: item, expectedEpisodeKey: "episode-2")

        XCTAssertEqual(episodes, [
            EpisodeSelection(mediaKey: "episode-2", title: "2"),
            EpisodeSelection(mediaKey: "episode-1", title: "1")
        ])
        XCTAssertEqual(pageLoads.value, 2)
    }

    func testSavedUpdateUsesOnePlaylistRequestForTheRetainedSnapshot() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/play/series-key":
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,4,152","isSerial":true}]}}"#.utf8)
            case "/v3/video/languagesplaylist":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"playList":[{"key":"episode-3","name":"3"},{"key":"episode-2","name":"2"},{"key":"episode-1","name":"1"}]}]}}"#.utf8)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Series",
            url: "https://m.yfsp.tv/play/series-key",
            isSerial: true
        )

        let episodes = try await NativePlaybackResolver(
            session: session,
            playlistRetryDelays: []
        ).episodesForSavedUpdate(for: item, expectedEpisodeKey: nil)

        XCTAssertEqual(episodes?.map(\.mediaKey), ["episode-3", "episode-2", "episode-1"])
        XCTAssertEqual(
            requests.values.filter { $0.url?.path == "/v3/video/languagesplaylist" }.count,
            1
        )
    }

    func testResolverDoesNotRetryTerminalPlaybackError() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/play/movie-key":
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,3,27","isSerial":false}]}}"#.utf8)
            case "/v3/video/play":
                data = Self.responseData(info: """
                {"isPreView":false,"needLogin":1,"flvPathList":[]}
                """)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "movie-key",
            title: "Login Required",
            url: "https://m.yfsp.tv/play/movie-key"
        )

        do {
            _ = try await NativePlaybackResolver(session: session).resolve(item: item)
            XCTFail("Expected loginRequired")
        } catch {
            XCTAssertEqual(error as? NativePlaybackError, .loginRequired)
        }
        XCTAssertEqual(requests.values.filter { $0.url?.path == "/play/movie-key" }.count, 1)
        XCTAssertEqual(requests.values.filter { $0.url?.path == "/v3/video/play" }.count, 1)
    }

    func testResolverDoesNotRetryCancellation() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            throw URLError(.cancelled)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "movie-key",
            title: "Cancelled",
            url: "https://m.yfsp.tv/play/movie-key"
        )

        do {
            _ = try await NativePlaybackResolver(session: session).resolve(item: item)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
        XCTAssertEqual(requests.values.count, 1)
    }

    func testResolverRetriesPartialPlaylistUntilKnownLatestEpisodeAppears() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/play/series-key":
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,4,152","isSerial":true}]}}"#.utf8)
            case "/v3/video/languagesplaylist":
                let attempt = requests.values.filter { $0.url?.path == "/v3/video/languagesplaylist" }.count
                let rows = attempt < 3
                    ? [["key": "episode-1", "name": "1"]]
                    : [["key": "episode-10", "name": "10"], ["key": "episode-1", "name": "1"]]
                data = try JSONSerialization.data(withJSONObject: [
                    "ret": 200,
                    "data": ["code": 0, "info": [["playList": rows]]]
                ])
            case "/v3/video/play":
                data = Self.responseData(info: """
                {"isPreView":false,"needLogin":0,"flvPathList":[
                  {"result":"https://media.example.com/episode-10.m3u8","isHls":true,"bitrate":576}
                ]}
                """)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Ten Episode Series",
            url: "https://m.yfsp.tv/play/series-key",
            isSerial: true,
            latestEpisodeKey: "episode-10",
            latestEpisodeTitle: "10"
        )

        let episodes = try await NativePlaybackResolver(
            session: session,
            playlistRetryDelays: [.zero, .zero, .zero]
        ).loadEpisodes(for: item, expectedEpisodeKey: "episode-10")

        XCTAssertEqual(episodes.map(\.mediaKey), ["episode-10", "episode-1"])
        XCTAssertEqual(
            requests.values.filter { $0.url?.path == "/v3/video/languagesplaylist" }.count,
            3
        )
    }

    func testResolverStartsKnownLatestEpisodeWithoutWaitingForPlaylist() async throws {
        let requests = LockedRequests()
        ResolverURLProtocol.setHandler { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case "/play/series-key":
                data = Data("""
                <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};</script>
                """.utf8)
            case "/v3/video/detail":
                data = Data(#"{"ret":200,"data":{"code":0,"info":[{"cid":"0,1,4,152","isSerial":true}]}}"#.utf8)
            case "/v3/video/play":
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first { $0.name == "id" }?.value, "episode-10")
                data = Self.responseData(info: """
                {"isPreView":false,"needLogin":0,"flvPathList":[
                  {"result":"https://media.example.com/episode-10.m3u8","isHls":true,"bitrate":576}
                ]}
                """)
            default:
                XCTFail("Unexpected resolver request path: \(url.path)")
                data = Data()
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Series",
            url: "https://m.yfsp.tv/play/series-key",
            isSerial: true,
            latestEpisodeKey: "episode-10",
            latestEpisodeTitle: "10"
        )

        let playback = try await NativePlaybackResolver(session: session).resolve(item: item)

        XCTAssertEqual(playback.selectedEpisode?.mediaKey, "episode-10")
        XCTAssertTrue(playback.episodes.isEmpty)
        XCTAssertFalse(requests.values.contains { $0.url?.path == "/v3/video/languagesplaylist" })
    }

    func testResolverRejectsProviderResponseFromUnsupportedFinalHost() async throws {
        ResolverURLProtocol.setHandler { request in
            let finalURL = URL(string: "https://attacker.invalid/redirected")!
            let response = HTTPURLResponse(
                url: finalURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )!
            let page = Data("""
            <script>var injectJson = {"config":[{"pConfig":{"publicKey":"public-test","privateKey":["private-test"]}}]};</script>
            """.utf8)
            return (response, page)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let item = AiyifanItem(
            listPath: "series-key",
            title: "Redirected",
            url: "https://m.yfsp.tv/play/series-key"
        )

        do {
            _ = try await NativePlaybackResolver(session: session).resolve(item: item)
            XCTFail("Expected an unsupported final response host")
        } catch {
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedSite)
        }
    }

    func testResponseDecoderDiscardsFrontAdAndReturnsOnlyFullProgram() throws {
        let data = Self.responseData(info: """
        {
          "isPreView": false,
          "needLogin": 0,
          "flvPathList": [
            {"result":"https://ads.example.com/front.mp4","duration":20,"isHls":false,"bitrate":0},
            {"result":"https://media.example.com/full.m3u8","duration":0,"isHls":true,"bitrate":576}
          ]
        }
        """)

        let playback = try NativePlaybackResponseDecoder.decode(data)

        XCTAssertEqual(playback.entries.count, 1)
        XCTAssertFalse(playback.entries[0].isAdvertisement)
        XCTAssertEqual(playback.entries[0].url.absoluteString, "https://media.example.com/full.m3u8")
    }

    func testResponseDecoderRetainsSecureProviderQualitySourcesInProviderOrder() throws {
        let data = Self.responseData(info: """
        {
          "isPreView": false,
          "needLogin": 0,
          "flvPathList": [
            {"result":"https://ads.example.com/front.mp4","duration":20,"isHls":false,"bitrate":0},
            {"result":"https://media.example.com/full-2160.m3u8","duration":0,"isHls":true,"bitrate":2160},
            {"result":"https://media.example.com/full-1080.m3u8","duration":0,"isHls":true,"bitrate":1080},
            {"result":"https://media.example.com/full-720.m3u8","duration":0,"isHls":true,"bitrate":720},
            {"result":"https://media.example.com/full-1080-duplicate.m3u8","duration":0,"isHls":true,"bitrate":1080}
          ]
        }
        """)

        let playback = try NativePlaybackResponseDecoder.decode(data)

        XCTAssertEqual(playback.entries.count, 1)
        XCTAssertEqual(playback.entries.first?.url.lastPathComponent, "full-2160.m3u8")
        XCTAssertEqual(playback.qualitySources.map(\.tierHeight), [2_160, 1_080, 720])
        XCTAssertTrue(playback.qualitySources.allSatisfy { $0.url.scheme == "https" })
        XCTAssertEqual(playback.qualitySources.map { $0.url.lastPathComponent }, [
            "full-2160.m3u8",
            "full-1080.m3u8",
            "full-720.m3u8"
        ])
    }

    func testResponseDecoderExcludesBitrateBearingHLSFrontAdFromProgramSources() throws {
        let data = Self.responseData(info: """
        {
          "isPreView": false,
          "needLogin": 0,
          "flvPathList": [
            {"result":"https://media.example.com/front-ad-2160.m3u8","duration":20,"isHls":true,"bitrate":2160},
            {"result":"https://media.example.com/full-1080.m3u8","duration":0,"isHls":true,"bitrate":1080},
            {"result":"https://media.example.com/full-720.m3u8","duration":0,"isHls":true,"bitrate":720},
            {"result":"https://media.example.com/full-1080-duplicate.m3u8","duration":0,"isHls":true,"bitrate":1080}
          ]
        }
        """)

        let playback = try NativePlaybackResponseDecoder.decode(data)

        XCTAssertEqual(playback.entries.map(\.url.lastPathComponent), ["full-1080.m3u8"])
        XCTAssertEqual(playback.qualitySources.map(\.tierHeight), [1_080, 720])
        XCTAssertEqual(
            playback.qualitySources.map(\.url.lastPathComponent),
            ["full-1080.m3u8", "full-720.m3u8"]
        )
    }

    func testResponseDecoderRejectsPlaybackContainingOnlyBitrateBearingHLSAds() {
        let data = Self.responseData(info: """
        {
          "isPreView": false,
          "needLogin": 0,
          "flvPathList": [
            {"result":"https://media.example.com/front-ad-1080.m3u8","duration":15,"isHls":true,"bitrate":1080},
            {"result":"https://media.example.com/front-ad-720.m3u8","duration":30,"isHls":true,"bitrate":720}
          ]
        }
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(data)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testResponseDecoderRejectsDirectMediaURLWithCustomPort() {
        let data = Self.responseData(info: """
        {
          "isPreView": false,
          "needLogin": 0,
          "flvPathList": [
            {"result":"https://media.example.com:8443/full-1080.m3u8","duration":0,"isHls":true,"bitrate":1080}
          ]
        }
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(data)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testResponseDecoderExcludesInvalidQualitySourcesButKeepsSecureRecognizedProgram() throws {
        let data = Self.responseData(info: """
        {
          "isPreView": false,
          "needLogin": 0,
          "flvPathList": [
            {"result":"https://attacker.invalid/full-2160.m3u8","duration":0,"isHls":true,"bitrate":2160},
            {"result":"https://media.example.com/full-2000.m3u8","duration":0,"isHls":true,"bitrate":2000},
            {"result":"https://media.example.com/full-2160-fractional.m3u8","duration":0,"isHls":true,"bitrate":2160.5},
            {"result":"https://media.example.com/full-1440.m3u8","duration":0,"isHls":true,"bitrate":1440}
          ]
        }
        """)

        let playback = try NativePlaybackResponseDecoder.decode(data)

        XCTAssertEqual(playback.entries.count, 1)
        XCTAssertEqual(playback.entries.first?.url.lastPathComponent, "full-1440.m3u8")
        XCTAssertEqual(playback.qualitySources.map(\.tierHeight), [1_440])
    }

    func testResponseDecoderRejectsPreviewAndLoginOnlyPlayback() {
        let preview = Self.responseData(info: """
        {"isPreView":true,"needLogin":0,"flvPathList":[{"result":"https://media.example.com/preview.m3u8","isHls":true,"bitrate":576}]}
        """)
        let loginOnly = Self.responseData(info: """
        {"isPreView":false,"needLogin":1,"flvPathList":[{"result":"https://media.example.com/full.m3u8","isHls":true,"bitrate":576}]}
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(preview)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .previewOnly)
        }
        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(loginOnly)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .loginRequired)
        }
    }

    func testResponseDecoderRejectsMalformedPreviewFlagAndUnsupportedMediaHost() {
        let malformedPreview = Self.responseData(info: """
        {"isPreView":"unexpected","needLogin":0,"flvPathList":[{"result":"https://hss100.pipecdn.vip/full.m3u8","isHls":true,"bitrate":576}]}
        """)
        let unsupportedHost = Self.responseData(info: """
        {"isPreView":false,"needLogin":0,"flvPathList":[{"result":"https://attacker.invalid/full.m3u8","isHls":true,"bitrate":576}]}
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(malformedPreview)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .invalidResponse)
        }
        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(unsupportedHost)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testResponseDecoderRejectsFractionalLoginAndEnvelopeFlags() {
        let fractionalLogin = Self.responseData(info: """
        {"isPreView":false,"needLogin":0.5,"flvPathList":[{"result":"https://hss100.pipecdn.vip/full.m3u8","isHls":true,"bitrate":576}]}
        """)
        let fractionalEnvelope = Data("""
        {"ret":200.5,"data":{"code":0,"info":[{"isSerial":true,"cid":"0,1,4,137"}]}}
        """.utf8)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(fractionalLogin)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .loginRequired)
        }
        XCTAssertThrowsError(try VideoDetailResponseDecoder.decode(fractionalEnvelope)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .invalidResponse)
        }
    }

    func testProviderSessionDelegateAllowsOnlyHTTPSProviderRedirects() throws {
        let delegate = ProviderSessionDelegate()
        let originalURL = try XCTUnwrap(URL(string: "https://m.yfsp.tv/v3/video/detail"))
        let allowedURL = try XCTUnwrap(URL(string: "https://www.yfsp.tv/v3/video/detail"))
        let blockedURL = try XCTUnwrap(URL(string: "https://attacker.invalid/redirected"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: originalURL,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": allowedURL.absoluteString]
        ))
        let task = URLSession.shared.dataTask(with: originalURL)
        var allowedRequest: URLRequest?
        var blockedRequest: URLRequest?

        delegate.urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: allowedURL)
        ) { allowedRequest = $0 }
        delegate.urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: blockedURL)
        ) { blockedRequest = $0 }

        XCTAssertEqual(allowedRequest?.url, allowedURL)
        XCTAssertNil(blockedRequest)
        task.cancel()
    }

    func testResponseDecoderRejectsInsecureOrMissingProgramURL() {
        let data = Self.responseData(info: """
        {
          "isPreView":false,
          "needLogin":0,
          "flvPathList":[
            {"result":"https://ads.example.com/front.mp4","duration":20,"isHls":false,"bitrate":0},
            {"result":"http://media.example.com/full.m3u8","isHls":true,"bitrate":576}
          ]
        }
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(data)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testResponseDecoderRejectsPrivateNetworkProgramURL() {
        let data = Self.responseData(info: """
        {
          "isPreView":false,
          "needLogin":0,
          "flvPathList":[
            {"result":"https://192.168.1.20/full.m3u8","isHls":true,"bitrate":576}
          ]
        }
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(data)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testResponseDecoderIgnoresInvalidFrontAdAndKeepsSecureProgram() throws {
        let data = Self.responseData(info: """
        {
          "isPreView":false,
          "needLogin":0,
          "flvPathList":[
            {"result":"http://ads.example.com/front.mp4","duration":20,"isHls":false,"bitrate":0},
            {"result":"https://media.example.com/full.m3u8","isHls":true,"bitrate":576}
          ]
        }
        """)

        let playback = try NativePlaybackResponseDecoder.decode(data)

        XCTAssertEqual(playback.entries.map(\.url.absoluteString), ["https://media.example.com/full.m3u8"])
    }

    func testCertificateParserRejectsMalformedPageData() {
        XCTAssertThrowsError(try PlaybackCertificateParser.parse(Data("<html></html>".utf8))) { error in
            XCTAssertEqual(error as? NativePlaybackError, .missingConfiguration)
        }
    }

    private static func responseData(info: String) -> Data {
        Data("""
        {"ret":200,"data":{"code":0,"msg":"","info":[\(info)]},"msg":""}
        """.utf8)
    }
}

private final class LockedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var values: [URLRequest] {
        lock.withLock { storage }
    }

    func append(_ request: URLRequest) {
        lock.withLock {
            storage = storage + [request]
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}

private final class ResolverURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func setHandler(_ newHandler: @escaping Handler) {
        lock.withLock {
            handler = newHandler
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let currentHandler = Self.lock.withLock { Self.handler }
            let handler = try XCTUnwrap(currentHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
