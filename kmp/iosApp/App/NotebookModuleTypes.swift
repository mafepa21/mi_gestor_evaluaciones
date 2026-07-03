import SwiftUI
import MiGestorKit

enum NotebookAttendanceStatus {
    static let present = "PRESENTE"
    static let absent = "AUSENTE"
    static let late = "TARDE"
    static let justified = "JUSTIFICADO"
    static let noMaterial = "SIN_MATERIAL"
    static let exempt = "EXENTO"

    static func canonical(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case present, "PRESENT", "PRES":
            return present
        case absent, "ABSENT", "AUS":
            return absent
        case late, "RETRASO", "LATE":
            return late
        case justified, "JUSTIFICADA", "JUSTIFIED":
            return justified
        case noMaterial:
            return noMaterial
        case exempt:
            return exempt
        default:
            return ""
        }
    }
}

struct NotebookInspectorSelection: Identifiable, Hashable {
    static let averageColumnId = "__notebook_average__"

    let studentId: Int64
    let columnId: String

    var id: String { "\(studentId)|\(columnId)" }
    var isAverage: Bool { columnId == Self.averageColumnId }
}

final class NotebookMacInspectorState: ObservableObject {
    @Published var selection: NotebookInspectorSelection?
    @Published var noteDraft = ""
    @Published var iconDraft = ""
    @Published var attachmentUris: [String] = []
    @Published var isPresented = false

    func resetDrafts() {
        noteDraft = ""
        iconDraft = ""
        attachmentUris = []
    }
}

/// Pilas de deshacer/rehacer de celdas del Cuaderno, separadas de `NotebookModuleView`
/// para que cambien sin formar parte de sus ~100 `@State` de la vista raiz.
final class NotebookUndoStore: ObservableObject {
    @Published var undoStack: [NotebookCellUndoEntry] = []
    @Published var redoStack: [NotebookCellUndoEntry] = []

    func reset() {
        undoStack = []
        redoStack = []
    }
}

/// Señales del dia (asistencia de hoy, incidencias) usadas por el plano de aula y el
/// resumen de asistencia por fila, separadas de `NotebookModuleView` por el mismo motivo.
final class NotebookAttendanceSignalsStore: ObservableObject {
    @Published var todayAttendanceByStudentId: [Int64: String] = [:]
    @Published var incidentCountByStudentId: [Int64: Int] = [:]

    func reset() {
        todayAttendanceByStudentId = [:]
        incidentCountByStudentId = [:]
    }
}

enum NotebookMacPresentation: Equatable {
    case full
    case content
    case inspector
}

struct NotebookTableRow: Identifiable {
    let student: Student
    let row: NotebookRow
    let groupName: String

    var id: Int64 { student.id }
}

enum NotebookDeletionKind {
    case column
    case category
    case columns
}

struct NotebookDeletionImpactDraft: Identifiable {
    let id = UUID()
    let kind: NotebookDeletionKind
    let targetId: String
    let targetName: String
    let affectedColumns: [NotebookColumnDefinition]
    let affectedGradeCount: Int
    let affectedFormulaColumnCount: Int
    let affectedAverageColumnCount: Int
    let hasLockedColumns: Bool

    var affectedColumnCount: Int { affectedColumns.count }
    var requiresStrongConfirmation: Bool { affectedGradeCount > 0 }
}

enum NotebookFixedColumn: String, Identifiable, CaseIterable {
    case photo
    case name
    case group
    case followUp
    case attendance
    case average

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Foto"
        case .name: return "Nombre"
        case .group: return "Grupo"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .average: return "Media"
        }
    }

    var subtitle: String {
        switch self {
        case .photo: return "Alumno"
        case .name: return "Alumno"
        case .group: return "Contexto"
        case .followUp: return "Estado"
        case .attendance: return "Resumen"
        case .average: return "Promedio"
        }
    }

    var width: CGFloat {
        switch self {
        case .photo: return 82
        case .name: return 180
        case .group: return 110
        case .followUp: return 120
        case .attendance: return 120
        case .average: return 110
        }
    }
}

