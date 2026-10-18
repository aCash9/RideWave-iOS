import SwiftUI
import UIKit

struct RidePlaylistsView: View {
    @ObservedObject var library: SpotifyController
    @ObservedObject var playback: SpotifyController
    let close: () -> Void
    @State private var saved = PlaylistSelection()
    @State private var draft = PlaylistSelection()
    @State private var editing = false
    @State private var storageError: String?
    @State private var interaction = 0
    @State private var switchControl = UIAccessibility.isSwitchControlRunning
    @GestureState private var touching = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var loading: Bool { library.busy || library.loadingPlaylists }
    private var libraryFailed: Bool { library.authorized && !loading && library.playlistCount == nil }
    private var timerPaused: Bool {
        loading || !library.authorized || libraryFailed || playback.startingPlaylist ||
        playback.playlistPlaybackMessage != nil || storageError != nil || touching ||
        scenePhase != .active || voiceOver || switchControl
    }
    private var selected: [SpotifyPlaylist] {
        saved.ids.compactMap { id in library.playlists.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                HStack {
                    Text("PLAYLISTS").font(.caption).tracking(3).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if library.authorized && !editing {
                        Button("Edit") {
                            interact(); draft = saved; editing = true
                            playback.clearPlaylistFeedback(); library.checkWebAPI()
                        }.frame(minWidth: 44, minHeight: 56)
                    }
                    Button("Close", action: dismiss).frame(minWidth: 44, minHeight: 56)
                }
                if let error = storageError { Text(error).font(.callout) }
                if let message = playback.playlistPlaybackMessage {
                    Text(message).font(.callout).multilineTextAlignment(.center)
                    if !playback.connected {
                        Button(playback.busy ? "Connecting…" : "Reconnect Spotify") {
                            interact(); playback.authorize(playback: true)
                        }.disabled(playback.busy)
                    }
                    Button("Dismiss message") { interact(); playback.clearPlaylistFeedback() }
                }
                if loading {
                    ProgressView(library.loadingPlaylists ? "Loading playlists…" : library.progressTitle).tint(.white)
                }
                if playback.startingPlaylist { ProgressView("Starting playlist…").tint(.white) }
                if !library.authorized {
                    Spacer()
                    Text("Connect Spotify to choose up to four playlists.").multilineTextAlignment(.center)
                    if let message = library.message { Text(message).font(.callout) }
                    Button("Connect Web API") { interact(); library.authorize(playback: false) }
                        .buttonStyle(.bordered).disabled(loading)
                    Spacer()
                } else {
                    if libraryFailed {
                        Text(library.message ?? "Could not load playlists.").font(.callout)
                        Button("Retry") { interact(); library.checkWebAPI() }.frame(minHeight: 44)
                    }
                    if editing { picker }
                    else if selected.isEmpty {
                        Spacer()
                        Text("No playlists selected. Tap Edit to add up to four.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        bubbles(landscape: geometry.size.width > geometry.size.height)
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white).buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .updating($touching) { _, touching, _ in touching = true }
            .onChanged { _ in interact() })
        .task(id: "\(interaction)-\(timerPaused)") {
            guard !timerPaused else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            dismiss()
        }
        .onAppear {
            playback.clearPlaylistFeedback()
            do { saved = try PlaylistSelection.load(); draft = saved; editing = !saved.setupComplete }
            catch { storageError = "Saved playlists could not be read. Close and try again." }
            if library.authorized { library.checkWebAPI() }
        }
        .onChange(of: library.loadingPlaylists) {
            interact()
            if !library.loadingPlaylists && library.playlistCount != nil {
                draft.retainAvailable(Set(library.playlists.map(\.id)))
            }
        }
        .onChange(of: playback.startingPlaylist) { interact() }
        .onChange(of: scenePhase) { interact() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            switchControl = UIAccessibility.isSwitchControlRunning
        }
    }

    private var picker: some View {
        VStack(spacing: 12) {
            Text("Choose up to 4 playlists (\(draft.ids.count)/4)")
            ScrollView {
                LazyVStack(spacing: 12) {
                    if library.playlistCount == 0 { Text("No playlists found in this Spotify account.") }
                    ForEach(library.playlists) { playlist in
                        let checked = draft.ids.contains(playlist.id)
                        Button { interact(); draft.toggle(playlist.id) } label: {
                            HStack {
                                Text(playlist.name).multilineTextAlignment(.leading)
                                Spacer()
                                if checked { Image(systemName: "checkmark") }
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 56)
                                .background(checked ? Color(white: 0.19) : .clear, in: RoundedRectangle(cornerRadius: 28))
                                .overlay(RoundedRectangle(cornerRadius: 28).stroke(checked ? .white : .gray.opacity(0.5), lineWidth: checked ? 2 : 1))
                        }
                        .disabled(loading || (!checked && draft.ids.count >= 4))
                        .opacity(!checked && draft.ids.count >= 4 ? 0.4 : 1)
                        .accessibilityAddTraits(checked ? [.isSelected] : [])
                    }
                }.padding(.vertical, 4)
            }
            HStack {
                Button("Refresh") { interact(); library.checkWebAPI() }.disabled(loading)
                Spacer()
                Button("Done") {
                    interact()
                    do { saved = try draft.save(); editing = false }
                    catch { storageError = "Your playlist selection could not be saved. Please retry." }
                }.disabled(loading || libraryFailed || storageError != nil)
            }.frame(minHeight: 44)
            Button("Disconnect playlist access") {
                interact(); library.signOut(); PlaylistSelection.clear()
                saved = PlaylistSelection(); draft = saved; editing = true
            }.frame(minHeight: 44).disabled(loading)
        }
    }

    private func bubbles(landscape: Bool) -> some View {
        GeometryReader { area in
            let columns = landscape ? selected.count : min(2, selected.count)
            let diameter = min(180.0, max(64, (area.size.width - CGFloat(columns - 1) * 20) / CGFloat(columns)))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns), spacing: 24) {
                    ForEach(selected) { playlist in
                        Button { interact(); playback.playPlaylist(playlist) } label: {
                            VStack(spacing: 10) {
                                PlaylistArtwork(url: playlist.artworkURL, name: playlist.name)
                                    .frame(width: diameter, height: diameter).clipShape(Circle())
                                    .overlay(Circle().stroke(.gray.opacity(0.5), lineWidth: 1))
                                Text(playlist.name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                            }.contentShape(Rectangle())
                        }.disabled(playback.startingPlaylist)
                            .accessibilityLabel("Play \(playlist.name) with shuffle")
                    }
                }.frame(minHeight: area.size.height, alignment: .center)
            }
        }
    }

    private func interact() { interaction += 1 }
    private func dismiss() {
        if library.busy { library.cancel() }
        close()
    }
}
