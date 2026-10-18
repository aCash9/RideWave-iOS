# RideWave iOS

RideWave is a SwiftUI app for controlling Spotify with simple gestures, opening saved playlists, and calling selected contacts. It uses a black fullscreen interface with portrait and landscape layouts.

## Features

- One-time gesture tutorial followed by Spotify playback connection.
- Returning users open ride mode with their saved session while Spotify reconnects.
- Tap to play/pause, swipe left for the next track, and swipe right for the previous track.
- Large clock and live Spotify track, artist, and playback state; the display stays awake while ride mode is active.
- Up to four saved playlist bubbles, with cover artwork and shuffle playback.
- Up to four saved contact numbers, chosen through the native contact picker and called through iOS confirmation.
- Separate Spotify playback and playlist authorization, cancellation/timeouts, and reconnect feedback.

This is an evolving prototype. A successful build does not establish that every Spotify account/device combination works. iOS does not expose Android's general notification-listener feature or immediate direct calling. RideWave does not provide background App Remote control.

## Requirements

- macOS with full Xcode selected as the active developer tools. The current project was built with **Xcode 27.1** and targets **iOS/iPadOS 27.0 or later**. Lower OS versions have not been validated.
- Network access to resolve the pinned official **SpotifyiOS 5.0.1** Swift package and access Spotify.
- A Spotify developer application and an authorized test account for development-mode testing.
- A physical iPhone with Spotify installed and signed in for App Remote playback. Simulator builds can check UI and some Web API flows, but cannot verify SDK playback or cellular calling.

## Setup

1. Open `RideWave.xcodeproj` in Xcode and allow Swift Package Manager to resolve dependencies. Keep the checked-in `Package.resolved` file.
2. Create local Spotify configuration from the example:

   ```sh
   cp Configuration/Spotify.local.xcconfig.example Configuration/Spotify.local.xcconfig
   ```

   Set `SPOTIFY_CLIENT_ID` to your developer application's client ID. Use the raw value without quotes. This file is ignored by Git. The shared `Spotify.xcconfig` intentionally has a blank default. Never put a client secret in the app.
3. In the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard), configure the iOS SDK/Web API integration and register **`ridewave://callback`** as the redirect URI. Add test users as required by the app's development mode and current Spotify account requirements.
4. In Xcode's **Signing & Capabilities**, select your development team and a bundle identifier you can sign. Register that exact bundle identifier in Spotify's Dashboard. The checked-in signing team and bundle identifier reflect the development project; other contributors must select their own.
5. Select your iPhone, enable Developer Mode if required by Xcode, and build/run. Install and sign into Spotify first, then tap **Connect Spotify** in RideWave.

No Dashboard changes are needed solely to use playlist shortcuts or contacts. Changing the redirect URI requires coordinated changes to `SpotifyConfiguration.swift`, `Configuration/Info.plist`, and the Dashboard. Info.plist also registers the Spotify app-query scheme and receives the client ID from build settings. Xcode merges it with generated scene/launch metadata.

Without a local client ID, the app builds and displays setup feedback when connection is attempted.

## Spotify connections and ride mode

Onboarding offers only **Connect Spotify**, which uses `SPTSessionManager` PKCE authorization and App Remote playback access. Authorization opens Spotify and may resume music so Spotify is available for the remote connection. The first successful connection opens ride mode.

Playback sessions, including refresh tokens, are stored in device-only Keychain storage, scoped to the client ID and redirect URI. Relaunch restores the session and opens ride mode while reconnecting; expired tokens are renewed when possible. Invalid/revoked authorization requires reconnection. App Remote disconnects when the scene becomes inactive and reconnects on return while ride mode is wanted. Closing ride mode stops reconnection.

Authorization and connection attempts time out and can be cancelled. Callback validation accepts the configured URI with an optional root slash; other hosts, paths, ports, or credentials are rejected. Debug diagnostics omit tokens and complete callback URLs.

## Playlists

Open **Playlists** from the bottom-left button. **Connect Web API** authorizes playlist access separately from playback. Cancelling or disconnecting this connection does not clear the SDK playback session.

1. Select zero to four playlists and press **Done**.
2. Tap a saved artwork bubble to start that playlist, then enable shuffle.
3. Use **Edit** to replace selections or **Refresh** to reload the library. Close or inactivity dismissal discards unfinished edits.

Choices and setup completion persist between launches. Saving zero choices is valid. Portrait uses two columns; landscape uses a row, with scrolling where needed. Missing artwork falls back to the playlist name. Opening the overlay refreshes metadata and temporary artwork URLs. Unavailable playlists are omitted from the bubbles; failed requests do not erase saved choices. **Disconnect playlist access**, available while editing, clears the local playlist session and choices. Revoke the server-side grant in Spotify account settings if desired.

The library fetches every page, deduplicates IDs, and renews the token once on HTTP 401. Spotify's user-scoped playlist pagination links are normalized to the current-user endpoint. Other origins/paths and redirects are rejected to prevent bearer-token forwarding. Permission, rate-limit, network, and malformed-response errors show retry feedback.

Playback starts before shuffle is requested. If shuffle fails, music continues with a warning. Disconnected playback offers reconnection, and commands time out rather than leaving the overlay busy indefinitely. Artwork uses HTTPS, ephemeral downloads limited to 2 MiB, network timeouts, and off-main-thread downsampling to 512 pixels. Only playlist IDs and setup completion persist in preferences.

The overlay dismisses after five seconds without interaction. Touches, scrolling, and controls reset the timer; authorization, loading, playback commands, errors, held touches, and backgrounding pause it. VoiceOver and Switch Control disable automatic dismissal.

## Contacts and calling

