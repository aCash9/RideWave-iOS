# Repository guidelines

These guidelines apply to the RideWave iOS repository and all of its subdirectories.

## Project scope

RideWave is a small SwiftUI iPhone/iPad application with Spotify playback, up to four saved playlist shortcuts, and up to four ride contacts. Match the Android interaction where iOS supports it, while keeping iOS-specific behavior explicit. Avoid new architecture or dependencies without a concrete need.

## Before making changes

- Read the root `README.md`, relevant source files, and existing checks in `Tests/`.
- Inspect `git status` and relevant diffs; preserve existing user changes.
- Determine whether the change affects Spotify authorization, redirect handling, signing, lifecycle, storage, or device-only behavior.
- The Android repository is a reference, not an implicit edit target. Keep changes scoped to the requested platform.
- Do not commit or push unless requested.

## Code organization

- `RideWave/ContentView.swift`: tutorial, connection, ride screen, gestures, and overlay composition.
- `RideWave/RideWaveModel.swift`: onboarding and initial navigation state.
- `RideWave/Spotify/`: SDK/session lifecycle, Keychain persistence, callback configuration, and Web API requests.
- `RideWave/Playlists/`: selection persistence, picker/bubbles, and bounded artwork loading.
- `RideWave/Contacts/`: native contact picker, selected-contact storage, bubbles, and call handoff.
- `Configuration/`: Info.plist and shared/example/local Spotify build configuration.
- `Tests/`: standalone host-side Swift checks; there is currently no XCTest/UI-test target.

Prefer SwiftUI, Foundation, UIKit, ContactsUI, and ImageIO over additional packages. Keep observable UI state and SDK calls on the main actor. Move image decoding off the main actor explicitly; the project enables default MainActor isolation and approachable concurrency. Match existing formatting and naming. New files in the synchronized `RideWave` group are included automatically.

## Spotify and lifecycle

- Keep playback and playlist authorization separate. Onboarding requests App Remote access; Web API playlist access belongs inside Playlists. Cancelling/disconnecting playlist access must not clear playback authorization.
- Restore sessions from Keychain and open ride mode for a saved playback session; reconnect/renew without forcing login on every launch.
- Disconnect App Remote when the scene becomes inactive, reconnect on return when playback is wanted, and stop reconnection when leaving ride mode.
- Keep timeout/cancellation cleanup explicit. Ignore callbacks from replaced SDK instances and stale requests. Do not log tokens or complete callback URLs.
- Validate callback scheme, host, path, credentials, and port. Accept only the configured callback, with the existing optional root slash behavior.
- Web API pagination must retain current-user semantics, validate every destination, prevent bearer-token forwarding through redirects, deduplicate IDs, and retry HTTP 401 with token renewal only once.
- Start playlist playback before enabling shuffle. Report shuffle failure without claiming playback failed or stopping music. Never assume App Remote is connected.

## Configuration and security

- Treat `SpotifyConfiguration.swift`, `Configuration/Info.plist`, xcconfig values, and the Spotify Developer Dashboard as one configuration surface.
- Shared `Spotify.xcconfig` keeps a blank client ID and optionally includes ignored `Spotify.local.xcconfig`. Keep the example generic. A client ID is public OAuth metadata, but environment-specific values belong in local configuration.
- Never commit client secrets, access/refresh tokens, signing keys, certificates, provisioning profiles, contact data, generated builds, local configuration, or Xcode user state. Keep `Package.resolved` tracked.
- Preserve the user's signing settings during unrelated work. Document dashboard/setup changes if bundle identifiers, redirect URIs, or entitlements change.
- Keep sessions in device-only Keychain storage. Contact snapshots must remain protected and excluded from backup. Do not expand address-book access beyond the selected contact without an explicit feature requirement.

## UI and interaction

- Preserve black fullscreen presentation, portrait/landscape layouts, and screen-awake behavior only while ride mode is active.
- Overlay controls and scrolling must not trigger background playback gestures.
- Playlists support zero to four saved choices; Done commits, while closing discards the draft. Refresh failures must not destroy saved choices.
- Contacts support four selected phone numbers. Preserve validation and duplicate detection. Use the native iOS call confirmation; never simulate successful dialing or place a real test call automatically.
- Keep inactivity timers responsive to touch, backgrounding, busy states, and errors. Respect VoiceOver, Switch Control, and Reduce Motion. Contact editing pauses its timer; playlist editing resets its timer through interaction.
- Provide useful permission, connection, timeout, missing-app, storage, and empty-state feedback. Bound artwork downloads, timeouts, and image dimensions; retain a name fallback.

## Validation

Run the smallest meaningful checks for the change using the commands in README.md. Swift source/UI/project changes should build for the iOS Simulator; changes involving SDK integration/signing should also build for a physical device when available. Run the relevant host checks and expand to the other checks when shared logic changes.

Device-only verification includes Spotify authorization/renewal, callback return, playlist playback and shuffle, app background/foreground transitions, contact picking, and call confirmation. A build or mocked HTTP check does not prove these behaviors. Do not initiate calls or music playback solely to test without appropriate user authorization. Report checks performed, failures, and unverified cases accurately. Do not change unrelated settings to hide failures.

For documentation-only edits, verify paths, commands, feature descriptions, and `git diff --check`; do not add tests that mirror prose.

## Documentation and change quality

Update README.md when setup, supported behavior, structure, validation commands, or known limitations change. Use portable commands and generic examples, not local absolute paths, device IDs, or credentials. Keep Android/iOS differences and manual verification requirements explicit. Keep patches focused, preserve user assets/docs, and never present pending device checks as completed verification.
