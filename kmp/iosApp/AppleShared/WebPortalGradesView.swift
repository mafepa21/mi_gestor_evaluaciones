import SwiftUI

/// Pestaña «Notas visibles» del portal del alumnado (maqueta fase 2, estados P1 a P5).
///
/// Solo el Mac cambia los interruptores (decisión 4.3 del ticket): en iPad se ven
/// desactivados con el aviso P5. No hay «Publicar ahora»: encender se publica solo 10 minutos
/// después del último cambio; apagar retira las notas al momento.

// MARK: - Modelo

@MainActor
final class WebPortalGradesViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded }

    @Published private(set) var overview: WebPortalGradeOverview?
    @Published private(set) var settings = WebPortalGroupGradeSettings()
    @Published private(set) var phase: Phase = .idle
    /// Columna que se acaba de encender por primera vez y espera confirmación (P2).
    @Published var pendingConfirmation: WebPortalGradeColumnRow?
    /// Primera activación de «Mostrar comentarios de celda» (maqueta 3C A2).
    @Published var pendingCommentsConfirmation = false
    /// Evaluación anterior que se acaba de encender por primera vez (maqueta 3D D1).
    @Published var pendingHistoricalTab: WebPortalGradeTab?
    /// Fallo al guardar los ajustes: se enseña en la hoja.
    @Published private(set) var saveError: String?

    let settingsURL: URL
    /// Solo el Mac edita.
    let canEdit: Bool
    private let loadOverview: (Int64, String?) async -> WebPortalGradeOverview?
    /// Pide a la app que ponga el grupo en la cola. `true`: retirar al momento (se apagó algo).
    private let changed: (Int64, Bool) -> Void
    private(set) var classId: Int64 = 0

    init(
        settingsURL: URL,
        canEdit: Bool = WebPortalGradesViewModel.platformCanEdit,
        loadOverview: @escaping (Int64, String?) async -> WebPortalGradeOverview?,
        changed: @escaping (Int64, Bool) -> Void
    ) {
        self.settingsURL = settingsURL
        self.canEdit = canEdit
        self.loadOverview = loadOverview
        self.changed = changed
    }

    nonisolated static var platformCanEdit: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    func load(classId: Int64) async {
        self.classId = classId
        pendingConfirmation = nil
        saveError = nil
        settings = WebPortalGradeSettings.load(fileURL: settingsURL)[classId]
        phase = .loading
        let loaded = await loadOverview(classId, settings.pestana)
        guard self.classId == classId else { return }
        overview = loaded
        phase = .loaded
    }

    var columns: [WebPortalGradeColumnRow] { overview?.columns ?? [] }

    func isOn(_ column: WebPortalGradeColumnRow) -> Bool { settings.isVisible(columnId: column.id) }

    /// La media solo se puede enseñar si todas las notas que entran en ella se muestran.
    var canShowMedia: Bool {
        guard let overview, !overview.hasHiddenCounting else { return false }
        return overview.columns.allSatisfy { isOn($0) }
    }

    /// Lo que se ve en el interruptor: encendido solo si de verdad se publica.
    var mediaIsOn: Bool { settings.media && canShowMedia }

    func setMedia(_ on: Bool) {
        guard canEdit, !on || canShowMedia else { return }
        apply(immediately: !on) { $0.media = on }
    }

    func requestComments(_ on: Bool) {
        guard canEdit else { return }
        if on, !settings.comentariosConfirmados {
            pendingCommentsConfirmation = true
            return
        }
        apply(immediately: !on) { $0.mostrarComentarios = on }
    }

    func confirmComments() {
        pendingCommentsConfirmation = false
        apply(immediately: false) {
            $0.mostrarComentarios = true
            $0.comentariosConfirmados = true
        }
    }

    func cancelComments() {
        pendingCommentsConfirmation = false
    }

    var otherTabs: [WebPortalGradeTab] {
        guard let overview else { return [] }
        let current = overview.tabId ?? settings.pestana
        return overview.tabs.filter { $0.id != current }
    }

    func isHistoricalOn(_ tab: WebPortalGradeTab) -> Bool {
        settings.isHistoricalTabVisible(tabId: tab.id)
    }

    func requestHistoricalTab(_ tab: WebPortalGradeTab, on: Bool) {
        guard canEdit else { return }
        if on, settings.needsHistoricalTabConfirmation(tabId: tab.id) {
            pendingHistoricalTab = tab
            return
        }
        apply(immediately: !on) {
            if on {
                if !$0.evaluacionesAnteriores.contains(tab.id) { $0.evaluacionesAnteriores.append(tab.id) }
            } else {
                $0.evaluacionesAnteriores.removeAll { $0 == tab.id }
            }
        }
    }

    func confirmHistoricalTab() {
        guard let tab = pendingHistoricalTab else { return }
        pendingHistoricalTab = nil
        apply(immediately: false) {
            if !$0.evaluacionesAnteriores.contains(tab.id) { $0.evaluacionesAnteriores.append(tab.id) }
            if !$0.evaluacionesConfirmadas.contains(tab.id) { $0.evaluacionesConfirmadas.append(tab.id) }
        }
    }

    func cancelHistoricalTab() {
        pendingHistoricalTab = nil
    }

    /// Pestaña de la que se publican media y notas.
    func setTab(_ tabId: String) {
        guard canEdit, tabId != (overview?.tabId ?? settings.pestana) else { return }
        apply(immediately: true) {
            $0.pestana = tabId
            $0.media = false
        }
        Task { await reloadOverview() }
    }

    private func reloadOverview() async {
        let classId = self.classId
        let loaded = await loadOverview(classId, settings.pestana)
        guard self.classId == classId else { return }
        overview = loaded
    }

    /// Apagar es inmediato y retira ya. Encender por primera vez pide confirmación (P2).
    func requestColumn(_ column: WebPortalGradeColumnRow, on: Bool) {
        guard canEdit else { return }
        if on, settings.needsConfirmation(columnId: column.id) {
            pendingConfirmation = column
            return
        }
        applyColumn(column.id, on: on)
    }

    func confirmPending() {
        guard let column = pendingConfirmation else { return }
        pendingConfirmation = nil
        applyColumn(column.id, on: true, confirm: true)
    }

    func cancelPending() { pendingConfirmation = nil }

    private func applyColumn(_ columnId: String, on: Bool, confirm: Bool = false) {
        let tab = overview?.tabId
        apply(immediately: !on) {
            $0.columnas[columnId] = on
            if confirm, !$0.confirmadas.contains(columnId) { $0.confirmadas.append(columnId) }
            // La pestaña publicada se fija al encender la primera columna.
            if on, $0.pestana == nil { $0.pestana = tab }
            // Sin todas las notas que cuentan, la media deja de publicarse sola.
            if !on { $0.media = false }
        }
    }

    private func apply(immediately: Bool, _ change: @escaping (inout WebPortalGroupGradeSettings) -> Void) {
        let classId = self.classId
        do {
            let saved = try WebPortalGradeSettings.mutate(fileURL: settingsURL) { change(&$0[classId]) }
            settings = saved[classId]
            saveError = nil
            changed(classId, immediately)
        } catch {
            saveError = "No se pudo guardar el ajuste: \(error.localizedDescription)"
        }
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
            if let error = model.saveError {
                banner(error, symbol: "exclamationmark.triangle.fill")
            }
            // Demasiado grande: reintentar no lo arregla.
            if watcher.tooLargeClassIds.contains(classId) {
                banner("Demasiado grande: el tablón de algún alumno pasa del límite y no se publica. Enseña menos notas.", symbol: "exclamationmark.octagon.fill")
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
                tabPicker
                mediaRow
                commentsRow
                Divider()
                columnsList
                if !model.otherTabs.isEmpty {
                    Divider().padding(.vertical, 4)
                    historicalTabsSection
                }
            }
        }
    }

    private func banner(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Pestaña del Cuaderno cuya media se publica (solo si hay más de una).
    @ViewBuilder
    private var tabPicker: some View {
        if let overview = model.overview, overview.tabs.count > 1 {
            HStack {
                Text("Pestaña").font(.body.weight(.semibold))
                Picker("Pestaña", selection: Binding(
                    get: { overview.tabId ?? overview.tabs[0].id },
                    set: { model.setTab($0) }
                )) {
                    ForEach(overview.tabs) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!model.canEdit)
                Spacer()
            }
        }
    }

    // P1 · «Mostrar la media»
    private var mediaRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mostrar la media").font(.body.weight(.semibold))
                if model.canShowMedia {
                    Text("La misma media del Cuaderno, solo con lo que cuenta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("La media incluye notas que no muestras")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            switchView(
                label: "Mostrar la media al alumnado",
                isOn: Binding(get: { model.mediaIsOn }, set: { model.setMedia($0) }),
                enabled: model.canShowMedia
            )
        }
    }

    // Fase 3C · A2 · «Mostrar comentarios de celda»
    private var commentsRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mostrar comentarios de celda").font(.body.weight(.semibold))
                Text("Muestra las observaciones escritas en columnas visibles como «Comentario del docente».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switchView(
                label: "Mostrar comentarios de celda al alumnado",
                isOn: Binding(get: { model.settings.mostrarComentarios }, set: { model.requestComments($0) }),
                enabled: true
            )
        }
    }

    // Fase 3D · D1 · «Histórico de evaluaciones anteriores»
    private var historicalTabsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HISTÓRICO DE EVALUACIONES ANTERIORES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.otherTabs) { tab in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.title).font(.body.weight(.semibold))
                        Text("Muestra su media final en el bloque «Evolución del curso».")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    switchView(
                        label: "Mostrar \(tab.title) en el histórico",
                        isOn: Binding(get: { model.isHistoricalOn(tab) }, set: { model.requestHistoricalTab(tab, on: $0) }),
                        enabled: true
                    )
                }
                .padding(.vertical, 4)
            }
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
                        if column.zeroCount > 0 {
                            Text("\(column.zeroCount) sin nota cuentan como 0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(column.typeLabel).font(.body).frame(width: 110, alignment: .leading)
                    Text("\(column.weightPercent) %").font(.body).frame(width: 50, alignment: .trailing)
                    switchView(
                        label: "Mostrar \(column.title)",
                        isOn: Binding(get: { model.isOn(column) }, set: { model.requestColumn(column, on: $0) }),
                        enabled: true
                    )
                    .frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// Interruptor con etiqueta real (para VoiceOver) y el «Sí / No» al lado.
    private func switchView(label: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!model.canEdit || !enabled)
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
