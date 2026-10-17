import Foundation

final class MockSpotifyProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, headers, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct SpotifyWebAPIChecks {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockSpotifyProtocol.self]
        let api = SpotifyWebAPI(session: URLSession(configuration: configuration))
        var requests = 0
        MockSpotifyProtocol.handler = { request in
            requests += 1
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            if requests == 1 {
                return (200, [:], #"{"items":[{"id":"1","name":"One","uri":"spotify:playlist:1"},null],"next":"https://api.spotify.com/v1/me/playlists?offset=50"}"#)
            }
            return (200, [:], #"{"items":[{"id":"1","name":"One","uri":"spotify:playlist:1"},{"id":"2","name":"Two","uri":"spotify:playlist:2"}],"next":null}"#)
        }
        let playlists = try await api.playlists { _ in "test-token" }
        precondition(playlists.map(\.id) == ["1", "2"] && requests == 2)

        requests = 0
        var refreshed = false
        MockSpotifyProtocol.handler = { request in
            requests += 1
            if requests == 1 { return (401, [:], "{}") }
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")
            return (200, [:], #"{"items":[],"next":null}"#)
        }
        _ = try await api.playlists { force in
            refreshed = force
            return force ? "renewed" : "expired"
        }
        precondition(refreshed && requests == 2)

        for status in [401, 403, 429, 500] {
            requests = 0
            MockSpotifyProtocol.handler = { _ in requests += 1; return (status, ["Retry-After": "5"], "{}") }
            do { _ = try await api.playlists { _ in "test-token" }; fatalError("Expected HTTP failure") }
            catch let error as SpotifyError {
                switch (status, error) {
                case (401, .authorization), (403, .forbidden), (429, .rateLimited("5")), (500, .invalidResponse): break
                default: fatalError("Wrong error")
                }
            }
            precondition(requests == (status == 401 ? 2 : 1))
        }
        for next in ["https://attacker.example/playlists", "http://api.spotify.com/v1/me/playlists", "https://api.spotify.com/v1/me/playlists?limit=50"] {
            requests = 0
            MockSpotifyProtocol.handler = { _ in requests += 1; return (200, [:], "{\"items\":[],\"next\":\"\(next)\"}") }
            do { _ = try await api.playlists { _ in "test-token" }; fatalError("Expected pagination rejection") }
            catch SpotifyError.invalidResponse {}
            precondition(requests == 1)
        }
        MockSpotifyProtocol.handler = { _ in (200, [:], "invalid JSON") }
        do { _ = try await api.playlists { _ in "test-token" }; fatalError("Expected decode failure") }
        catch is DecodingError {}
        MockSpotifyProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await api.playlists { _ in "test-token" }; fatalError("Expected network failure") }
        catch let error as URLError { precondition(error.code == .timedOut) }

        precondition(SpotifyConfiguration.accepts(URL(string: "ridewave://callback?code=example")!))
        for url in ["other://callback", "ridewave://wrong", "ridewave://callback/extra", "ridewave://user@callback"] {
            precondition(!SpotifyConfiguration.accepts(URL(string: url)!))
        }
        print("Spotify checks passed: pagination, deduplication, 401 renewal/retry limit, HTTP errors, hostile/cyclic pagination, decoding, timeout, callback routing")
    }
}
