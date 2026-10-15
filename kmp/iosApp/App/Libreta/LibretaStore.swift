import SwiftUI
import SwiftData

/// Base de datos de la Libreta: SwiftData en su propio archivo (`Libreta.store`),
/// separada de la base de KMP/SQLDelight. Se abre la primera vez que se entra en el
/// módulo, así no frena el arranque de la app.
@MainActor
final class LibretaStore: ObservableObject {
    static let shared = LibretaStore()

    enum State {
        case loading
        case ready(ModelContainer)
        case failed
    }

    @Published private(set) var state: State = .loading

    /// Petición de abrir la libreta de una clase (desde el Diario o el Planner).
    struct ClassOpenRequest: Equatable, Identifiable {
        let id = UUID()
        let classId: Int64
        let className: String
    }

    /// La atiende `LibraryView` en cuanto está en pantalla, y la borra.
    @Published var classOpenRequest: ClassOpenRequest?

    func openForClass(id: Int64, name: String) {
        classOpenRequest = ClassOpenRequest(classId: id, className: name)
    }

    private init() {}

    private var pendingRetry: Task<Void, Never>?

    func loadIfNeeded() {
        if case .ready = state { return }
        // Si hay un reintento en marcha, él abrirá la base: no crear dos contenedores.
        guard pendingRetry == nil else { return }
        load()
    }

    func retry() {
        guard pendingRetry == nil else { return }
        state = .loading
        // Un respiro para que se vea que se está reintentando.
        pendingRetry = Task {
            try? await Task.sleep(for: .milliseconds(300))
            load()
            pendingRetry = nil
        }
    }

    private func load() {
        let schema = Schema([Notebook.self, NotebookGroup.self, Page.self, PageElement.self])
        // Ruta fija y compartida con las copias de Seguridad (`LibretaStorage`).
        // Es la misma que SwiftData usaba por defecto en la fase 1.
        let storage = LibretaStorage.standard
        try? FileManager.default.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)
        let config = ModelConfiguration("Libreta", schema: schema, url: storage.storeURL)
        do {
            state = .ready(try ModelContainer(for: schema, configurations: config))
        } catch {
            // Sin fatalError: el archivo sigue ahí y se puede reintentar.
            state = .failed
        }
    }
}
