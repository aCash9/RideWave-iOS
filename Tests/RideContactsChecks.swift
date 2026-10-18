import Foundation

@main
struct RideContactsChecks {
    static func check(_ condition: Bool) { precondition(condition) }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RideContactsChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RideContactStorage(file: directory.appendingPathComponent("contacts.json"))
        check(try storage.load().isEmpty)
        let first = try RideContact(name: "Alex", number: "+1 (202) 555-0100", photo: Data([1, 2, 3]))
        precondition(first.number == "+12025550100")
        check(try ContactPhone.callURL(first.number).absoluteString == "tel:+12025550100")
        var contacts = try storage.adding(first, to: [])
        try storage.save(contacts)
        check(try storage.load() == contacts)
        let duplicate = try RideContact(name: "Same number", number: "+1 202-555-0100")
        do { _ = try storage.adding(duplicate, to: contacts); fatalError("Duplicate accepted") }
        catch ContactError.duplicate {}
        for number in ["2025550101", "2025550102", "2025550103"] {
            contacts = try storage.adding(RideContact(name: "Test", number: number), to: contacts)
        }
        do { _ = try storage.adding(RideContact(name: "Fifth", number: "2025550104"), to: contacts); fatalError("Exceeded four") }
        catch ContactError.full {}
        try storage.save(contacts)
        check(try storage.load().count == 4)
        contacts.removeFirst()
        try storage.save(contacts)
        check(try storage.load() == contacts)
        for number in ["", "+", "*123#", "2025550100;123", "2025550100?x=y", "tel:2025550100", "2025550100 ext 1", "++12025550100"] {
            do { _ = try ContactPhone.callURL(number); fatalError("Unsafe/unsupported number accepted") }
            catch ContactError.invalidNumber {}
        }
        let noName = try RideContact(name: "  ", number: "2025550100")
        precondition(noName.name == noName.number)
        let original = try Data(contentsOf: storage.file)
        let badStorage = RideContactStorage(file: storage.file.appendingPathComponent("cannot-write.json"))
        do { try badStorage.save([]); fatalError("Expected save failure") } catch {}
        check(try Data(contentsOf: storage.file) == original)
        try Data("invalid".utf8).write(to: storage.file)
        do { _ = try storage.load(); fatalError("Corrupt file accepted") } catch {}
        check(try String(contentsOf: storage.file, encoding: .utf8) == "invalid")
        print("Contacts checks passed: persistence, removal, four-contact limit, normalized duplicates, phone URLs, unsupported numbers, and storage failures. No calls placed.")
    }
}
