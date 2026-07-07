import SwiftUI
import Combine
import MiGestorKit

class PhysicalTestsMacInspectorState: ObservableObject {
    @Published var selectedSection: PhysicalTestsMacSection = .dashboard
    @Published var selectedTest: KmpBridge.PhysicalTestSnapshot? = nil
    @Published var selectedStudentId: Int64? = nil

    // Derivado de selectedTest para que no pueda desincronizarse de él.
    var selectedTestId: Int64? {
        selectedTest?.evaluation.id
    }

    init() {}
}
