import SwiftUI
import UIKit

struct PosterImage: View {
    let item: MyVideoItem

    @StateObject private var loader = PosterImageLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: item.thumbnailURL) {
            await loader.load(from: item.thumbnailURL)
        }
        .onDisappear {
            loader.cancel()
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.06))
    }
}

final class PosterImageLoader: ObservableObject {
    @MainActor
    @Published private(set) var image: UIImage?

    nonisolated(unsafe) private static let imageCache = NSCache<NSURL, UIImage>()

    private let session: URLSession
    private var loadingTask: Task<Void, Never>?
    private var activeURL: URL?

    init(session: URLSession = PosterImageSession.shared) {
        self.session = session
    }

    @MainActor
    func load(from url: URL?) async {
        loadingTask?.cancel()
        activeURL = url
        image = nil

        guard let url, Self.isAllowedArtworkURL(url) else {
            return
        }

        if let cachedImage = Self.cachedImage(for: url) {
            image = cachedImage
            return
        }

        loadingTask = Task { [session, url] in
            do {
                let loadedImage = try await Self.fetchImage(from: url, session: session)
                guard !Task.isCancelled else {
                    return
                }
                Self.store(loadedImage, for: url)
                if activeURL == url {
                    image = loadedImage
                }
            } catch {
                if activeURL == url {
                    image = nil
                }
            }
        }

        await loadingTask?.value
    }

    @MainActor
    func cancel() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    static func resetCache() {
        imageCache.removeAllObjects()
    }

    static func cachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        imageCache.setObject(image, forKey: url as NSURL)
    }

    static func makeRequest(for url: URL) throws -> URLRequest {
        guard isAllowedArtworkURL(url) else {
            throw URLError(.unsupportedURL)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://m.yfsp.tv/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    static func fetchImage(from url: URL, session: URLSession, maxAttempts: Int = 2) async throws -> UIImage {
        let attempts = max(1, maxAttempts)
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                let request = try makeRequest(for: url)
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw PosterImageLoadingError.httpStatus(httpResponse.statusCode)
                }
                guard let image = UIImage(data: data) else {
                    throw PosterImageLoadingError.invalidImageData
                }
                return image
            } catch {
                lastError = error
                guard attempt + 1 < attempts, shouldRetry(error) else {
                    throw error
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func isAllowedArtworkURL(_ url: URL) -> Bool {
        guard
            url.scheme?.lowercased() == "https",
            url.user == nil,
            url.password == nil,
            let host = url.host
        else {
            return false
        }
        return RemoteResourceHostValidator.isAllowedArtworkHost(host)
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if case PosterImageLoadingError.httpStatus(let statusCode) = error {
            return statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
        }

        let urlError = error as? URLError
        return urlError.map {
            [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains($0.code)
        } ?? false
    }
}

enum PosterImageLoadingError: Error, Equatable {
    case httpStatus(Int)
    case invalidImageData
}

enum PosterImageSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 24 * 1_024 * 1_024,
            diskCapacity: 80 * 1_024 * 1_024,
            diskPath: "MyVideoPosterImages"
        )
        return URLSession(
            configuration: configuration,
            delegate: ProviderSessionDelegate(),
            delegateQueue: nil
        )
    }()
}