enum NotebookDisplaySegment: Identifiable {
    case fixed(NotebookFixedColumn)
    case column(NotebookColumnDefinition)
    case collapsedCategory(NotebookColumnCategory, [NotebookColumnDefinition])

    var id: String {
        switch self {
        case .fixed(let fixed):
            return "fixed_\(fixed.rawValue)"
        case .column(let column):
            return "column_\(column.id)"
        case .collapsedCategory(let category, _):
            return "collapsed_\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .fixed(let fixed):
            return fixed.title
        case .column(let column):
            return column.title
        case .collapsedCategory(let category, _):
            return category.name
        }
    }
}

enum NotebookViewPreset: String, CaseIterable, Identifiable {
    case all
    case evaluation
    case followUp
    case attendance
    case extras
    case physicalEducation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Vista completa"
        case .evaluation: return "Vista evaluación"
        case .followUp: return "Vista seguimiento"
        case .attendance: return "Vista asistencia"
        case .extras: return "Vista extras"
        case .physicalEducation: return "Vista EF"
        }
    }
}

enum NotebookSurfaceMode: String, CaseIterable, Identifiable {
    case grid
    case seatingPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Rejilla"
        case .seatingPlan: return "Plano"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "tablecells"
        case .seatingPlan: return "square.grid.3x3.square"
        }
    }
}

struct NotebookSeatPosition: Codable {
    var x: Double
    var y: Double
}

struct NotebookAddColumnContext: Identifiable {
    let categoryId: String?
    let startsCreatingCategory: Bool

    var id: String {
        "\(categoryId ?? "none")|\(startsCreatingCategory)"
    }
}

enum NotebookToastStyle: Equatable {
    case success
    case warning

    var tint: Color {
        switch self {
        case .success: return NotebookStyle.successTint
        case .warning: return NotebookStyle.warningTint
        }
    }
}

struct NotebookToast: Identifiable {
    let id = UUID()
    let message: String
    let style: NotebookToastStyle
}

enum NotebookHeaderLaneItem: Identifiable {
    case spacer(id: String, width: CGFloat)
    case folder(NotebookColumnCategory, [NotebookColumnDefinition], CGFloat)

    var id: String {
        switch self {
        case .spacer(let id, _): return id
        case .folder(let category, _, _): return "folder_\(category.id)"
        }
    }
}

enum NotebookAIFlowMode {
    case createColumn
    case selection
}

enum NotebookAIColumnScope: String, CaseIterable, Identifiable {
    case visibleColumns
    case evaluableColumns
    case allManagedColumns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visibleColumns: return "Columnas visibles"
        case .evaluableColumns: return "Solo evaluables"
        case .allManagedColumns: return "Todas las gestionadas"
        }
    }
}

struct NotebookAISheetRequest: Identifiable {
    let mode: NotebookAIFlowMode
    let studentIds: [Int64]
    let targetColumnId: String?

    var id: String {
        let modeLabel = mode == .createColumn ? "create" : "selection"
        return "\(modeLabel)|\(studentIds.map(String.init).joined(separator: ","))|\(targetColumnId ?? "none")"
    }
}

struct NotebookSummarySheetRequest: Identifiable {
    let targetColumnId: String?

    var id: String { targetColumnId ?? "summary" }
}

enum NotebookNavigationDirection: String, CaseIterable, Identifiable {
    case up
    case down
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return "Arriba"
        case .down: return "Abajo"
        case .left: return "Izquierda"
        case .right: return "Derecha"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}

struct NotebookFormulaEditRequest: Identifiable {
    let columnId: String

    var id: String { columnId }
}

struct NotebookFormulaCellDisplay {
    let text: String
    let isError: Bool
}

struct NotebookCellUndoEntry {
    let studentId: Int64
    let column: NotebookColumnDefinition
    let previousValue: String
    let previousDisplayLabel: String?
}
