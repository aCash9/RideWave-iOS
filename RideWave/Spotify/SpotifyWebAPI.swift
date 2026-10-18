import Foundation

struct SpotifyPlaylist: Decodable, Identifiable, Equatable {
    struct Artwork: Decodable, Equatable { let url: String }
    let id: String
    let name: String
    let uri: String
    var images: [Artwork]? = nil

    var artworkURL: URL? {
        images?.compactMap { URL(string: $0.url) }.first {
            $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil
        }
    }
}

enum SpotifyError: LocalizedError {
    case authorization, forbidden, rateLimited(String?), invalidResponse, timeout, disconnected
    case httpStatus(Int), pagination
    var errorDescription: String? {
        switch self {
        case .authorization: return "Spotify authorization expired or was cancelled. Connect your account again."
        case .forbidden: return "Spotify denied access. Check the app’s allowed users and playlist permissions."
        case .rateLimited(let seconds): return "Spotify is busy. Try again \(seconds.map { "in \($0) seconds" } ?? "later")."
        case .httpStatus(let status): return "Spotify could not load playlists (HTTP \(status)). Please retry."
        case .pagination: return "Spotify returned an unsupported playlist page link. Please retry."
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
                #if DEBUG
                print("[RideWave Web API] Playlist HTTP status=\(http.statusCode), page=\(visited.count)")
                #endif
                if http.statusCode == 401 && attempt == 0 { continue }
                switch http.statusCode {
                case 200: responseData = data
                case 401: throw SpotifyError.authorization
                case 403: throw SpotifyError.forbidden
                case 429:
                    let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                    throw SpotifyError.rateLimited(seconds.map(String.init))
                default: throw SpotifyError.httpStatus(http.statusCode)
                }
                break
            }
            guard let data = responseData else { throw SpotifyError.authorization }
            let page = try JSONDecoder().decode(Page.self, from: data)
            for playlist in page.items.compactMap({ $0 }) where ids.insert(playlist.id).inserted {
                playlists.append(playlist)
            }
            if let value = page.next {
                guard let candidate = URL(string: value), let url = Self.normalizedPlaylistURL(candidate) else {
                    #if DEBUG
                    let candidate = URL(string: value)
                    let segments = candidate?.path.split(separator: "/") ?? []
                    print("[RideWave Web API] Rejected next page; spotifyHost=\(candidate?.host == "api.spotify.com"), userPlaylistPath=\(segments.count == 4 && segments.first == "v1" && segments[1] == "users" && segments.last == "playlists")")
                    #endif
                    throw SpotifyError.pagination
                }
                next = url
            } else { next = nil }
        }
        return playlists
    }

    static func isPlaylistURL(_ url: URL) -> Bool {
        normalizedPlaylistURL(url) != nil
    }

    static func normalizedPlaylistURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "api.spotify.com",
              components.user == nil, components.password == nil, components.fragment == nil,
              components.port == nil || components.port == 443 else { return nil }
        let path = components.percentEncodedPath
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        let userPlaylistPath = segments.count == 5 && segments[0].isEmpty &&
            segments[1] == "v1" && segments[2] == "users" &&
            !segments[3].isEmpty && segments[4] == "playlists"
        guard path == "/v1/me/playlists" || userPlaylistPath else { return nil }
        // Spotify's /me response can paginate via /users/{id}/playlists.
        // Keep current-user semantics and avoid depending on the legacy users endpoint.
        components.path = "/v1/me/playlists"
        return components.url
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
