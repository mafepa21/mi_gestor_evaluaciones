import SwiftUI

@MainActor
final class IOSSelectionStore: ObservableObject {
    @Published var selectedClassId: Int64?
    @Published var selectedStudentId: Int64?
    @Published private(set) var revision = 0

    func select(classId: Int64?, studentId: Int64?) {
        guard selectedClassId != classId || selectedStudentId != studentId else { return }
        selectedClassId = classId
        selectedStudentId = studentId
        revision &+= 1
    }
}
