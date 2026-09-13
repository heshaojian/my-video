import CryptoKit
import Foundation

final class ProviderSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard
            request.url?.scheme?.lowercased() == "https",
            let host = request.url?.host,
            request.url?.user == nil,
            request.url?.password == nil,
            RemoteResourceHostValidator.matchingProviderDomain(for: host) != nil
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum ProviderSessionFactory {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(
            configuration: configuration,
            delegate: ProviderSessionDelegate(),
            delegateQueue: nil
        )
    }
}

actor ProviderCertificateCache {
    static let shared = ProviderCertificateCache()

    private struct Entry {
        let certificate: PlaybackCertificate
        let expiresAt: Date
    }

    private struct Load {
        let id: UUID
        let task: Task<PlaybackCertificate, Error>
    }

    private let lifetime: TimeInterval
    private var entries: [String: Entry] = [:]
    private var loads: [String: Load] = [:]

    init(lifetime: TimeInterval = 300) {
        self.lifetime = lifetime
    }

    func certificate(
        for domain: String,
        load: @escaping @Sendable () async throws -> PlaybackCertificate
    ) async throws -> PlaybackCertificate {
        let now = Date()
        if let entry = entries[domain], entry.expiresAt > now {
            return entry.certificate
        }
        if let existing = loads[domain] {
            let certificate = try await existing.task.value
            if loads[domain]?.id == existing.id || entries[domain]?.certificate == certificate {
                return certificate
            }
            throw CancellationError()
        }

        let loadID = UUID()
        let task = Task { try await load() }
        loads = loads.merging(
            [domain: Load(id: loadID, task: task)],
            uniquingKeysWith: { _, new in new }
        )
        do {
            let certificate = try await task.value
            guard loads[domain]?.id == loadID else {
                throw CancellationError()
            }
            entries = entries.merging(
                [domain: Entry(certificate: certificate, expiresAt: now.addingTimeInterval(lifetime))],
                uniquingKeysWith: { _, new in new }
            )
            loads.removeValue(forKey: domain)
            return certificate
        } catch {
            if loads[domain]?.id == loadID {
                loads.removeValue(forKey: domain)
            }
            throw error
        }
    }

    func invalidate(for domain: String) {
        loads[domain]?.task.cancel()
        loads.removeValue(forKey: domain)
        entries.removeValue(forKey: domain)
    }
}

enum RemoteResourceHostValidator {
    static let providerDomains = [
        "yfsp.tv", "yifan.tv", "yfsp.me", "ayf.tv", "aiyifan.tv",
        "wyav.tv", "flyv.tv", "jssp.tv", "iyf.tv", "lgsp.tv",
        "tripdata.app", "kubb.tv"
    ]

    static func matchingProviderDomain(for host: String) -> String? {
        matchingDomain(for: host, allowedDomains: providerDomains)
    }

    static func isAllowedArtworkHost(_ host: String) -> Bool {
        matchingProviderDomain(for: host) != nil || isDebugFixtureHost(host, expected: "images.example.com")
    }

    static func isAllowedMediaHost(_ host: String) -> Bool {
        matchingDomain(for: host, allowedDomains: providerDomains + ["pipecdn.vip"]) != nil
            || isDebugFixtureHost(host, expected: "media.example.com")
    }

    private static func matchingDomain(for host: String, allowedDomains: [String]) -> String? {
        let normalized = host.lowercased()
        return allowedDomains.first { domain in
            normalized == domain || normalized.hasSuffix(".\(domain)")
        }
    }

    private static func isDebugFixtureHost(_ host: String, expected: String) -> Bool {
#if DEBUG
        host.caseInsensitiveCompare(expected) == .orderedSame
#else
        false
#endif
    }
}

enum ProviderRequestSigner {
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
        guard let domain = RemoteResourceHostValidator.matchingProviderDomain(for: normalizedHost) else {
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
