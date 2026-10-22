import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model: RideWaveModel
    @StateObject private var spotify: SpotifyController
    @StateObject private var playlistSpotify = SpotifyController(forPlaylists: true)
    @State private var orientationMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let playback = SpotifyController()
        _spotify = StateObject(wrappedValue: playback)
        _model = StateObject(wrappedValue: RideWaveModel())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.page {
            case .setup:
                SetupPage {
                    Text("Ready for your ride?").font(.largeTitle.weight(.medium))
                    Text("Set up your screen before heading out. Your preferences are saved for next time.")
                        .foregroundStyle(.secondary)
                    Button("Start ride") {
                        model.startRide(connected: spotify.connected)
                        spotify.startRide()
                    }
                    .buttonStyle(RideButtonStyle())
                    .accessibilityIdentifier("setup.startRide")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ride orientation").font(.headline)
                        Picker("Ride orientation", selection: $model.orientation) {
                            ForEach(RideOrientation.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Text("Applies when you start a ride. Auto follows device rotation settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle(isOn: $model.keepScreenAwake) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keep screen awake").font(.headline)
                            Text("Prevent the screen from sleeping during a ride.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    GestureRow(title: "Tap to play or pause", detail: "Double-tap to add to Liked Songs.")
                    GestureRow(title: "Swipe left / right", detail: "Next / previous track")
                    if let orientationMessage { Text(orientationMessage).font(.footnote) }
                }
            case .connect:
                SetupPage {
                    Button("Back to setup") { spotify.cancel(); model.closeRide() }
                        .frame(minHeight: 44)
                    Text("Connect your soundtrack.")
                        .font(.largeTitle.weight(.medium))
                    Text("Open Spotify and sign in on this device, then connect your account.")
                        .foregroundStyle(.secondary)
                    if let message = spotify.message {
                        Text(message).font(.callout)
                            .accessibilityIdentifier("connection.message")
                    }
                    Button(spotify.busy ? spotify.progressTitle : "Connect Spotify") { spotify.authorize(playback: true) }
                        .buttonStyle(RideButtonStyle())
                        .disabled(spotify.busy || spotify.loadingPlaylists)
                    Text("Connecting playback opens Spotify and may resume your music.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if spotify.busy {
                        ProgressView().tint(.white)
                        Button("Cancel connection", action: spotify.cancel)
                            .frame(minHeight: 44)
                    }

                }
            case .ride:
                RideView(spotify: spotify, playlistSpotify: playlistSpotify, orientationMessage: orientationMessage) { spotify.stopPlayback(); model.closeRide() }
            }
        }
        .background {
            RideOrientationController(orientation: model.page == .ride ? model.orientation : .auto) {
                orientationMessage = $0
            }.frame(width: 0, height: 0)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onChange(of: model.page, initial: true) { updateIdleTimer(); orientationMessage = nil }
        .onChange(of: model.keepScreenAwake) { updateIdleTimer() }
        .onChange(of: scenePhase, initial: true) {
            updateIdleTimer()
            spotify.setActive(scenePhase == .active)
            playlistSpotify.setActive(scenePhase == .active)
        }
        .onChange(of: spotify.connected) {
            if spotify.connected { model.connectionEstablished() }
        }
        .onChange(of: spotify.authorized) {
            if !spotify.authorized && model.page == .ride { model.page = .connect }
        }
        .onOpenURL {
            spotify.handleURL($0)
            playlistSpotify.handleURL($0)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            spotify.setActive(false)
            playlistSpotify.setActive(false)
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = model.page == .ride && model.keepScreenAwake && scenePhase == .active
    }
}

private struct SetupPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("RIDEWAVE")
                        .font(.caption).tracking(3).foregroundStyle(.secondary)
                    content
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, geometry.size.width > geometry.size.height ? 24 : 88)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct RideView: View {
    @ObservedObject var spotify: SpotifyController
    @ObservedObject var playlistSpotify: SpotifyController
    let orientationMessage: String?
    @State private var playlistsOpen = false
    let close: () -> Void
    @State private var contactsOpen = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 60).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        spotify.perform(value.translation.width < 0 ? .next : .previous)
                    }.exclusively(before:
                        TapGesture(count: 2).onEnded { spotify.likeCurrentTrack() }
                            .exclusively(before: TapGesture().onEnded { spotify.perform(.toggle) })))
                    .accessibilityLabel("Ride playback controls")
                    .accessibilityAction(named: "Add to Liked Songs") { spotify.likeCurrentTrack() }
                    .accessibilityAction(named: "Play or pause") { spotify.perform(.toggle) }
                    .accessibilityAction(named: "Next track") { spotify.perform(.next) }
                    .accessibilityAction(named: "Previous track") { spotify.perform(.previous) }
                VStack(spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: landscape ? 80 : 64, weight: .bold, design: .monospaced))
                            .tracking(5)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .padding(.horizontal, landscape ? 88 : 28)
                    }
                    .padding(.top, landscape ? 0 : 56)
                    Spacer(minLength: 16)
                    VStack(spacing: 6) {
                        Text(spotify.connected ? (spotify.paused ? "PAUSED" : "NOW PLAYING") : "SPOTIFY NOT CONNECTED")
                            .font(.system(size: 11, weight: .bold)).tracking(2)
                            .foregroundStyle(.secondary)
                        Text(spotify.connected ? spotify.trackTitle : "Your next soundtrack")
                            .font(landscape ? .title2.bold() : .title.bold())
                        Text(spotify.connected ? spotify.trackArtist : "Connect Spotify to see your music")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Rectangle().fill(.white).frame(width: 32, height: 2).padding(.top, 4)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, landscape ? 88 : 28)
                    .padding(.bottom, landscape ? 56 : 88)
                }.allowsHitTesting(false)
                if let orientationMessage {
                    VStack {
                        Text(orientationMessage).font(.footnote).multilineTextAlignment(.center)
                            .padding(.horizontal, 72).padding(.top, 8)
                        Spacer()
                    }.allowsHitTesting(false)
                }
                if let feedback = spotify.likeFeedback, spotify.message == nil {
                    Text(feedback).font(.title3).multilineTextAlignment(.center)
                        .padding(32).allowsHitTesting(false)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let message = spotify.message {
                    VStack(spacing: 16) {
                        Text(spotify.likeFeedback ?? message).font(.callout).multilineTextAlignment(.center)
                        if !spotify.connected && !spotify.busy {
                            Button("Reconnect Spotify") { spotify.authorize(playback: true) }
                                .buttonStyle(RideButtonStyle())
                        }
                    }.frame(maxWidth: 360).padding(32)
                }
                VStack {
                    HStack {
                        iconButton("xmark", label: "Close ride mode", action: close)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        iconButton("music.note.list", label: "Playlists") {
                            playlistsOpen = true
                        }
                        Spacer()
                        iconButton("person.2", label: "Ride contacts") {
                            contactsOpen = true
                        }
                    }
                }.padding(8)
            }
        }
        .accessibilityHidden(playlistsOpen || contactsOpen)
        .overlay {
            if playlistsOpen {
                RidePlaylistsView(library: playlistSpotify, playback: spotify) { playlistsOpen = false }
            }
            if contactsOpen {
                RideContactsView { contactsOpen = false }
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 25))
                .frame(width: 56, height: 56).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

private struct GestureRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct RideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? Color.white.opacity(0.12) : .clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.gray.opacity(0.65), lineWidth: 1))
            .contentShape(Capsule())
    }
}

#Preview("Three-screen flow") {
    ContentView()
}
