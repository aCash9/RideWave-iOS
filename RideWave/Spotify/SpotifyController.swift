import Combine
import Foundation
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyController: NSObject, ObservableObject, SPTSessionManagerDelegate,
                               SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var progressTitle = "Authorizing…"
    @Published private(set) var authorized = false
    @Published private(set) var message: String?
    @Published private(set) var trackTitle = "Your next soundtrack"
    @Published private(set) var trackArtist = "Choose a song in Spotify"
    @Published private(set) var paused = true
    @Published private(set) var hasPlayerState = false
    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published private(set) var playlistCount: Int?
    @Published private(set) var loadingPlaylists = false

    @Published private(set) var startingPlaylist = false
    @Published private(set) var playlistPlaybackMessage: String?
    private var playbackRequestID = UUID()
    private var playbackDeadline: Task<Void, Never>?

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
    private let store: SpotifySessionStore
    private let scopes: SPTScope
    private let forPlaylists: Bool

    init(forPlaylists: Bool = false) {
        self.forPlaylists = forPlaylists
        scopes = forPlaylists ? [.playlistReadPrivate, .playlistReadCollaborative] : [.appRemoteControl]
        let account = SpotifyConfiguration.clientID + "|" + SpotifyConfiguration.redirectURL.absoluteString
        store = SpotifySessionStore(account: account + (forPlaylists ? "|playlists" : ""))
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
                // Restore authorization, but wait for Start ride before reconnecting.
                trace("Saved session restored; playlists=\(forPlaylists)")
            }
        } catch { message = error.localizedDescription }
    }

    private func trace(_ event: String, error: Error? = nil) {
        #if DEBUG
        var detail = ""
        var current = error as NSError?
        for _ in 0..<4 {
            guard let value = current else { break }
            detail += " [\(value.domain):\(value.code)]"
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        print("[RideWave Spotify] \(event)\(detail)")
        #endif
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
        trace("Authorization started; playback=\(playback)")
        stopPlayback()
        wantsPlayback = playback
        manager?.delegate = nil
        manager = makeManager(playback: playback)
        authorizing = true
        busy = true
        progressTitle = "Authorizing…"
        message = "Waiting for Spotify authorization…"
        startDeadline(seconds: 120)
        manager?.initiateSession(with: scopes, options: .default, campaign: nil)
    }

    func handleURL(_ url: URL) {
        trace("URL received; pending=\(authorizing), schemeMatch=\(url.scheme == SpotifyConfiguration.redirectURL.scheme), hostMatch=\(url.host == SpotifyConfiguration.redirectURL.host), rootSlash=\(url.path == "/"), accepted=\(SpotifyConfiguration.accepts(url))")
        guard authorizing, SpotifyConfiguration.accepts(url), let manager else { return }
        trace("Authorization callback received")
        progressTitle = "Authorizing…"
        message = "Completing Spotify authorization…"
        if !manager.application(UIApplication.shared, open: url, options: [:]) {
            fail(SpotifyError.authorization)
        }
    }

    func setActive(_ value: Bool) {
        trace("Scene active=\(value)")
        active = value
        if !value {
            cancelLike()
            finishPlaylistPlayback(message: startingPlaylist ? "Playback interrupted. Tap the playlist again after reconnecting." : nil)
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

    func startRide() {
        wantsPlayback = true
        if authorized { reconnect() }
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
        progressTitle = "Connecting…"
        message = "Connecting to Spotify…"
        startDeadline(seconds: 20)
        trace("App Remote connection started")
        remote.connect()
    }

    func stopPlayback() {
        cancelLike()
        finishPlaylistPlayback(message: startingPlaylist ? SpotifyError.disconnected.localizedDescription : nil)
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
        playlists = []
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
                progressTitle = "Renewing session…"
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
                self.playlists = playlists
                self.playlistCount = playlists.count
                self.message = "Web API connected. Found \(playlists.count) playlists."
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.message = error.localizedDescription }
            }
        }
    }

    func clearPlaylistFeedback() { playlistPlaybackMessage = nil }

    private func finishPlaylistPlayback(message: String?) {
        playbackRequestID = UUID()
        playbackDeadline?.cancel()
        playbackDeadline = nil
        startingPlaylist = false
        if let message { playlistPlaybackMessage = message }
    }

    func playPlaylist(_ playlist: SpotifyPlaylist) {
        guard !startingPlaylist else { return }
        guard connected, let remote, let player = remote.playerAPI else {
            playlistPlaybackMessage = SpotifyError.disconnected.localizedDescription
            return
        }
        guard playlist.uri == "spotify:playlist:" + playlist.id else {
            playlistPlaybackMessage = "This playlist cannot be played. Refresh your library and try again."
            return
        }
        let requestID = UUID()
        playbackRequestID = requestID
        startingPlaylist = true
        playlistPlaybackMessage = nil
        playbackDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.playbackRequestID == requestID else { return }
            self.finishPlaylistPlayback(message: "Spotify did not confirm playback. Check Spotify before trying again.")
        }
        player.play(playlist.uri) { [weak self, weak remote] _, error in
            guard let self, let remote, self.remote === remote,
                  self.playbackRequestID == requestID else { return }
            guard error == nil else {
                self.finishPlaylistPlayback(message: "Spotify could not play this playlist. Check Spotify and try again.")
                return
            }
            player.setShuffle(true) { [weak self, weak remote] _, error in
                guard let self, let remote, self.remote === remote,
                      self.playbackRequestID == requestID else { return }
                self.finishPlaylistPlayback(message: error == nil ? nil :
                    "Playback started, but Spotify could not enable shuffle.")
            }
        }
    }

    @Published private(set) var likeFeedback: String?
    private var likeRequestID: UUID?
    private var likeDeadline: Task<Void, Never>?
    private var likeFeedbackTask: Task<Void, Never>?

    private func cancelLike() {
        likeRequestID = nil
        likeDeadline?.cancel()
        likeDeadline = nil
        likeFeedbackTask?.cancel()
        likeFeedback = nil
    }

    private func finishLike(_ text: String) {
        likeRequestID = nil
        likeDeadline?.cancel()
        likeDeadline = nil
        likeFeedbackTask?.cancel()
        likeFeedback = text
        UIAccessibility.post(notification: .announcement, argument: text)
        likeFeedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.likeFeedback = nil
        }
    }

    func likeCurrentTrack() {
        guard likeRequestID == nil else { return }
        guard connected, let remote, let player = remote.playerAPI, let user = remote.userAPI else {
            finishLike("Spotify is disconnected. Reconnect and try again.")
            return
        }
        let request = UUID()
        likeRequestID = request
        likeFeedbackTask?.cancel()
        likeFeedback = "Adding to Liked Songs…"
        likeDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.likeRequestID == request else { return }
            self.finishLike("Could not confirm the like. Check Spotify and try again.")
        }
        player.getPlayerState { [weak self, weak remote] result, error in
            guard let self, let remote, self.remote === remote, self.likeRequestID == request else { return }
            guard error == nil, let state = result as? SPTAppRemotePlayerState else {
                self.finishLike("Could not read the current song. Try again.")
                return
            }
            let uri = state.track.uri
            guard uri.hasPrefix("spotify:track:") else {
                self.finishLike("Play a Spotify song first. This item cannot be liked.")
                return
            }
            user.fetchLibraryState(forURI: uri) { [weak self, weak remote] result, error in
                guard let self, let remote, self.remote === remote, self.likeRequestID == request else { return }
                guard error == nil, let library = result as? SPTAppRemoteLibraryState else {
                    self.finishLike("Could not check Liked Songs. Try again.")
                    return
                }
                if library.isAdded { self.finishLike("Already in Liked Songs"); return }
                guard library.canAdd else { self.finishLike("This song cannot be added to Liked Songs."); return }
                user.addItemToLibrary(withURI: uri) { [weak self, weak remote] _, error in
                    guard let self, let remote, self.remote === remote, self.likeRequestID == request else { return }
                    guard error == nil else {
                        self.finishLike("Could not like this song. Check Spotify and try again.")
                        return
                    }
                    // SpotifyiOS 5.0.1 can return an acknowledgement wrapped as a library
                    // state whose isAdded getter throws an Objective-C exception. Do not
                    // inspect the mutation payload; fetch the actual library state instead.
                    user.fetchLibraryState(forURI: uri) { [weak self, weak remote] result, error in
                        guard let self, let remote, self.remote === remote,
                              self.likeRequestID == request else { return }
                        let saved = (result as? SPTAppRemoteLibraryState)?.isAdded == true
                        self.finishLike(error == nil && saved ? "Added to Liked Songs" :
                            "Could not confirm the like. Check Spotify and try again.")
                    }
                }
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
            self?.trace("Connection deadline expired")
            self?.fail(SpotifyError.timeout)
        }
    }

    private func fail(_ error: Error) {
        trace("Connection failed", error: error)
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
        if let spotifyError = error as? SpotifyError, case .authorization = spotifyError {
            manager?.session = nil
            authorized = false
            try? store.delete()
        }
        message = error.localizedDescription
    }

    private func accept(_ session: SPTSession) {
        trace("Session accepted; expired=\(session.isExpired)")
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
        if forPlaylists && !loadingPlaylists { checkWebAPI() }
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
        trace("Session authorization failed", error: error)
        fail(SpotifyError.authorization)
    }
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        guard appRemote === remote, active, wantsPlayback else { appRemote.disconnect(); return }
        trace("App Remote connected")
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
        trace("App Remote disconnected or failed", error: error)
        fail(SpotifyError.disconnected)
    }
    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        guard appRemote === remote else { return }
        trace("App Remote disconnected or failed", error: error)
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
