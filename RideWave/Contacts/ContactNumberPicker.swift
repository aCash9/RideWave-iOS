import Contacts
import ContactsUI
import ImageIO
import SwiftUI

struct ContactNumberPicker: UIViewControllerRepresentable {
    let selected: (Result<RideContact, Error>) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // With only the property-selection delegate, a contact opens its number list.
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == %@", CNContactPhoneNumbersKey)
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactNumberPicker
        private var finished = false
        init(parent: ContactNumberPicker) { self.parent = parent }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            guard !finished else { return }
            finished = true
            parent.cancelled()
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            guard !finished else { return }
            finished = true
            do {
                guard property.key == CNContactPhoneNumbersKey,
                      let phone = property.value as? CNPhoneNumber else { throw ContactError.invalidNumber }
                let contact = property.contact
                let nameKeys = [CNContactGivenNameKey, CNContactFamilyNameKey]
                let name = nameKeys.allSatisfy { contact.isKeyAvailable($0) }
                    ? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ") : ""
                let photo = contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil
                parent.selected(.success(try RideContact(name: name, number: phone.stringValue, photo: thumbnail(photo))))
            } catch { parent.selected(.failure(error)) }
        }

        private func thumbnail(_ data: Data?) -> Data? {
            guard let data, data.count <= 8_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 384,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
        }
    }
}