Open **Contacts** from the bottom-right button and tap **Add contact**. Choose a phone number using the native iOS picker; contacts with multiple numbers allow selection of the exact number. RideWave does not request full address-book permission or enumerate contacts.

Save up to four numbers as photo/name bubbles. Portrait uses two columns and landscape a row. **Edit** changes taps into removal; **Done** returns to calling. Tap a contact to open the native iOS call confirmation. iOS controls confirmation and call completion; RideWave cannot reliably determine whether a call was completed. No automatic retries occur. Returning from Phone uses the normal Spotify reconnect lifecycle.

Only the selected name, normalized number, and resized photo are stored in Application Support, with complete file protection and excluded from backup. Remove and re-add a contact to refresh details. Formatting-only number duplicates are rejected; local and international forms are not inferred to be equivalent. Extensions, star/hash codes, and unsupported characters are rejected rather than silently changing the dialed number. Save failures preserve the previous selection, and unreadable storage is not overwritten.

Close or the outside background dismisses the overlay. Its five-second inactivity timer resets on touch/scroll and pauses during editing, the picker, errors, calling, held touches, and backgrounding. VoiceOver and Switch Control disable automatic dismissal; animations respect Reduce Motion. Overlay controls do not trigger ride playback gestures.

## Project structure

| Path | Purpose |
| --- | --- |
| `RideWave/MyApp.swift` | App entry point |
| `RideWave/ContentView.swift` | Tutorial, connection, ride screen, gestures, overlays |
| `RideWave/RideWaveModel.swift` | Onboarding persistence and initial navigation |
| `RideWave/Spotify/` | SDK lifecycle, Keychain sessions, configuration, Web API |
| `RideWave/Playlists/` | Playlist selection, bubbles, artwork |
| `RideWave/Contacts/` | Native picker, saved contacts, calling |
| `Configuration/` | Info.plist and Spotify build configuration |
| `Tests/` | Standalone Swift checks with mock data |
| `docs/` | HTML explainer and code walkthrough |
| `AGENTS.md` | Contributor and automated-agent guidelines |

## Build and automated checks

Run from the repository root. These checks use the selected Xcode toolchain. The project currently uses standalone Swift checks rather than an XCTest/UI-test target.

```sh
xcodebuild -project RideWave.xcodeproj -scheme RideWave \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/RideWaveDerivedData \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

swiftc -parse-as-library RideWave/RideWaveModel.swift \
  Tests/ScreenFlowChecks.swift -o /tmp/ridewave-screen-checks
/tmp/ridewave-screen-checks

swiftc -parse-as-library RideWave/Spotify/SpotifyWebAPI.swift \
  RideWave/Spotify/SpotifyConfiguration.swift Tests/SpotifyWebAPIChecks.swift \
  -o /tmp/ridewave-spotify-checks
/tmp/ridewave-spotify-checks

swiftc -parse-as-library RideWave/Contacts/RideContacts.swift \
  Tests/RideContactsChecks.swift -o /tmp/ridewave-contacts-checks
/tmp/ridewave-contacts-checks

swiftc -parse-as-library RideWave/Playlists/PlaylistSelection.swift \
  RideWave/Spotify/SpotifyWebAPI.swift Tests/PlaylistSelectionChecks.swift \
  -o /tmp/ridewave-playlist-checks
/tmp/ridewave-playlist-checks
```

Checks cover onboarding/session routing, mocked playlist pagination/deduplication, token retry limits, HTTP/network errors, callback validation, contact persistence/validation, and playlist selection/persistence/artwork URLs. They never dial or start music and do not validate the Spotify binary SDK, real Keychain entitlements, or UI layout. Debug launches also accept `-preview-page tutorial`, `-preview-page connect`, or `-preview-page ride` for UI inspection.

## Device verification

Before a release, record the device/account used and which cases passed. A signed build and the host checks have passed during development; the latest playlist playback/shuffle flow still requires end-to-end account verification.

- Complete, cancel, deny, and retry each Spotify authorization flow. Confirm callback return preserves the playlist overlay and the two sessions remain independent.
- Relaunch with a saved playback session; test expiry/renewal, revoked access, missing Spotify, disconnected playback, and background/foreground reconnect.
- Verify live track state and tap/swipe actions. Confirm corner/overlay controls never trigger those gestures.
- Load a library larger than 50 playlists. Save zero, two, and four choices; reopen/relaunch; replace choices; close without Done. Tap each bubble and confirm the intended playlist and shuffle in Spotify.
- Add contacts with/without photos and multiple numbers; cancel the picker, try duplicates, remove choices, and relaunch. Use an agreed test contact to verify call confirmation/cancellation and return from Phone.
- Check portrait/landscape, large text, VoiceOver, Switch Control, Reduce Motion, inactivity dismissal, and timer pause/reset behavior.

## Preparing a GitHub push

Keep `Spotify.local.xcconfig`, Xcode user state, build output, signing material, tokens, and personal contact data out of Git. The example configuration and dependency lockfile should be tracked. `.gitignore` does not remove files already tracked, so review both staged and unstaged changes:

```sh
git status --short
git diff --check
git diff --cached --check
git diff --stat
git diff --cached --stat
git check-ignore Configuration/Spotify.local.xcconfig
```

Ensure new source folders, tests, app icon assets, and intended documentation are included in your commit. Review file contents before publishing. Removing a value from the current tree does not remove it from existing Git history. Spotify client IDs are public OAuth identifiers, not client secrets; actual secrets must never be included.

## References

- [Official Spotify iOS SDK, pinned version](https://github.com/spotify/ios-sdk/tree/v5.0.1)
- [SDK PKCE and session authorization](https://github.com/spotify/ios-sdk/blob/v5.0.1/docs/auth.md)
- [Spotify iOS lifecycle guidance](https://developer.spotify.com/documentation/ios/concepts/application-lifecycle)
