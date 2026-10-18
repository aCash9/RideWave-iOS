import Foundation

enum SpotifyConfiguration {
    static let redirectURL = URL(string: "ridewave://callback")!
    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var isConfigured: Bool {
        clientID.count == 32 && clientID.allSatisfy { $0.isHexDigit }
    }
    static func accepts(_ url: URL) -> Bool {
        // Spotify may return the authority-only redirect with an explicit root slash.
        // Treat only the empty/root path as equivalent; never accept arbitrary subpaths.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return url.scheme == redirectURL.scheme && url.host == redirectURL.host &&
        (components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/") &&
        url.port == nil && url.user == nil && url.password == nil
    }
}
