import Foundation
import XCTest
@testable import Aiyifan

final class NativePlaybackResolverTests: XCTestCase {
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
        XCTAssertEqual(values["vv"], "150c013e5d6c7191d6bdcc688b546df1")
        XCTAssertEqual(values["pub"], "public-test")
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
        {"ret":200,"data":{"code":0,"info":[{"key":"series-key","cid":"0,1,4,137","isSerial":true}]}}
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
        XCTAssertEqual(episodes.map(\.mediaKey), ["episode-4", "episode-3", "episode-1"])
        XCTAssertEqual(episodes.first?.title, "04")
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

        let playback = NativePlayback(entries: [], episodes: [newest, older], selectedEpisode: older)

        XCTAssertEqual(playback.episodes, [newest, older])
        XCTAssertEqual(playback.selectedEpisode, older)
        XCTAssertEqual(playback.episodeTitle, "03")
    }

    func testPlaylistDecoderRejectsEmptyEpisodeList() {
        let playlist = Data("""
        {"ret":200,"data":{"code":0,"info":[{"playList":[]}]}}
        """.utf8)

        XCTAssertThrowsError(try EpisodePlaylistResponseDecoder.decodeEpisodes(playlist)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testResponseDecoderQueuesFrontAdBeforeFullProgram() throws {
        let data = responseData(info: """
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

        XCTAssertEqual(playback.entries.count, 2)
        XCTAssertTrue(playback.entries[0].isAdvertisement)
        XCTAssertEqual(playback.entries[0].url.absoluteString, "https://ads.example.com/front.mp4")
        XCTAssertFalse(playback.entries[1].isAdvertisement)
        XCTAssertEqual(playback.entries[1].url.absoluteString, "https://media.example.com/full.m3u8")
    }

    func testResponseDecoderRejectsPreviewAndLoginOnlyPlayback() {
        let preview = responseData(info: """
        {"isPreView":true,"needLogin":0,"flvPathList":[{"result":"https://media.example.com/preview.m3u8","isHls":true,"bitrate":576}]}
        """)
        let loginOnly = responseData(info: """
        {"isPreView":false,"needLogin":1,"flvPathList":[{"result":"https://media.example.com/full.m3u8","isHls":true,"bitrate":576}]}
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(preview)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .previewOnly)
        }
        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(loginOnly)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .loginRequired)
        }
    }

    func testResponseDecoderRejectsInsecureOrMissingProgramURL() {
        let data = responseData(info: """
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
        let data = responseData(info: """
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

    func testResponseDecoderDoesNotSilentlySkipInvalidFrontAd() {
        let data = responseData(info: """
        {
          "isPreView":false,
          "needLogin":0,
          "flvPathList":[
            {"result":"http://ads.example.com/front.mp4","duration":20,"isHls":false,"bitrate":0},
            {"result":"https://media.example.com/full.m3u8","isHls":true,"bitrate":576}
          ]
        }
        """)

        XCTAssertThrowsError(try NativePlaybackResponseDecoder.decode(data)) { error in
            XCTAssertEqual(error as? NativePlaybackError, .unsupportedMedia)
        }
    }

    func testCertificateParserRejectsMalformedPageData() {
        XCTAssertThrowsError(try PlaybackCertificateParser.parse(Data("<html></html>".utf8))) { error in
            XCTAssertEqual(error as? NativePlaybackError, .missingConfiguration)
        }
    }

    private func responseData(info: String) -> Data {
        Data("""
        {"ret":200,"data":{"code":0,"msg":"","info":[\(info)]},"msg":""}
        """.utf8)
    }
}
