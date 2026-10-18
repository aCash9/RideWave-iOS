import Foundation

@main
struct PlaylistSelectionChecks {
    static func main() throws {
        let suite = "PlaylistSelectionChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(tryLoad(defaults).setupComplete == false)
        var draft = PlaylistSelection()
        for id in ["a", "b", "c", "d", "e"] { draft.toggle(id) }
        precondition(draft.ids == ["a", "b", "c", "d"])
        let saved = try draft.save(to: defaults)
        draft.toggle("b"); draft.toggle("e")
        precondition(draft.ids == ["a", "c", "d", "e"])
        precondition(tryLoad(defaults) == saved, "Unfinished edits must not change saved choices")
        draft.retainAvailable(["a", "e"])
        precondition(draft.ids == ["a", "e"])
        _ = try draft.save(to: defaults)
        precondition(tryLoad(defaults).ids == ["a", "e"])
        _ = try PlaylistSelection().save(to: defaults)
        precondition(tryLoad(defaults).setupComplete && tryLoad(defaults).ids.isEmpty)
        PlaylistSelection.clear(in: defaults)
        precondition(!tryLoad(defaults).setupComplete)
        let withoutImages = try JSONDecoder().decode(SpotifyPlaylist.self, from: Data(#"{"id":"a","name":"A","uri":"spotify:playlist:a"}"#.utf8))
        precondition(withoutImages.artworkURL == nil)
        let withImages = try JSONDecoder().decode(SpotifyPlaylist.self, from: Data(#"{"id":"a","name":"A","uri":"spotify:playlist:a","images":[{"url":"http://unsafe.example/a"},{"url":"https://images.example/a"}]}"#.utf8))
        precondition(withImages.artworkURL?.host == "images.example")
        print("Playlist selection and artwork checks passed")
    }
    static func tryLoad(_ defaults: UserDefaults) -> PlaylistSelection { try! PlaylistSelection.load(from: defaults) }
}
