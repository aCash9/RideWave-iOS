import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = RideWaveModel()
    @StateObject private var spotify = SpotifyController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.page {
            case .tutorial:
                SetupPage {
                    Text("Your music.\nA simple gesture.")
                        .font(.largeTitle.weight(.medium))
                    Text("Control Spotify with a tap or swipe. Ride mode keeps your clock and music on a black screen.")
                        .foregroundStyle(.secondary)
                    GestureRow(title: "Tap anywhere", detail: "Play or pause")
                    GestureRow(title: "Swipe left", detail: "Next track")
                    GestureRow(title: "Swipe right", detail: "Previous track")
                    Text("Connect before setting off.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Continue", action: model.completeTutorial)
                        .buttonStyle(RideButtonStyle())
                        .accessibilityIdentifier("tutorial.continue")
                }
            case .connect:
                SetupPage {
                    Text("Connect your soundtrack.")
                        .font(.largeTitle.weight(.medium))
                    Text("Open Spotify and sign in on this device, then connect your account.")
                        .foregroundStyle(.secondary)
                    if let message = spotify.message {
                        Text(message).font(.callout)
                            .accessibilityIdentifier("connection.message")
                    }
                    Button(spotify.busy ? "Connecting…" : "Connect Spotify") { spotify.authorize(playback: true) }
                        .buttonStyle(RideButtonStyle())
                        .disabled(spotify.busy || spotify.loadingPlaylists)
                    Text("Connecting playback opens Spotify and may resume your music.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if spotify.busy {
                        ProgressView().tint(.white)
                        Button("Cancel connection", action: spotify.cancel)
                            .frame(minHeight: 44)
                    }
                    if spotify.authorized {
                        Button(spotify.loadingPlaylists ? "Checking playlists…" : "Check Web API playlist access", action: spotify.checkWebAPI)
                            .buttonStyle(RideButtonStyle())
                            .disabled(spotify.busy || spotify.loadingPlaylists)
                        Button("Forget Spotify account", action: spotify.signOut).frame(minHeight: 44)
                    } else {
                        Button("Connect Web API only") { spotify.authorize(playback: false) }
                            .buttonStyle(RideButtonStyle())
                            .disabled(spotify.busy || spotify.loadingPlaylists)
                    }
                    Button("Preview ride screen") { spotify.stopPlayback(); model.page = .ride }
                        .buttonStyle(RideButtonStyle())
                        .disabled(spotify.busy || spotify.loadingPlaylists)
                    Button("View tutorial") { model.page = .tutorial }
                        .frame(minHeight: 44).frame(maxWidth: .infinity)
                        .disabled(spotify.busy || spotify.loadingPlaylists)
                }
            case .ride:
                RideView(spotify: spotify) { spotify.stopPlayback(); model.page = .connect }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onChange(of: model.page, initial: true) { updateIdleTimer() }
        .onChange(of: scenePhase, initial: true) {
            updateIdleTimer()
            spotify.setActive(scenePhase == .active)
        }
        .onChange(of: spotify.connected) {
            if spotify.connected { model.page = .ride }
        }
        .onOpenURL { spotify.handleURL($0) }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            spotify.setActive(false)
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = model.page == .ride && scenePhase == .active
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
    let close: () -> Void
    @State private var notice: String?

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 60).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        spotify.perform(value.translation.width < 0 ? .next : .previous)
                    }.exclusively(before: TapGesture().onEnded { spotify.perform(.toggle) }))
                    .accessibilityLabel("Ride playback controls")
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
                if let message = spotify.message {
                    Text(message).font(.callout).multilineTextAlignment(.center)
                        .padding(32).allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        iconButton("xmark", label: "Close ride mode", action: close)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        iconButton("music.note.list", label: "Playlists") {
                            notice = "Use Check Web API playlist access on the connection page to verify your library. Playlist selection is coming in the next step."
                        }
                        Spacer()
                        iconButton("person.2", label: "Ride contacts") {
                            notice = "Ride contacts will be added in a later step."
                        }
                    }
                }.padding(8)
            }
        }
        .alert("Coming in a later step", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } }
        )) {
            Button("OK") { notice = nil }
        } message: {
            Text(notice ?? "")
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
