import Foundation

struct SpotifyPlaylist: Decodable, Identifiable {
    let id: String
    let name: String
    let uri: String
}

enum SpotifyError: LocalizedError {
    case authorization, forbidden, rateLimited(String?), invalidResponse, timeout, disconnected
    var errorDescription: String? {
        switch self {
        case .authorization: return "Spotify authorization expired or was cancelled. Connect your account again."
        case .forbidden: return "Spotify denied access. Check the app’s allowed users and playlist permissions."
        case .rateLimited(let seconds): return "Spotify is busy. Try again \(seconds.map { "in \($0) seconds" } ?? "later")."
        case .invalidResponse: return "Spotify returned an unexpected response. Please retry."
        case .timeout: return "Spotify did not respond in time. Open Spotify and try connecting again."
        case .disconnected: return "Spotify is disconnected. Reconnect before controlling playback."
        }
    }
}

@MainActor
final class SpotifyWebAPI {
    private let session: URLSession
    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral,
                                             delegate: SpotifyRedirectPolicy(), delegateQueue: nil)
    }

    // Token provider refreshes once on a 401; never forward a bearer token to a pagination host we don't trust.
    func playlists(token: (Bool) async throws -> String) async throws -> [SpotifyPlaylist] {
        struct Page: Decodable { let items: [SpotifyPlaylist?]; let next: String? }
        var next: URL? = URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")
        var visited = Set<URL>()
        var playlists = [SpotifyPlaylist]()
        var ids = Set<String>()
        while let url = next {
            try Task.checkCancellation()
            guard Self.isPlaylistURL(url), visited.insert(url).inserted, visited.count <= 1000 else {
                throw SpotifyError.invalidResponse
            }
            var responseData: Data?
            for attempt in 0...1 {
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.setValue("Bearer \(try await token(attempt == 1))", forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
                if http.statusCode == 401 && attempt == 0 { continue }
                switch http.statusCode {
                case 200: responseData = data
                case 401: throw SpotifyError.authorization
                case 403: throw SpotifyError.forbidden
                case 429:
                    let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                    throw SpotifyError.rateLimited(seconds.map(String.init))
                default: throw SpotifyError.invalidResponse
                }
                break
            }
            guard let data = responseData else { throw SpotifyError.authorization }
            let page = try JSONDecoder().decode(Page.self, from: data)
            for playlist in page.items.compactMap({ $0 }) where ids.insert(playlist.id).inserted {
                playlists.append(playlist)
            }
            if let value = page.next {
                guard let url = URL(string: value), Self.isPlaylistURL(url) else { throw SpotifyError.invalidResponse }
                next = url
            } else { next = nil }
        }
        return playlists
    }

    static func isPlaylistURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "api.spotify.com" &&
        url.path == "/v1/me/playlists" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443)
    }
}

// Pagination is validated before every request; redirects must not leak its Authorization header.
private final class SpotifyRedirectPolicy: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest,
                               completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
