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
        let config = ModelConfiguration("Libreta", schema: schema)
        do {
            state = .ready(try ModelContainer(for: schema, configurations: config))
        } catch {
            // Sin fatalError: el archivo sigue ahí y se puede reintentar.
            state = .failed
        }
    }
}
