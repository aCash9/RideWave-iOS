import Foundation

struct RideContact: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let number: String
    let photo: Data?

    init(name: String, number: String, photo: Data? = nil) throws {
        id = UUID()
        self.number = try ContactPhone.normalized(number)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? self.number : name
        self.photo = photo
    }
}

enum ContactPhone {
    static func normalized(_ value: String) throws -> String {
        var result = ""
        for character in value {
            if character.isASCII, character.isNumber { result.append(character) }
            else if character == "+", result.isEmpty { result.append(character) }
            else if character.isWhitespace || "()- .".contains(character) { continue }
            else { throw ContactError.invalidNumber }
        }
        let digits = result.filter(\.isNumber)
        guard !digits.isEmpty, digits.count <= 20 else { throw ContactError.invalidNumber }
        return result
    }

    static func callURL(_ value: String) throws -> URL {
        guard let url = URL(string: "tel:" + (try normalized(value))) else { throw ContactError.invalidNumber }
        return url
    }
}

enum ContactError: LocalizedError {
    case invalidNumber, duplicate, full, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidNumber: return "Choose a phone number containing digits and an optional country code. Extensions and special dialing codes are not supported."
        case .duplicate: return "This phone number is already in your ride contacts."
        case .full: return "You can save up to four ride contacts. Remove one before adding another."
        case .unavailable: return "Could not read saved ride contacts. Your saved file has been left unchanged."
        }
    }
}

struct RideContactStorage {
    let file: URL

    static var standard: RideContactStorage {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RideContacts", isDirectory: true)
        return RideContactStorage(file: directory.appendingPathComponent("contacts.json"))
    }

    func load() throws -> [RideContact] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let contacts = try JSONDecoder().decode([RideContact].self, from: Data(contentsOf: file))
        guard contacts.count <= 4, Set(contacts.map(\.id)).count == contacts.count,
              Set(contacts.map(\.number)).count == contacts.count else { throw ContactError.unavailable }
        for contact in contacts {
            guard try ContactPhone.normalized(contact.number) == contact.number,
                  (contact.photo?.count ?? 0) <= 1_000_000 else { throw ContactError.unavailable }
        }
        return contacts
    }

    func adding(_ contact: RideContact, to contacts: [RideContact]) throws -> [RideContact] {
        guard !contacts.contains(where: { $0.number == contact.number }) else { throw ContactError.duplicate }
        guard contacts.count < 4 else { throw ContactError.full }
        return contacts + [contact]
    }

    func save(_ contacts: [RideContact]) throws {
        guard contacts.count <= 4 else { throw ContactError.full }
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try directory.setResourceValues(resourceValues)
        let data = try JSONEncoder().encode(contacts)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: [.atomic])
        #endif
    }
}
