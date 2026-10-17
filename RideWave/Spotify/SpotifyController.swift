import Combine
import Foundation
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyController: NSObject, ObservableObject, SPTSessionManagerDelegate,
                               SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var authorized = false
    @Published private(set) var message: String?
    @Published private(set) var trackTitle = "Your next soundtrack"
    @Published private(set) var trackArtist = "Choose a song in Spotify"
    @Published private(set) var paused = true
    @Published private(set) var hasPlayerState = false
    @Published private(set) var playlistCount: Int?
    @Published private(set) var loadingPlaylists = false

    private var manager: SPTSessionManager?
    private var remote: SPTAppRemote?
    private var active = false
    private var wantsPlayback = false
    private var authorizing = false
    private var deadline: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var playlistTask: Task<Void, Never>?
    private var connectionID = UUID()
    private var playlistRequestID = UUID()
    private var refreshWaiters = [CheckedContinuation<String, Error>]()
    private let webAPI = SpotifyWebAPI()
    private let store = SpotifySessionStore(account: SpotifyConfiguration.clientID + "|" + SpotifyConfiguration.redirectURL.absoluteString)
    private let scopes: SPTScope = [.appRemoteControl, .playlistReadPrivate, .playlistReadCollaborative]

    override init() {
        super.init()
        // Remove the obsolete prototype's unencrypted token and simulated connection flag.
        UserDefaults.standard.removeObject(forKey: "spotify_access_token")
        UserDefaults.standard.removeObject(forKey: "spotify_authorized")
        guard SpotifyConfiguration.isConfigured else { return }
        manager = makeManager(playback: false)
        do {
            if let data = try store.read(),
               let session = try NSKeyedUnarchiver.unarchivedObject(ofClass: SPTSession.self, from: data),
               session.scope.contains(scopes) {
                manager?.session = session
                authorized = true
            }
        } catch { message = error.localizedDescription }
    }

    private func makeManager(playback: Bool) -> SPTSessionManager {
        let configuration = SPTConfiguration(clientID: SpotifyConfiguration.clientID,
                                             redirectURL: SpotifyConfiguration.redirectURL)
        if playback { configuration.playURI = "" }
        return SPTSessionManager(configuration: configuration, delegate: self)
    }

    func authorize(playback: Bool) {
        guard !busy && !loadingPlaylists else { return }
        guard SpotifyConfiguration.isConfigured else {
            message = "Spotify setup is missing. Add your client ID in Configuration/Spotify.local.xcconfig and rebuild."
            return
        }
        if playback && !(manager?.isSpotifyAppInstalled ?? false) {
            message = "Install and sign in to Spotify on your iPhone to connect playback. Web API access can be tested separately."
            return
        }
        stopPlayback()
        wantsPlayback = playback
        manager?.delegate = nil
        manager = makeManager(playback: playback)
        authorizing = true
        busy = true
        message = "Waiting for Spotify authorization…"
        startDeadline(seconds: 120)
        manager?.initiateSession(with: scopes, options: .default, campaign: nil)
    }

    func handleURL(_ url: URL) {
        guard authorizing, SpotifyConfiguration.accepts(url), let manager else { return }
        if !manager.application(UIApplication.shared, open: url, options: [:]) {
            fail(SpotifyError.authorization)
        }
    }

    func setActive(_ value: Bool) {
        active = value
        if !value {
            connectionID = UUID()
            connectionTask?.cancel()
            connectionTask = nil
            remote?.delegate = nil
            remote?.playerAPI?.delegate = nil
            remote?.disconnect()
            remote = nil
            connected = false
            hasPlayerState = false
            if !authorizing && refreshWaiters.isEmpty { busy = false; deadline?.cancel() }
        } else if wantsPlayback && !authorizing && !connected {
            reconnect()
        }
    }

    func reconnect() {
        guard active, wantsPlayback, !authorizing, connectionTask == nil, !connected else { return }
        let attemptID = UUID()
        connectionID = attemptID
        connectionTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.connectionID == attemptID { self.connectionTask = nil } }
            do {
                let token = try await self.accessToken()
                try Task.checkCancellation()
                guard self.active, self.wantsPlayback else { return }
                self.connectRemote(token: token)
            } catch is CancellationError {
            } catch {
                if self.connectionID == attemptID && !Task.isCancelled { self.fail(error) }
            }
        }
    }

    private func connectRemote(token: String) {
        remote?.delegate = nil
        remote?.playerAPI?.delegate = nil
        remote?.disconnect()
        let configuration = SPTConfiguration(clientID: SpotifyConfiguration.clientID,
                                             redirectURL: SpotifyConfiguration.redirectURL)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        self.remote = remote
        remote.delegate = self
        remote.connectionParameters.accessToken = token
        busy = true
        message = "Connecting to Spotify…"
        startDeadline(seconds: 20)
        remote.connect()
    }

    func stopPlayback() {
        wantsPlayback = false
        connectionID = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        remote?.delegate = nil
        remote?.playerAPI?.delegate = nil
        remote?.disconnect()
        remote = nil
        connected = false
        hasPlayerState = false
        if !authorizing && refreshWaiters.isEmpty { deadline?.cancel(); busy = false }
    }

    func cancel() {
        manager?.delegate = nil
        authorizing = false
        finishRefresh(.failure(CancellationError()))
        stopPlayback()
        busy = false
        deadline?.cancel()
        message = "Connection cancelled. You can try again."
        // Discard callbacks from the cancelled manager, while retaining any established session.
        let session = manager?.session
        manager = SpotifyConfiguration.isConfigured ? makeManager(playback: false) : nil
        manager?.session = session
    }

    func signOut() {
        cancel()
        playlistRequestID = UUID()
        playlistTask?.cancel()
        playlistTask = nil
        loadingPlaylists = false
        manager?.session = nil
        authorized = false
        playlistCount = nil
        trackTitle = "Your next soundtrack"
        trackArtist = "Choose a song in Spotify"
        paused = true
        do { try store.delete(); message = "Spotify disconnected and saved session removed." }
        catch { message = error.localizedDescription }
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let session = manager?.session else { throw SpotifyError.authorization }
        if !forceRefresh && session.expirationDate.timeIntervalSinceNow > 60 { return session.accessToken }
        return try await withCheckedThrowingContinuation { continuation in
            refreshWaiters.append(continuation)
            if refreshWaiters.count == 1 {
                busy = true
                startDeadline(seconds: 25)
                manager?.renewSession()
            }
        }
    }

    private func finishRefresh(_ result: Result<String, Error>) {
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters { waiter.resume(with: result) }
    }

    func checkWebAPI() {
        guard !loadingPlaylists, !busy else { return }
        loadingPlaylists = true
        playlistCount = nil
        message = "Checking playlist access…"
        let requestID = UUID()
        playlistRequestID = requestID
        playlistTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.playlistRequestID == requestID {
                    self.loadingPlaylists = false
                    self.playlistTask = nil
                }
            }
            do {
                let playlists = try await self.webAPI.playlists { force in
                    try await self.accessToken(forceRefresh: force)
                }
                try Task.checkCancellation()
                self.playlistCount = playlists.count
                self.message = "Web API connected. Found \(playlists.count) playlists."
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.message = error.localizedDescription }
            }
        }
    }

    enum PlaybackAction { case toggle, next, previous }
    func perform(_ action: PlaybackAction) {
        guard connected, let player = remote?.playerAPI else {
            message = SpotifyError.disconnected.localizedDescription
            return
        }
        let callback: SPTAppRemoteCallback = { [weak self] _, error in
            if error != nil { self?.message = "Spotify could not perform that playback action. Please retry." }
        }
        switch action {
        case .toggle:
            guard hasPlayerState else { message = "Waiting for Spotify playback state…"; return }
            if paused { player.resume(callback) } else { player.pause(callback) }
        case .next: player.skip(toNext: callback)
        case .previous: player.skip(toPrevious: callback)
        }
    }

    private func startDeadline(seconds: Double) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.fail(SpotifyError.timeout)
        }
    }

    private func fail(_ error: Error) {
        let wasAuthorizing = authorizing
        let savedSession = manager?.session
        manager?.delegate = nil
        manager = SpotifyConfiguration.isConfigured ? makeManager(playback: false) : nil
        manager?.session = wasAuthorizing ? nil : savedSession
        authorizing = false
        busy = false
        deadline?.cancel()
        finishRefresh(.failure(error))
        stopPlayback()
        if wasAuthorizing {
            authorized = false
        }
        message = error.localizedDescription
    }

    private func accept(_ session: SPTSession) {
        deadline?.cancel()
        authorizing = false
        busy = false
        authorized = true
        message = "Spotify account authorized."
        do {
            try store.save(NSKeyedArchiver.archivedData(withRootObject: session, requiringSecureCoding: true))
        } catch { message = "Authorized for this session, but secure storage failed. You may need to sign in again." }
        finishRefresh(.success(session.accessToken))
        if wantsPlayback && active { reconnect() }
    }

    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        guard manager === self.manager else { return }
        accept(session)
    }
    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        guard manager === self.manager else { return }
        accept(session)
    }
    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        guard manager === self.manager else { return }
        fail(SpotifyError.authorization)
    }
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        guard appRemote === remote, active, wantsPlayback else { appRemote.disconnect(); return }
        deadline?.cancel()
        connected = true
        busy = false
        message = nil
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if error != nil { self?.message = "Could not subscribe to playback updates. Reconnect Spotify." }
        })
        appRemote.playerAPI?.getPlayerState { [weak self] result, error in
            guard let self, self.remote === appRemote else { return }
            if let state = result as? SPTAppRemotePlayerState { self.playerStateDidChange(state) }
            else if error != nil { self.message = "Could not read Spotify playback state. Reconnect Spotify." }
        }
    }
    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        guard appRemote === remote else { return }
        fail(SpotifyError.disconnected)
    }
    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        guard appRemote === remote else { return }
        fail(SpotifyError.disconnected)
    }
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        guard connected else { return }
        trackTitle = playerState.track.name
        trackArtist = playerState.track.artist.name
        paused = playerState.isPaused
        hasPlayerState = true
    }
}
