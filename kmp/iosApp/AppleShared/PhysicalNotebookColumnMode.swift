import Foundation

enum PhysicalNotebookColumnMode: String, CaseIterable, Identifiable {
    case rawOnly = "Solo marca"
    case rawAndScore = "Marca + nota baremada"
    case scoreOnly = "Solo nota baremada"

    var id: String { rawValue }
}
