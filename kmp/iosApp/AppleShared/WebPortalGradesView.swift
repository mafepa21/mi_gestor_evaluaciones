import SwiftUI

/// Pestaña «Notas visibles» del portal del alumnado (maqueta fase 2, estados P1 a P5).
///
/// Solo el Mac cambia los interruptores (decisión 4.3 del ticket): en iPad se ven
/// desactivados con el aviso P5. No hay «Publicar ahora»: todo se publica solo 10 minutos
/// después del último cambio.

// MARK: - Modelo

@MainActor
final class WebPortalGradesViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded }

    @Published private(set) var overview: WebPortalGradeOverview?
    @Published private(set) var settings = WebPortalGroupGradeSettings()
    @Published private(set) var phase: Phase = .idle
    /// Columna que se acaba de encender por primera vez y espera confirmación (P2).
    @Published var pendingConfirmation: WebPortalGradeColumnRow?

    let settingsURL: URL
    /// Solo el Mac edita.
    let canEdit: Bool
    private let loadOverview: (Int64) async -> WebPortalGradeOverview?
    /// Pide a la app que ponga el grupo en la cola de 10 minutos.
    private let changed: (Int64) -> Void
    private(set) var classId: Int64 = 0

    init(
        settingsURL: URL,
        canEdit: Bool = WebPortalGradesViewModel.platformCanEdit,
        loadOverview: @escaping (Int64) async -> WebPortalGradeOverview?,
        changed: @escaping (Int64) -> Void
    ) {
        self.settingsURL = settingsURL
        self.canEdit = canEdit
        self.loadOverview = loadOverview
        self.changed = changed
    }

    nonisolated static var platformCanEdit: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    func load(classId: Int64) async {
        self.classId = classId
        pendingConfirmation = nil
        settings = WebPortalGradeSettings.load(fileURL: settingsURL)[classId]
        phase = .loading
        let loaded = await loadOverview(classId)
        guard self.classId == classId else { return }
        overview = loaded
        phase = .loaded
    }

    var columns: [WebPortalGradeColumnRow] { overview?.columns ?? [] }

    func isOn(_ column: WebPortalGradeColumnRow) -> Bool { settings.isVisible(columnId: column.id) }

    func setMedia(_ on: Bool) {
        guard canEdit else { return }
        apply { $0.media = on }
    }

    /// Apagar es inmediato. Encender por primera vez pide confirmación (P2).
    func requestColumn(_ column: WebPortalGradeColumnRow, on: Bool) {
        guard canEdit else { return }
        if on, settings.needsConfirmation(columnId: column.id) {
            pendingConfirmation = column
            return
        }
        apply { $0.columnas[column.id] = on }
    }

    func confirmPending() {
        guard let column = pendingConfirmation else { return }
        pendingConfirmation = nil
        apply {
            $0.columnas[column.id] = true
            if !$0.confirmadas.contains(column.id) { $0.confirmadas.append(column.id) }
        }
    }

    func cancelPending() { pendingConfirmation = nil }

    private func apply(_ change: @escaping (inout WebPortalGroupGradeSettings) -> Void) {
        let classId = self.classId
        guard let saved = try? WebPortalGradeSettings.mutate(fileURL: settingsURL, { change(&$0[classId]) }) else { return }
        settings = saved[classId]
        changed(classId)
    }
}

// MARK: - Vista

struct WebPortalGradesPane: View {
    @ObservedObject var model: WebPortalGradesViewModel
    @ObservedObject var watcher: WebPortalGradesWatcher
    let classId: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.canEdit {
                // P5
                Label("Las notas se publican desde el Mac. Lo que evalúes aquí sube cuando llegue al Mac por la sincronización.", systemImage: "info.circle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            // P4
            if watcher.failedClassIds.contains(classId) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("No se pudo publicar. Se reintentará solo cuando vuelva la conexión.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reintentar") { watcher.retryNow(classId: classId) }
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.phase != .loaded {
                ProgressView().controlSize(.small)
            } else if model.columns.isEmpty {
                // P3
                ContentUnavailableView {
                    Label("Este grupo no tiene notas que contar", systemImage: "tablecells")
                } description: {
                    Text("Aquí salen las columnas del Cuaderno que cuentan en la media. Cuando tengas alguna, podrás elegir si se ven.")
                }
            } else {
                mediaRow
                Divider()
                columnsList
            }
        }
    }

    // P1 · «Mostrar la media»
    private var mediaRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mostrar la media").font(.body.weight(.semibold))
                Text("La misma media del Cuaderno, solo con lo que cuenta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switchView(
                label: "Mostrar la media al alumnado",
                isOn: Binding(get: { model.settings.media }, set: { model.setMedia($0) })
            )
        }
    }

    private var columnsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notas que cuentan en la media").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tipo").frame(width: 110, alignment: .leading)
                Text("Peso").frame(width: 50, alignment: .trailing)
                Text("Mostrar").frame(width: 90, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
            ForEach(model.columns) { column in
                Divider()
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(column.title).font(.body)
                        Text("\(column.typeLabel) · \(column.withGrade) de \(column.total) con nota")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(column.typeLabel).font(.body).frame(width: 110, alignment: .leading)
                    Text("\(column.weightPercent) %").font(.body).frame(width: 50, alignment: .trailing)
                    switchView(
                        label: "Mostrar \(column.title)",
                        isOn: Binding(get: { model.isOn(column) }, set: { model.requestColumn(column, on: $0) })
                    )
                    .frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// Interruptor con etiqueta real (para VoiceOver) y el «Sí / No» al lado.
    private func switchView(label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!model.canEdit)
            Text(isOn.wrappedValue ? "Sí" : "No")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
        }
    }
}

/// Pie de la pestaña: cuándo se publica y, tras un fallo, lo último que se publicó.
struct WebPortalGradesFooter: View {
    @ObservedObject var watcher: WebPortalGradesWatcher
    let classId: Int64

    var body: some View {
        Group {
            if watcher.failedClassIds.contains(classId) {
                if let last = watcher.lastPublished[classId] {
                    Text("Último publicado: \(last.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Aún no se ha publicado nada")
                }
            } else if let due = watcher.dueDates[classId] {
                Text("Los cambios se publican solos 10 minutos después · próxima publicación hacia las \(due.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Los cambios se publican solos 10 minutos después")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
