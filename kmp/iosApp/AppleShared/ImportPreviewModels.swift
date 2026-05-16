import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let xlsx = UTType(filenameExtension: "xlsx", conformingTo: .data)!
}

struct AppleStudentImportPreview: Identifiable {
    let id = UUID()
    let className: String?
    let course: String?
    let students: [AppleParsedStudent]
}

struct AppleParsedStudent: Identifiable {
    let id: Int
    let rowNumber: Int
    let fullName: String
    let firstName: String
    let lastName: String
}

extension Array where Element == [String] {
    var tsvText: String {
        map { row in
            row.map {
                $0
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
            }
            .joined(separator: "\t")
        }
        .joined(separator: "\n")
    }
}
