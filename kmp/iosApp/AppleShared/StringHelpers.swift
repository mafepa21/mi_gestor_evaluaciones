import Foundation

public extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where !value.isEmpty: return value
        default: return nil
        }
    }
}

public extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
