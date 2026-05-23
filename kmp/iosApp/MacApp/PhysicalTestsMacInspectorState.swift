import SwiftUI
import Combine
import MiGestorKit

class PhysicalTestsMacInspectorState: ObservableObject {
    @Published var selectedSection: PhysicalTestsMacSection = .dashboard
    @Published var selectedTestId: Int64? = nil
    @Published var selectedTest: KmpBridge.PhysicalTestSnapshot? = nil
    @Published var selectedStudentId: Int64? = nil
    
    init() {}
}
