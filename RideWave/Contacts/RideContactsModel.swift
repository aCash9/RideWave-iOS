import Combine
import Foundation
import UIKit

@MainActor
final class RideContactsModel: ObservableObject {
    @Published private(set) var contacts: [RideContact] = []
    @Published var error: String?
    @Published private(set) var calling = false
    @Published private(set) var loaded = false
    private let storage: RideContactStorage
    private var callAttempt: UUID?

    init(storage: RideContactStorage? = nil) {
        self.storage = storage ?? .standard
        reload()
    }

    func reload() {
        do { contacts = try storage.load(); loaded = true; error = nil }
        catch { loaded = false; self.error = ContactError.unavailable.localizedDescription }
    }

    func add(_ contact: RideContact) {
        guard loaded else { return }
        do {
            let updated = try storage.adding(contact, to: contacts)
            try storage.save(updated)
            contacts = updated
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ contact: RideContact) {
        guard loaded else { return }
        do {
            let updated = contacts.filter { $0.id != contact.id }
            try storage.save(updated)
            contacts = updated
        } catch { self.error = "Could not save your contacts. Please retry." }
    }

    func call(_ contact: RideContact) {
        guard !calling else { return }
        do {
            let url = try ContactPhone.callURL(contact.number)
            let attempt = UUID()
            callAttempt = attempt
            calling = true
            // iOS presents its own confirmation. Never bypass it or auto-retry a call.
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                guard let self, self.callAttempt == attempt else { return }
                self.calling = false
                self.callAttempt = nil
                if !opened { self.error = "The call was cancelled or calling is unavailable on this device." }
            }
        } catch { self.error = error.localizedDescription }
    }

    func returnedToApp() {
        calling = false
        callAttempt = nil
    }
}
