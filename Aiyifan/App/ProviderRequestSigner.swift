import CryptoKit
import Foundation

enum ProviderRequestSigner {
    private static let supportedDomains = [
        "yfsp.tv", "yifan.tv", "yfsp.me", "ayf.tv", "aiyifan.tv",
        "wyav.tv", "flyv.tv", "jssp.tv", "iyf.tv", "lgsp.tv",
        "tripdata.app", "kubb.tv"
    ]

    static func makeSignedURL(
        path: String,
        parameters: [URLQueryItem],
        siteHost: String,
        certificate: PlaybackCertificate
    ) throws -> URL {
        guard
            path.hasPrefix("/"),
            !path.contains(".."),
            !certificate.publicKey.isEmpty,
            certificate.publicKey.count <= 1_024,
            !certificate.privateKey.isEmpty,
            certificate.privateKey.count <= 1_024
        else {
            throw NativePlaybackError.invalidResponse
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
