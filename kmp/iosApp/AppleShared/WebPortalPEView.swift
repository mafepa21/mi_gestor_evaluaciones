import SwiftUI

/// Pestaña «EF y seguimiento» del portal del alumnado (fase 3C, maqueta A1).
/// Solo el Mac edita los interruptores; en iPad se ven en solo lectura.
@MainActor
final class WebPortalPEViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded }

    enum PendingConfirmation: Identifiable, Equatable {
        case showTest(WebPortalPETestRow)
        case showAttendance

        var id: String {
            switch self {
            case .showTest(let row): return "test-\(row.id)"
            case .showAttendance: return "attendance"
            }
        }
    }

    @Published private(set) var overview: WebPortalPEOverview?
    @Published private(set) var settings = WebPortalGroupPESettings()
    @Published private(set) var phase: Phase = .idle
    @Published var pendingConfirmation: PendingConfirmation?
    @Published private(set) var saveError: String?

    let settingsURL: URL
    let canEdit: Bool
    private let loadOverview: (Int64) async -> WebPortalPEOverview?
    private let changed: (Int64, Bool) -> Void
    private(set) var classId: Int64 = 0

    init(
        settingsURL: URL,
        canEdit: Bool = WebPortalGradesViewModel.platformCanEdit,
        loadOverview: @escaping (Int64) async -> WebPortalPEOverview?,
        changed: @escaping (Int64, Bool) -> Void
    ) {
        self.settingsURL = settingsURL
        self.canEdit = canEdit
        self.loadOverview = loadOverview
        self.changed = changed
    }

    func load(classId: Int64) async {
        self.classId = classId
        pendingConfirmation = nil
        saveError = nil
        settings = WebPortalPESettings.load(fileURL: settingsURL)[classId]
        phase = .loading
        let loaded = await loadOverview(classId)
        guard self.classId == classId else { return }
        overview = loaded
        phase = .loaded
    }

    var tests: [WebPortalPETestRow] { overview?.tests ?? [] }

    func isTestOn(_ row: WebPortalPETestRow) -> Bool { settings.isTestVisible(testId: row.id) }

    func requestTest(_ row: WebPortalPETestRow, on: Bool) {
        guard canEdit else { return }
        if on, settings.needsTestConfirmation(testId: row.id) {
            pendingConfirmation = .showTest(row)
            return
        }
        apply(immediately: !on) {
            $0.pruebas[row.id] = on
        }
    }

    func requestAttendance(on: Bool) {
        guard canEdit else { return }
        if on, !settings.asistenciaConfirmada {
            pendingConfirmation = .showAttendance
            return
        }
        apply(immediately: !on) {
            $0.asistencia = on
        }
    }

    func confirmPending() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch pending {
        case .showTest(let row):
            apply(immediately: false) {
                $0.pruebas[row.id] = true
                if !$0.pruebasConfirmadas.contains(row.id) { $0.pruebasConfirmadas.append(row.id) }
            }
        case .showAttendance:
            apply(immediately: false) {
                $0.asistencia = true
                $0.asistenciaConfirmada = true
            }
        }
    }

    func cancelPending() { pendingConfirmation = nil }

    private func apply(immediately: Bool, _ change: @escaping (inout WebPortalGroupPESettings) -> Void) {
        let classId = self.classId
        do {
            let saved = try WebPortalPESettings.mutate(fileURL: settingsURL) { change(&$0[classId]) }
            settings = saved[classId]
            saveError = nil
            changed(classId, immediately)
        } catch {
            saveError = "No se pudo guardar el ajuste: \(error.localizedDescription)"
        }
    }
}

struct WebPortalPEPane: View {
    @ObservedObject var model: WebPortalPEViewModel
    @ObservedObject var watcher: WebPortalPEWatcher
    let classId: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.canEdit {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                    Text("Los interruptores de Educación Física y asistencia se cambian desde el Mac. Aquí puedes consultar qué está activo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }

            if let error = model.saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if model.phase == .loading && model.overview == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cargando pruebas físicas y asistencia…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else {
                Text("PRUEBAS FÍSICAS DEL GRUPO")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if model.tests.isEmpty {
                    Text("Este grupo todavía no tiene pruebas físicas asignadas.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.tests) { row in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).font(.callout.weight(.semibold))
                                    Text("\(row.capacityLabel) · \(row.recordedStudents) de \(row.totalStudents) con registro · \(row.assignmentCount) \(row.assignmentCount == 1 ? "toma" : "tomas")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { model.isTestOn(row) },
                                    set: { model.requestTest(row, on: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!model.canEdit)
                                .accessibilityLabel("Mostrar \(row.name)")
                            }
                            .padding(.vertical, 10)
                            if row.id != model.tests.last?.id { Divider() }
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                Text("ASISTENCIA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mostrar resumen de asistencia").font(.callout.weight(.semibold))
                        Text("Solo contadores y fechas de faltas, retrasos y equipación. Nunca tus notas privadas ni incidencias.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.asistencia },
                        set: { model.requestAttendance(on: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.canEdit)
                    .accessibilityLabel("Mostrar resumen de asistencia")
                }
                .padding(.vertical, 6)
            }
        }
    }
}

struct WebPortalPEFooter: View {
    @ObservedObject var watcher: WebPortalPEWatcher
    let classId: Int64

    var body: some View {
        HStack {
            if watcher.failedClassIds.contains(classId) {
                Label("No se pudo publicar el último cambio.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Reintentar") { watcher.retryNow(classId: classId) }
                    .font(.footnote)
            } else if let due = watcher.dueDates[classId] {
                Text("Se publicará \(due.formatted(.relative(presentation: .named))) · Apagar retira al momento")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let last = watcher.lastPublished[classId] {
                Text("Última publicación \(last.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Los cambios se publican solos 10 minutos después · Apagar retira al momento")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
