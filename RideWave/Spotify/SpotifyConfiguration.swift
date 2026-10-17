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
        url.scheme == redirectURL.scheme && url.host == redirectURL.host &&
        url.path == redirectURL.path && url.port == nil && url.user == nil && url.password == nil
    }
}
