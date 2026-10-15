import Foundation
import SwiftData

/// Copia de seguridad legible (JSON) de cuadernos, grupos, hojas, tinta y objetos.
///
/// Versión 2 añade los grupos (`groups`, `NotebookDTO.groupID`). Ambos son opcionales
/// para seguir leyendo copias de la versión 1.
struct BackupFile: Codable {
    var version = 2
    var exportedAt = Date()
    /// Grupos de cuadernos. Opcional: las copias antiguas no los tienen.
    var groups: [GroupDTO]?
    var notebooks: [NotebookDTO]

    struct GroupDTO: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
        var sortOrder: Int
    }
    struct NotebookDTO: Codable {
        var id: UUID
        var title: String
        var coverColorRaw: String
        var paperStyleRaw: String
        var createdAt: Date
        var lastOpenedAt: Date
        var lastPageIndex: Int
        var pages: [PageDTO]
        /// Grupo del cuaderno. Opcional: `nil` = suelto (o copia antigua).
        var groupID: UUID?
    }
    struct PageDTO: Codable {
        var id: UUID
        var index: Int
        var drawingData: Data
        var isBookmarked: Bool
        var searchText: String
        /// Plantilla propia de la hoja. Opcional: las copias antiguas no la tienen.
        var templateRaw: String?
        var elements: [ElementDTO]
    }
    struct ElementDTO: Codable {
        var id: UUID
        var kindRaw: String
        var x, y, width, height, rotation, scale: Double
        var order: Int
        var text: String
        var fontSize: Double
        var colorRaw: String
        var imageData: Data?
    }
}

enum Backup {
    /// Resultado de una restauración.
    struct RestoreResult {
        var notebooks = 0
        var groups = 0
    }

    /// Codifica los cuadernos y sus grupos. `groups` añade grupos extra (p. ej. los
    /// vacíos al copiar toda la biblioteca); los de los cuadernos se incluyen siempre.
    static func encode(_ notebooks: [Notebook], groups extraGroups: [NotebookGroup] = []) throws -> Data {
        var seen = Set<UUID>()
        var groups: [NotebookGroup] = []
        for g in extraGroups + notebooks.compactMap(\.group) {
            if seen.insert(g.id).inserted { groups.append(g) }
        }
        let file = BackupFile(
            groups: groups.map { g in
                BackupFile.GroupDTO(id: g.id, name: g.name, createdAt: g.createdAt, sortOrder: g.sortOrder)
            },
            notebooks: notebooks.map { nb in
            BackupFile.NotebookDTO(id: nb.id, title: nb.title, coverColorRaw: nb.coverColorRaw,
                  paperStyleRaw: nb.paperStyleRaw, createdAt: nb.createdAt,
                  lastOpenedAt: nb.lastOpenedAt, lastPageIndex: nb.lastPageIndex,
                  pages: nb.sortedPages.map { p in
                BackupFile.PageDTO(id: p.id, index: p.index, drawingData: p.drawingData,
                      isBookmarked: p.isBookmarked, searchText: p.searchText,
                      templateRaw: p.templateRaw,
                      elements: p.elementList.map { e in
                    BackupFile.ElementDTO(id: e.id, kindRaw: e.kindRaw, x: e.x, y: e.y, width: e.width,
                          height: e.height, rotation: e.rotation, scale: e.scale, order: e.order,
                          text: e.text, fontSize: e.fontSize, colorRaw: e.colorRaw,
                          imageData: e.imageData)
                })
            },
                  groupID: nb.group?.id)
        })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func write(_ notebooks: [Notebook], groups: [NotebookGroup] = [], name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(PageRenderer.safeFileName(name))
            .appendingPathExtension("json")
        try encode(notebooks, groups: groups).write(to: url, options: .atomic)
        return url
    }

    /// Importa los grupos y cuadernos que aún no existen (por id), sin duplicar nada.
    /// Los cuadernos nuevos entran en su grupo; un cuaderno que ya existía y está suelto
    /// entra en su grupo solo si ese grupo se acaba de restaurar.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext) throws -> RestoreResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        var result = RestoreResult()

        // Grupos: se respetan los ids; los nuevos van detrás de los existentes, en su orden.
        let existingGroups = try context.fetch(FetchDescriptor<NotebookGroup>())
        var groupsByID = Dictionary(existingGroups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var restoredGroupIDs = Set<UUID>()
        var nextOrder = (existingGroups.map(\.sortOrder).max() ?? -1) + 1
        for gd in (file.groups ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }) where groupsByID[gd.id] == nil {
            let g = NotebookGroup(name: gd.name, sortOrder: nextOrder)
            g.id = gd.id
            g.createdAt = gd.createdAt
            context.insert(g)
            groupsByID[gd.id] = g
            restoredGroupIDs.insert(gd.id)
            nextOrder += 1
            result.groups += 1
        }

        let existingNotebooks = Dictionary(try context.fetch(FetchDescriptor<Notebook>()).map { ($0.id, $0) },
                                           uniquingKeysWith: { a, _ in a })
        for dto in file.notebooks {
            if let current = existingNotebooks[dto.id] {
                if current.group == nil, let gid = dto.groupID, restoredGroupIDs.contains(gid) {
                    current.group = groupsByID[gid]
                }
                continue
            }
            let nb = Notebook(title: dto.title, coverColorRaw: dto.coverColorRaw,
                              paperStyle: PaperStyle(rawValue: dto.paperStyleRaw) ?? .ruled)
            nb.id = dto.id
            nb.createdAt = dto.createdAt
            nb.lastOpenedAt = dto.lastOpenedAt
            nb.lastPageIndex = dto.lastPageIndex
            context.insert(nb)
            if let gid = dto.groupID { nb.group = groupsByID[gid] }
            nb.pages = dto.pages.map { pd in
                let p = Page(index: pd.index)
                p.id = pd.id
                p.drawingData = pd.drawingData
                p.isBookmarked = pd.isBookmarked
                p.searchText = pd.searchText
                p.templateRaw = pd.templateRaw ?? ""
                p.indexedDrawingSize = pd.drawingData.count
                p.elements = pd.elements.map { ed in
                    let e = PageElement(kind: ElementKind(rawValue: ed.kindRaw) ?? .sticker)
                    e.id = ed.id
                    e.x = ed.x; e.y = ed.y; e.width = ed.width; e.height = ed.height
                    e.rotation = ed.rotation; e.scale = ed.scale; e.order = ed.order
                    e.text = ed.text; e.fontSize = ed.fontSize; e.colorRaw = ed.colorRaw
                    e.imageData = ed.imageData
                    return e
                }
                return p
            }
            nb.normalize()
            result.notebooks += 1
        }
        return result
    }
}
