# RideWave iOS

SwiftUI tutorial → Spotify setup → fullscreen ride mode. The UI preserves the black background, outlined buttons, large clock, and portrait/landscape layouts. Ride mode keeps the display awake only while active.

## Spotify integration

The project pins Spotify’s official `SpotifyiOS` Swift package at **5.0.1** (including `Package.resolved`). Xcode downloads it automatically. The app target supports iPhone/iPad; the starter target’s macOS and visionOS destinations were removed because this integration uses UIKit and Spotify’s iOS binary.

- **Connect Spotify** uses `SPTSessionManager` authorization with PKCE and then App Remote. Authorization can open Spotify and resume music to keep Spotify available for the remote connection. The ride page opens only after the remote connection succeeds.
- **Connect Web API only** authorizes the same scopes without requesting playback. With Spotify absent, the SDK falls back to browser authentication. This path can be tested in the simulator.
- **Check Web API playlist access** loads all pages of the account’s playlist library and reports the count. It deduplicates entries, refreshes the token once on HTTP 401, and reports permission, rate-limit, timeout, and malformed-response failures. Playlist selection/playback UI remains a later milestone.
- Ride gestures issue real pause/resume, next, and previous commands. Track title, artist, and paused state come from Spotify. Controls remain safe when disconnected; visible corner controls do not share the gesture surface. VoiceOver exposes named playback actions.
- App Remote disconnects when the scene is inactive and reconnects on return during the same ride. Closing ride mode stops reconnection. Relaunch returns to setup with the saved account available for Web API access; playback connection is explicit.
- Authorization and connection attempts time out and can be cancelled. Only the expected callback URI is forwarded during an active authorization attempt.
- Sessions (including refresh tokens) use device-only Keychain storage, scoped to client ID and redirect URI. No client secret is required. **Forget Spotify account** removes the local session; remove RideWave in Spotify account settings to revoke the server-side grant. Old prototype tokens in UserDefaults are removed.

## Local configuration and Developer Dashboard

1. Copy `Configuration/Spotify.local.xcconfig.example` to `Configuration/Spotify.local.xcconfig` and replace the placeholder with your Spotify developer app’s **client ID**. This file is ignored by Git. Never put a client secret in the app.
2. In the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard), enable the iOS SDK/Web API as appropriate and register **`ridewave://callback`** exactly.
3. Add the bundle identifier from Xcode’s RideWave target. The current default is **`devplaceholder.Z7028OKY.RideWave`**; this change does not modify the bundle ID. If you change it for signing, update the Dashboard too.
4. For Development Mode, ensure the test Spotify account is an allowed user and meets Spotify’s current developer-account requirements.
5. For device testing, select your development team in Xcode, install Spotify on the iPhone, and sign in. Signing credentials remain local.

`Configuration/Info.plist` registers the `ridewave` callback scheme and `spotify` query scheme. The build merges it with Xcode’s generated scene/launch metadata and injects the local client ID. `SpotifyConfiguration.swift` owns the exact callback URL. If changing the redirect, update this file, Info.plist, and the Dashboard together. Android configuration is unchanged.

The app builds with no local client ID and displays a configuration message when connecting. Simulator UI and Web API authorization do not prove App Remote connectivity: playback requires a physical iPhone with Spotify installed. Spotify account/product restrictions can limit playback actions.

Official references: [SDK setup](https://github.com/spotify/ios-sdk/tree/v5.0.1), [SDK PKCE/session authorization](https://github.com/spotify/ios-sdk/blob/v5.0.1/docs/auth.md), [iOS lifecycle](https://developer.spotify.com/documentation/ios/concepts/application-lifecycle).

## Build and checks

```sh
xcodebuild -project RideWave.xcodeproj -scheme RideWave \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

swiftc -parse-as-library RideWave/RideWaveModel.swift Tests/ScreenFlowChecks.swift -o /tmp/ridewave-screen-checks
/tmp/ridewave-screen-checks

swiftc -parse-as-library RideWave/Spotify/SpotifyWebAPI.swift \
  RideWave/Spotify/SpotifyConfiguration.swift Tests/SpotifyWebAPIChecks.swift \
  -o /tmp/ridewave-spotify-checks
/tmp/ridewave-spotify-checks
```

The host-side checks use isolated preferences and mocked HTTP responses: navigation persistence, pagination/deduplication, token refresh/retry limits, HTTP errors, hostile/cyclic pagination, malformed JSON, network timeouts, and callback routing. They do not exercise Spotify’s binary authorization implementation or real Keychain entitlements.

Manual verification before calling the integration complete:

1. Missing client ID: verify useful setup feedback. On simulator, verify missing Spotify feedback with a configured client ID.
2. Authorize Web API, cancel authorization, deny permission, and retry. Confirm playlist count for an allowed test account and a library larger than 50 playlists.
3. On iPhone, connect playback, verify current song/state and tap/swipe commands. Test paused music, unsupported actions, and a disconnected Spotify app.
4. Background/foreground the app, rotate in ride mode, and leave/return from Spotify. Check timeout/retry and larger text/VoiceOver. Corner buttons must not trigger playback.
5. Relaunch with a saved session, exercise expired-token renewal, forget the account, and relaunch again. No saved account should remain after successful removal.

Tutorial completion persists. View tutorial and Preview ride screen remain available. Debug launches accept `-preview-page tutorial`, `-preview-page connect`, or `-preview-page ride`. Contacts and playlist selection are deferred; iOS does not provide Android’s notification-listener feature.
