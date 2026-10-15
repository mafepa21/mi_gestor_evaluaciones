import SwiftUI
import SwiftData

/// Papel de una hoja: los cuatro papeles básicos y las plantillas impresas.
/// Es el papel por defecto de un cuaderno (`Notebook.paperStyle`) y, opcionalmente,
/// la plantilla propia de una hoja (`Page.templateRaw`).
enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case ruled, grid, dotted, blank
    case weekly, todo, cornell, staff
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ruled: "Rayado"
        case .grid: "Cuadriculado"
        case .dotted: "Puntos"
        case .blank: "Liso"
        case .weekly: "Semana"
        case .todo: "Tareas"
        case .cornell: "Cornell"
        case .staff: "Pentagrama"
        }
    }
    /// SF Symbol para menús.
    var systemImage: String {
        switch self {
        case .ruled: "line.3.horizontal"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        case .blank: "rectangle.portrait"
        case .weekly: "calendar"
        case .todo: "checklist"
        case .cornell: "sidebar.left"
        case .staff: "music.note"
        }
    }
}

// Nota: todos los atributos tienen valor por defecto y las relaciones son opcionales
// para que el esquema sea compatible con CloudKit (sincronización con iCloud).

@Model
final class Notebook {
    var id: UUID = UUID()
    var title: String = "Cuaderno"
    /// `CoverColor.rawValue` (definido en Design/).
    var coverColorRaw: String = "blue"
    var paperStyleRaw: String = PaperStyle.ruled.rawValue
    var createdAt: Date = Date()
    var lastOpenedAt: Date = Date()
    /// Última hoja (índice 0-based) en la que se estaba.
    var lastPageIndex: Int = 0
    /// Grupo (montón / balda) al que pertenece. `nil` = cuaderno suelto.
    var group: NotebookGroup?
    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page]? = []

    init(title: String, coverColorRaw: String, paperStyle: PaperStyle) {
        self.title = title
        self.coverColorRaw = coverColorRaw
        self.paperStyleRaw = paperStyle.rawValue
    }

    var paperStyle: PaperStyle {
        get { PaperStyle(rawValue: paperStyleRaw) ?? .ruled }
        set { paperStyleRaw = newValue.rawValue }
    }

    var pageList: [Page] { pages ?? [] }
    var sortedPages: [Page] { pageList.sorted { $0.index < $1.index } }

    // MARK: Gestión de hojas

    /// Renumera, asegura un número par de hojas (mínimo 2) y una hoja en blanco al final.
    func normalize() {
        var sorted = sortedPages
        func append() {
            let p = Page(index: sorted.count)
            pages = pageList + [p]
            sorted.append(p)
        }
        if !(sorted.last?.isBlank ?? false) { append() }
        while sorted.count < 2 || sorted.count % 2 != 0 { append() }
        for (i, p) in sorted.enumerated() where p.index != i { p.index = i }
    }

    @discardableResult
    func insertPage(after index: Int) -> Page {
        let sorted = sortedPages
        let newPage = Page(index: index + 1)
        for p in sorted where p.index > index { p.index += 1 }
        pages = pageList + [newPage]
        normalize()
        return newPage
    }

    func delete(_ page: Page) {
        guard pageList.count > 2 else { return }
        pages = pageList.filter { $0.id != page.id }
        page.modelContext?.delete(page)
        normalize()
    }

    func move(pageID: UUID, before targetID: UUID) {
        var sorted = sortedPages
        guard pageID != targetID,
              let from = sorted.firstIndex(where: { $0.id == pageID }) else { return }
        let moving = sorted.remove(at: from)
        let to = sorted.firstIndex(where: { $0.id == targetID }) ?? sorted.count
        sorted.insert(moving, at: to)
        for (i, p) in sorted.enumerated() { p.index = i }
        normalize()
    }
}

/// Grupo de cuadernos de un mismo tema: una balda en la estantería, un montón en la mesa.
/// Al borrarlo, sus cuadernos no se borran: pasan a sueltos (`.nullify`).
@Model
final class NotebookGroup {
    var id: UUID = UUID()
    var name: String = "Grupo"
    var createdAt: Date = Date()
    /// Posición del grupo en la biblioteca (menor = antes).
    var sortOrder: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Notebook.group)
    var notebooks: [Notebook]? = []

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }

    var notebookList: [Notebook] { notebooks ?? [] }

    /// Nombre para mostrar (nunca vacío).
    var displayName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Sin nombre" : t
    }
}

@Model
final class Page {
    var id: UUID = UUID()
    var index: Int = 0
    /// `PKDrawing.dataRepresentation()`
    @Attribute(.externalStorage) var drawingData: Data = Data()
    var isBookmarked: Bool = false
    /// Plantilla propia de la hoja (`PaperStyle.rawValue`). Vacío = la del cuaderno.
    var templateRaw: String = ""
    /// Texto reconocido (manuscrito + cajas de texto) para la búsqueda.
    var searchText: String = ""
    /// Tamaño de `drawingData` cuando se indexó por última vez.
    var indexedDrawingSize: Int = -1
    var notebook: Notebook?
    @Relationship(deleteRule: .cascade, inverse: \PageElement.page)
    var elements: [PageElement]? = []

    init(index: Int) { self.index = index }

    var elementList: [PageElement] { (elements ?? []).sorted { $0.order < $1.order } }
    var isBlank: Bool { drawingData.isEmpty && (elements ?? []).isEmpty }

    /// Papel con el que se dibuja esta hoja: su plantilla o, si no tiene (o no se
    /// reconoce), el papel del cuaderno.
    func style(in notebook: Notebook?) -> PaperStyle {
        PaperStyle(rawValue: templateRaw) ?? notebook?.paperStyle ?? .ruled
    }

    /// `style(in:)` con el cuaderno al que pertenece la hoja.
    var effectiveStyle: PaperStyle { style(in: notebook) }
}

enum ElementKind: String { case image, text, sticker }

/// Imagen, caja de texto o pegatina colocada sobre una hoja (bajo la tinta).
/// Coordenadas en el espacio lógico de la hoja (`PageGeometry.logicalSize`); (x, y) es el centro.
@Model
final class PageElement {
    var id: UUID = UUID()
    var kindRaw: String = ElementKind.sticker.rawValue
    var x: Double = 410
    var y: Double = 570
    var width: Double = 120
    var height: Double = 120
    var rotation: Double = 0      // radianes
    var scale: Double = 1
    var order: Int = 0
    /// Texto de la caja o emoji de la pegatina.
    var text: String = ""
    var fontSize: Double = 36
    /// "ink", "red", "blue", "green"
    var colorRaw: String = "ink"
    @Attribute(.externalStorage) var imageData: Data?
    var page: Page?

    init(kind: ElementKind) { self.kindRaw = kind.rawValue }

    var kind: ElementKind { ElementKind(rawValue: kindRaw) ?? .sticker }

    var textColor: Color { Self.textColor(for: colorRaw) }

    static func textColor(for raw: String) -> Color {
        switch raw {
        case "red": Color(red: 0.75, green: 0.16, blue: 0.16)
        case "blue": Color(red: 0.13, green: 0.32, blue: 0.70)
        case "green": Color(red: 0.14, green: 0.52, blue: 0.30)
        default: Color(red: 0.12, green: 0.12, blue: 0.14)
        }
    }
    static let colorChoices = ["ink", "red", "blue", "green"]
}
