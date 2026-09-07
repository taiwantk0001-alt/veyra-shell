import Contacts
import Foundation

/// Read every contact phone number into Android-compatible JSON: [{name, phone}, ...]
enum ContactsReader {
  static func isAuthorized() -> Bool {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .authorized { return true }
    if #available(iOS 18.0, *) {
      return status == .limited
    }
    return false
  }

  static func requestAccess(completion: @escaping (Bool) -> Void) {
    if isAuthorized() {
      completion(true)
      return
    }
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .denied || status == .restricted {
      completion(false)
      return
    }
    CNContactStore().requestAccess(for: .contacts) { ok, _ in
      DispatchQueue.main.async {
        completion(ok && isAuthorized())
      }
    }
  }

  /// All phone numbers for all contacts (one JSON object per number), same shape as Android.
  static func allContactsJSON() -> String {
    guard isAuthorized() else { return "[]" }

    let store = CNContactStore()
    let keys: [CNKeyDescriptor] = [
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.unifyResults = true

    var rows: [[String: String]] = []
    do {
      try store.enumerateContacts(with: request) { contact, _ in
        var display =
          CNContactFormatter.string(from: contact, style: .fullName)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if display.isEmpty {
          display = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if display.isEmpty {
          display = "未知"
        }
        for labeled in contact.phoneNumbers {
          let phone = labeled.value.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if phone.isEmpty { continue }
          rows.append(["name": display, "phone": phone])
        }
      }
    } catch {
      return "[]"
    }

    guard JSONSerialization.isValidJSONObject(rows),
          let data = try? JSONSerialization.data(withJSONObject: rows, options: []),
          let json = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return json
  }
}
