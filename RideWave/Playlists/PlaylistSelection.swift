import Foundation

/// Only Done commits the draft. An empty saved selection is distinct from first setup.
struct PlaylistSelection: Codable, Equatable {
    private(set) var ids: [String] = []
    private(set) var setupComplete = false

    mutating func toggle(_ id: String) {
        if ids.contains(id) { ids.removeAll { $0 == id } }
        else if ids.count < 4 { ids.append(id) }
    }

    mutating func retainAvailable(_ available: Set<String>) {
        ids = ids.filter { available.contains($0) }
    }

    func save(to defaults: UserDefaults = .standard) throws -> PlaylistSelection {
        var saved = self
        saved.setupComplete = true
        defaults.set(try JSONEncoder().encode(saved), forKey: Self.key)
        return saved
    }

    static func load(from defaults: UserDefaults = .standard) throws -> PlaylistSelection {
        guard let data = defaults.data(forKey: key) else { return PlaylistSelection() }
        let saved = try JSONDecoder().decode(Self.self, from: data)
        guard saved.ids.count <= 4, Set(saved.ids).count == saved.ids.count else {
            throw CocoaError(.coderReadCorrupt)
        }
        return saved
    }

    static func clear(in defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
    private static let key = "ride_playlist_selection_v1"
}
