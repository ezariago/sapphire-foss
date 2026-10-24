#if !SAPPHIRE_FULL_BUILD
import Foundation

struct PhoneActionDraft: Equatable, Sendable {
    enum Kind: String, Sendable { case sms, dial }
    let kind: Kind
    let number: String
    let body: String
    static func make(kind: Kind, number input: String, body: String = "") -> Self? {
        guard input.utf16.count <= 40 else { return nil }
        let number = input.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
        let digits = number.hasPrefix("+") ? number.dropFirst() : number[...]
        guard (7...15).contains(digits.utf8.count), digits.utf8.allSatisfy({ (48...57).contains($0) }),
              body.utf8.count <= 4000,
              body.unicodeScalars.allSatisfy({ scalar in
                  let value = scalar.value
                  return value == 9 || value == 10 || value == 13 || (value >= 32 && !(127...159).contains(value))
              }), kind != .dial || body.isEmpty else { return nil }
        return .init(kind: kind, number: number, body: body)
    }
}
#endif
