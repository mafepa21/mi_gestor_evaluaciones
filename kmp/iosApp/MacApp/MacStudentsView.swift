import SwiftUI
import AppKit
import MiGestorKit
import UniformTypeIdentifiers

enum MacStudentsPresentation {
    case content
    case inspector
}

@MainActor
final class MacStudentsStore: ObservableObject {
    @Published var rows: [KmpBridge.MacStudentRowSnapshot] = []
    @Published var profile: KmpBridge.StudentProfileSnapshot?
    @Published var localSelectedStudentId: Int64?
    @Published var searchText = ""
    @Published var trackingFilter = "todos"
    @Published var workGroupFilter = "Todos"
    @Published var quickNoteText = ""
    @Published var isLoadingRows = false
    @Published var isLoadingProfile = false
    @Published var isSavingNote = false
    @Published var errorMessage: String?
    @Published var profileErrorMessage: String?
    @Published var riskPack: TeachingEvidencePack?
    @Published var didBootstrap = false
    @Published var isBootstrapping = false
    var profileLoadTask: Task<Void, Never>?
    @Published var profileLoadingStudentId: Int64?
    @Published var studentEditorMode: MacStudentEditorMode?
    deinit {
        profileLoadTask?.cancel()
    }
    @Published var supportMeasures: [SupportMeasureRow] = []
    @Published var tutoringSessions: [TutoringSessionRow] = []
}

struct MacStudentsView: View {
    let bridge: KmpBridge
    @ObservedObject var studentsBridgeStore: StudentsBridgeStore
    @ObservedObject var store: MacStudentsStore
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    var presentation: MacStudentsPresentation = .content
    var reloadToken: Int = 0

    @State private var showingStudentFileImporter = false
    @State private var showSupportMeasureSheet = false
    @State private var showTutoringSheet = false
    @State private var editingTutoringSession: TutoringSessionRow?
    @State private var pendingDeleteTutoringSession: TutoringSessionRow?
    @State private var editingSupportMeasure: SupportMeasureRow?
    @State private var pendingDeleteSupportMeasure: SupportMeasureRow?
    @State private var showBulkImportSheet = false
    @State private var showGroupOverviewSheet = false
    @State private var showSexInferenceSheet = false
    @State private var studentImportPreview: AppleStudentImportPreview?
    @State private var importErrorMessage: String?
    @FocusState private var isSearchFocused: Bool

    private var filteredRows: [KmpBridge.MacStudentRowSnapshot] {
        let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.rows.filter { row in
            let matchesQuery = query.isEmpty ||
                row.student.fullName.localizedCaseInsensitiveContains(query) ||
                row.className.localizedCaseInsensitiveContains(query)
            let matchesTracking: Bool = {
                switch store.trackingFilter {
                case "seguimiento":
                    return row.isFollowUp
                case "lesionados":
                    return row.isInjured
                default:
                    return true
                }
            }()
            let matchesGroup = store.workGroupFilter == "Todos" || row.workGroupName == store.workGroupFilter
            return matchesQuery && matchesTracking && matchesGroup
        }
    }

    private var selectedRow: KmpBridge.MacStudentRowSnapshot? {
        guard let selectedStudentId = store.localSelectedStudentId else { return filteredRows.first }
        return store.rows.first(where: { $0.id == selectedStudentId }) ?? filteredRows.first
    }

    private var workGroupOptions: [String] {
        ["Todos"] + Array(Set(store.rows.map(\.workGroupName))).sorted()
    }

    private var selectedRowClassId: Int64? {
        selectedClassId ?? selectedRow?.classId
    }

    private var canSaveQuickNote: Bool {
        selectedRowClassId != nil && !store.quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isSavingNote
    }

    private var ownsStudentSideEffects: Bool {
        presentation != .inspector
    }

    var body: some View {
        Group {
            switch presentation {
            case .content:
                HStack(spacing: 0) {
                    studentsFilters
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
                    Divider()
                    studentsList
                        .frame(minWidth: 360, maxWidth: .infinity)
                }
            case .inspector:
                studentInspector
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430, maxHeight: .infinity)
            }
        }
        .background(MacAppStyle.pageBackground)
        .task {
            guard ownsStudentSideEffects else { return }
            await bootstrapStudents()
        }
        .task(id: reloadToken) {
            guard ownsStudentSideEffects else { return }
            guard reloadToken > 0 else { return }
            await reloadRows()
        }
        .appOnChange(of: selectedClassId) { _, newClassId in
            guard ownsStudentSideEffects else { return }
            guard store.didBootstrap else { return }
            Task {
                await bridge.selectStudentsClass(classId: newClassId)
                await reloadRows()
            }
        }
        .appOnChange(of: store.localSelectedStudentId) { _, newValue in
            guard ownsStudentSideEffects else { return }
            if selectedStudentId != newValue {
                selectedStudentId = newValue
            }
            loadProfileForSelection(newValue)
        }
        .appOnChange(of: selectedStudentId) { _, newValue in
            guard ownsStudentSideEffects else { return }
            guard store.didBootstrap else { return }
            guard let newValue else {
                store.localSelectedStudentId = nil
                loadProfileForSelection(nil)
                return
            }
            guard store.rows.contains(where: { $0.id == newValue }) else { return }
            if store.localSelectedStudentId != newValue {
                store.localSelectedStudentId = newValue
            } else {
                loadProfileForSelection(newValue)
            }
        }
        .appOnChange(of: filteredRows.map(\.id)) { _, visibleIds in
            guard ownsStudentSideEffects else { return }
            guard !visibleIds.isEmpty else {
                store.localSelectedStudentId = nil
                store.profileLoadTask?.cancel()
                store.isLoadingProfile = false
                store.profileLoadingStudentId = nil
                store.profile = nil
                store.riskPack = nil
                store.profileErrorMessage = nil
                return
            }
            if let selectedStudentId = store.localSelectedStudentId {
                guard visibleIds.contains(selectedStudentId) else {
                    store.localSelectedStudentId = visibleIds.first
                    return
                }
            } else {
                store.localSelectedStudentId = visibleIds.first
            }
        }
        .appOnChange(of: studentsBridgeStore.allStudents.map { "\($0.id):\($0.isInjured)" }.joined(separator: "|")) { _, _ in
            guard ownsStudentSideEffects, store.didBootstrap else { return }
            Task { await reloadRows(preferredStudentId: store.localSelectedStudentId, showsLoading: false) }
        }
        .onExitCommand {
            guard ownsStudentSideEffects else { return }
            if !store.searchText.isEmpty {
                store.searchText = ""
            }
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)

            Button("") {
                openSelectedInNotebook()
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
        }
        .onDisappear(perform: cancelProfileLoadOnDisappear)
        .sheet(item: studentEditorModeBinding) { mode in
            MacStudentEditorSheet(mode: mode) { draft in
                Task { await saveStudentDraft(draft, mode: mode) }
            }
        }
        .sheet(isPresented: $showTutoringSheet) {
            if let studentId = store.localSelectedStudentId ?? selectedRow?.id {
                TutoringSessionFormSheet(studentId: studentId) {
                    loadProfileForSelection(studentId)
                }
                .environmentObject(bridge)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { editingTutoringSession != nil },
                set: setEditingTutoringPresented
            )
        ) {
            if let studentId = store.localSelectedStudentId ?? selectedRow?.id, let editingTutoringSession {
                TutoringSessionFormSheet(studentId: studentId, existingSession: editingTutoringSession) {
                    loadProfileForSelection(studentId)
                }
                .environmentObject(bridge)
            }
        }
        .alert(
            "¿Borrar esta tutoría?",
            isPresented: Binding(
                get: { pendingDeleteTutoringSession != nil },
                set: setPendingDeleteTutoringPresented
            )
        ) {
            Button("Cancelar", role: .cancel) { pendingDeleteTutoringSession = nil }
            Button("Borrar", role: .destructive) {
                if let session = pendingDeleteTutoringSession {
                    Task {
                        try? await bridge.deleteTutoringSession(id: session.id)
                        loadProfileForSelection(session.studentId)
                    }
                }
                pendingDeleteTutoringSession = nil
            }
        } message: {
            Text("El acta de la entrevista se elimina de forma permanente.")
        }
        .sheet(isPresented: $showSupportMeasureSheet) {
            if let studentId = store.localSelectedStudentId ?? selectedRow?.id {
                SupportMeasureFormSheet(studentId: studentId) {
                    loadProfileForSelection(studentId)
                }
                .environmentObject(bridge)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { editingSupportMeasure != nil },
                set: setEditingSupportMeasurePresented
            )
        ) {
            if let studentId = store.localSelectedStudentId ?? selectedRow?.id, let editingSupportMeasure {
                SupportMeasureFormSheet(studentId: studentId, existingMeasure: editingSupportMeasure) {
                    loadProfileForSelection(studentId)
                }
                .environmentObject(bridge)
            }
        }
        .sheet(isPresented: $showBulkImportSheet) {
            if let selectedClassId {
                SupportMeasureBulkImportSheet(
                    classId: selectedClassId,
                    roster: studentsBridgeStore.studentsInClass
                ) {
                    loadProfileForSelection(store.localSelectedStudentId ?? selectedRow?.id)
                }
                .environmentObject(bridge)
            }
        }
        .sheet(isPresented: $showGroupOverviewSheet) {
            SupportMeasureGroupOverviewSheet(
                className: studentsBridgeStore.classes.first(where: { $0.id == selectedClassId })?.name ?? "",
                roster: studentsBridgeStore.studentsInClass
            )
            .environmentObject(bridge)
        }
        .sheet(isPresented: $showSexInferenceSheet) {
            StudentSexInferenceSheet(students: studentsBridgeStore.studentsInClass) { assignments in
                Task { await applyStudentSexInference(assignments) }
            }
        }
        .confirmationDialog(
            "Eliminar medida de apoyo",
            isPresented: Binding(
                get: { pendingDeleteSupportMeasure != nil },
                set: setPendingDeleteSupportMeasurePresented
            ),
            presenting: pendingDeleteSupportMeasure
        ) { measure in
            Button("Eliminar \(measure.level.displayName) · \(measure.measureType.displayName)", role: .destructive) {
                Task { await deleteSupportMeasure(measure) }
            }
            Button("Cancelar", role: .cancel) {
                pendingDeleteSupportMeasure = nil
            }
        } message: { _ in
            Text("Se eliminará este registro por completo. Si solo quieres cerrarla, usa \"Retirar\".")
        }
        .fileImporter(
            isPresented: $showingStudentFileImporter,
            allowedContentTypes: [.xlsx, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleStudentImportFile(result) }
        }
        .sheet(item: $studentImportPreview) { preview in
            StudentImportSheet(preview: preview)
                .environmentObject(bridge)
                .frame(minWidth: 720, minHeight: 620)
                .onDisappear(perform: reloadRowsAfterStudentImportPreview)
        }
        .alert("No se pudo importar alumnado", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: setImportErrorPresented
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var studentEditorModeBinding: Binding<MacStudentEditorMode?> {
        Binding(
            get: { ownsStudentSideEffects ? store.studentEditorMode : nil },
            set: { newValue in
                guard ownsStudentSideEffects else { return }
                store.studentEditorMode = newValue
            }
        )
    }

    private func cancelProfileLoadOnDisappear() {
        guard ownsStudentSideEffects else { return }
        store.profileLoadTask?.cancel()
    }

    private func reloadRowsAfterStudentImportPreview() {
        Task { await reloadRows() }
    }

    private func setEditingTutoringPresented(_ isPresented: Bool) {
        if !isPresented { editingTutoringSession = nil }
    }

    private func setPendingDeleteTutoringPresented(_ isPresented: Bool) {
        if !isPresented { pendingDeleteTutoringSession = nil }
    }

    private func setEditingSupportMeasurePresented(_ isPresented: Bool) {
        if !isPresented { editingSupportMeasure = nil }
    }

    private func setPendingDeleteSupportMeasurePresented(_ isPresented: Bool) {
        if !isPresented { pendingDeleteSupportMeasure = nil }
    }

    private func setImportErrorPresented(_ isPresented: Bool) {
        if !isPresented { importErrorMessage = nil }
    }

    private var studentsList: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            studentsHeader
            studentsTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var studentsFilters: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Filtros")
                    .font(.title3.weight(.semibold))
                Text("\(filteredRows.count) de \(store.rows.count) alumnos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Clase", selection: $selectedClassId) {
                    Text("Todas").tag(Optional<Int64>.none)
                    ForEach(studentsBridgeStore.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Búsqueda")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nombre o clase", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Seguimiento")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Seguimiento", selection: $store.trackingFilter) {
                    Text("Todos").tag("todos")
                    Text("Seguimiento").tag("seguimiento")
                    Text("Lesionados").tag("lesionados")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Grupo de trabajo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Grupo de trabajo", selection: $store.workGroupFilter) {
                    ForEach(workGroupOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Spacer()

            if let errorMessage = store.errorMessage {
                MacPremiumOperationState(kind: .failed(errorMessage))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MacAppStyle.pagePadding)
        .background(MacAppStyle.cardBackground)
    }

    private var studentsHeader: some View {
        MacPremiumModuleHeader(
            title: "Alumnado",
            subtitle: "Seguimiento, asistencia, media e incidencias.",
            state: studentsOperationState,
            primaryAction: MacPremiumHeaderAction(
                title: "Nuevo alumno",
                systemImage: "plus",
                isDisabled: selectedRowClassId == nil
            ) {
                guard let classId = selectedRowClassId else { return }
                store.studentEditorMode = .create(classId: classId)
            },
            secondaryActions: [
                MacPremiumHeaderAction(
                    title: "Importar medidas Nivel III",
                    systemImage: "tablecells.badge.ellipsis",
                    isDisabled: selectedClassId == nil
                ) {
                    showBulkImportSheet = true
                },
                MacPremiumHeaderAction(
                    title: "Ver medidas del grupo",
                    systemImage: "list.bullet.clipboard",
                    isDisabled: selectedClassId == nil
                ) {
                    showGroupOverviewSheet = true
                },
                MacPremiumHeaderAction(
                    title: "Sugerir sexo por nombre",
                    systemImage: "person.2.badge.gearshape",
                    isDisabled: selectedClassId == nil
                ) {
                    showSexInferenceSheet = true
                },
                MacPremiumHeaderAction(title: "Importar Excel", systemImage: "square.and.arrow.down") {
                    showingStudentFileImporter = true
                },
                MacPremiumHeaderAction(title: "Recargar", systemImage: "arrow.clockwise") {
                    Task { await reloadRows() }
                }
            ]
        )
    }

    private var studentsOperationState: MacPremiumOperationStateKind? {
        if let errorMessage = store.errorMessage {
            return .failed(errorMessage)
        }
        if store.isLoadingRows {
            return .loading("Actualizando...")
        }
        return nil
    }

    @ViewBuilder
    private var studentsTable: some View {
        MacPremiumTableContainer(
            title: "Listado de alumnado",
            subtitle: selectedClassId == nil ? "Todas las clases visibles" : "Clase seleccionada",
            count: filteredRows.count,
            isLoading: store.isLoadingRows
        ) {
            studentsTableContent
        }
    }

    @ViewBuilder
    private var studentsTableContent: some View {
        if store.rows.isEmpty && !store.isLoadingRows {
            ContentUnavailableView(
                "Sin alumnado",
                systemImage: "person.3",
                description: Text("No hay alumnos disponibles para la clase seleccionada.")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if filteredRows.isEmpty {
            ContentUnavailableView(
                "Sin coincidencias",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Ajusta la búsqueda o los filtros de seguimiento.")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            Table(filteredRows, selection: $store.localSelectedStudentId) {
                TableColumn("Nombre") { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 6) {
                            Text(row.workGroupName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if row.isInjured {
                                MacStatusPill(label: "Lesión", isActive: true, tint: MacAppStyle.warningTint)
                            }
                        }
                        if row.student.email?.isEmpty == false {
                            Text(row.student.email ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Clase") { row in
                    Text(row.className)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Seguimiento") { row in
                    MacStatusPill(
                        label: row.followUpLabel,
                        isActive: row.isFollowUp,
                        tint: row.isInjured ? MacAppStyle.warningTint : (row.isFollowUp ? MacAppStyle.infoTint : MacAppStyle.successTint)
                    )
                }
                .width(min: 112, ideal: 130)
                TableColumn("Asistencia reciente") { row in
                    Text(row.recentAttendanceLabel)
                        .font(.system(size: 12, weight: .medium))
                }
                .width(min: 130, ideal: 150)
                TableColumn("Media") { row in
                    Text(row.averageText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 82)
                TableColumn("Incidencias") { row in
                    Text("\(row.incidentCount)")
                        .font(.system(size: 12, weight: row.incidentCount > 0 ? .bold : .regular))
                        .foregroundStyle(row.incidentCount > 0 ? .red : .secondary)
                        .monospacedDigit()
                }
                .width(min: 82, ideal: 96)
                TableColumn("Última observación") { row in
                    Text(row.lastObservationText)
                        .font(.system(size: 12))
                        .foregroundStyle(row.lastObservationText == "Sin observaciones" ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private var studentInspector: some View {
        if let selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MacPremiumInspectorHeader(
                        title: selectedRow.student.fullName,
                        subtitle: "\(selectedRow.className) · Ficha del alumno"
                    ) {
                        HStack(spacing: 8) {
                            MacStatusPill(
                                label: selectedRow.followUpLabel,
                                isActive: selectedRow.isFollowUp,
                                tint: selectedRow.isInjured ? MacAppStyle.warningTint : MacAppStyle.infoTint
                            )
                            MacStatusPill(
                                label: selectedRow.workGroupName,
                                isActive: selectedRow.workGroupName != "Sin grupo",
                                tint: MacAppStyle.successTint
                            )
                        }
                    }

                    inspectorSection("Datos del alumno") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let email = selectedRow.student.email, !email.isEmpty {
                                Label(email, systemImage: "envelope")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                store.studentEditorMode = .edit(row: selectedRow)
                            } label: {
                                Label("Editar datos", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)

                        }
                    }

                    inspectorSection("Condición física") {
                        VStack(alignment: .leading, spacing: 10) {
                            MacStatusPill(
                                label: selectedRow.isInjured ? "Lesión activa" : "Sin lesión",
                                isActive: selectedRow.isInjured,
                                tint: selectedRow.isInjured ? MacAppStyle.warningTint : MacAppStyle.successTint
                            )
                            injuryToggleButton(for: selectedRow)
                        }
                    }

                    if store.profileLoadingStudentId == selectedRow.id {
                        inspectorMetricsSkeleton
                    } else if let profile = store.profile, profile.student.id == selectedRow.id {
                        MacPremiumInspectorMetricGrid {
                            MacMetricCard(label: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                            MacMetricCard(label: "Media", value: IosFormatting.decimal(profile.averageScore), systemImage: "sum")
                            MacMetricCard(label: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble")
                            MacMetricCard(label: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                        }
                    } else if let profileErrorMessage = store.profileErrorMessage {
                        ContentUnavailableView(
                            "No se pudo cargar la ficha",
                            systemImage: "exclamationmark.triangle",
                            description: Text(profileErrorMessage)
                        )
                    } else {
                        inspectorMetricsSkeleton
                    }

                    if let profile = store.profile, profile.student.id == selectedRow.id {
                        if let riskPack = store.riskPack, let level = riskPack.riskLevel {
                            inspectorSection("Radar de riesgo") {
                                VStack(alignment: .leading, spacing: 10) {
                                    MacStatusPill(
                                        label: level.title,
                                        isActive: level != .seguimientoNormal,
                                        tint: level == .atencionPrioritaria ? MacAppStyle.dangerTint : (level == .atencionPuntual ? MacAppStyle.warningTint : MacAppStyle.successTint)
                                    )
                                    Text(riskPack.summary)
                                        .font(.system(size: 13, weight: .medium))
                                    ForEach(Array(riskPack.warningTexts.prefix(3)), id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(riskPack.recommendedActionTexts.prefix(2)), id: \.self) { action in
                                        Label(action, systemImage: "arrowshape.right.circle")
                                            .font(.caption)
                                    }
                                }
                            }
                        }

                        inspectorSection("Notas rápidas") {
                            if selectedRowClassId == nil {
                                Text("Selecciona una clase para guardar notas rápidas.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                TextEditor(text: $store.quickNoteText)
                                    .frame(minHeight: 86)
                                    .font(.system(size: 13))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                HStack {
                                    Button {
                                        Task { await saveQuickNote() }
                                    } label: {
                                        Label(store.isSavingNote ? "Guardando…" : "Guardar nota", systemImage: "square.and.arrow.down")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!canSaveQuickNote)
                                    Spacer()
                                }
                            }
                        }

                        inspectorSection("Historial de incidencias") {
                            if profile.incidents.isEmpty {
                                Text("Sin incidencias registradas.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(profile.incidents.prefix(5), id: \.id) { incident in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(incident.title)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(incident.severity.capitalized)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(incident.detail ?? "Sin detalle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }

                        inspectorSection("Medidas de apoyo") {
                            VStack(alignment: .leading, spacing: 10) {
                                if store.supportMeasures.isEmpty {
                                    Text("Sin medidas registradas.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(store.supportMeasures) { measure in
                                        macSupportMeasureRow(measure)
                                    }
                                }
                                Button {
                                    showSupportMeasureSheet = true
                                } label: {
                                    Label("Añadir medida", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        inspectorSection("Tutorías con familias") {
                            VStack(alignment: .leading, spacing: 10) {
                                if store.tutoringSessions.isEmpty {
                                    Text("Sin entrevistas registradas.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(store.tutoringSessions) { session in
                                        macTutoringSessionRow(session)
                                    }
                                }
                                Button {
                                    showTutoringSheet = true
                                } label: {
                                    Label("Registrar tutoría", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        inspectorSection("Accesos") {
                            MacPremiumInspectorActionGroup {
                                Button {
                                    openSelectedInNotebook()
                                } label: {
                                    Label("Abrir en cuaderno", systemImage: "tablecells")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    openSelected(.attendance)
                                } label: {
                                    Label("Abrir asistencia", systemImage: "checklist.checked")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    openSelected(.reports)
                                } label: {
                                    Label("Abrir informes", systemImage: "doc.text")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        EmptyView()
                    }
                }
                .padding(MacAppStyle.pagePadding)
            }
            .background(MacAppStyle.cardBackground)
        } else {
            VStack {
                ContentUnavailableView(
                    "Selecciona un alumno",
                    systemImage: "person.3",
                    description: Text("La ficha reunirá notas, incidencias y accesos cruzados.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(MacAppStyle.cardBackground)
        }
    }

    private func macTutoringSessionRow(_ session: TutoringSessionRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: session.channel.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.dateDisplay)
                        .font(.subheadline.weight(.semibold))
                    if session.isClosed {
                        Text("Cerrada")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                if !session.attendees.isEmpty {
                    Text(session.attendees)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !session.agreements.isEmpty {
                    Text(session.agreements)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                switch session.reviewStatus {
                case .overdue:
                    Text("Revisión vencida\(session.reviewDueDisplay.map { " · \($0)" } ?? "")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MacAppStyle.dangerTint)
                case .dueSoon:
                    Text("Revisión próxima\(session.reviewDueDisplay.map { " · \($0)" } ?? "")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MacAppStyle.warningTint)
                case .none:
                    EmptyView()
                }
            }
            Spacer()
            Button("Editar") {
                editingTutoringSession = session
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                pendingDeleteTutoringSession = session
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func macSupportMeasureRow(_ measure: SupportMeasureRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(measure.level.displayName) · \(measure.measureType.displayName)")
                        .font(.subheadline.weight(.semibold))
                    if !measure.isActive {
                        Text("Retirada")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let responsible = measure.responsible, !responsible.isEmpty {
                    Text(responsible)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                switch measure.reviewStatus {
                case .overdue:
                    Text("Revisión vencida")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MacAppStyle.dangerTint)
                case .dueSoon:
                    Text("Revisión próxima")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MacAppStyle.warningTint)
                case .none:
                    EmptyView()
                }
            }
            Spacer()
            if measure.isActive {
                Button("Editar") {
                    editingSupportMeasure = measure
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderless)

                Button("Retirar") {
                    Task { await retireSupportMeasure(measure) }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if measure.isActive {
                Button {
                    editingSupportMeasure = measure
                } label: {
                    Label("Editar medida", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                pendingDeleteSupportMeasure = measure
            } label: {
                Label("Eliminar medida", systemImage: "trash")
            }
        }
    }

    @MainActor
    private func retireSupportMeasure(_ measure: SupportMeasureRow) async {
        do {
            try await bridge.retireSupportMeasure(
                id: measure.id,
                endDateIso: AppDateTimeSupport.isoDateFormatter.string(from: Date())
            )
            loadProfileForSelection(measure.studentId)
        } catch {
            store.profileErrorMessage = "No se pudo retirar la medida: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteSupportMeasure(_ measure: SupportMeasureRow) async {
        pendingDeleteSupportMeasure = nil
        do {
            try await bridge.deleteSupportMeasure(id: measure.id)
            loadProfileForSelection(measure.studentId)
        } catch {
            store.profileErrorMessage = "No se pudo eliminar la medida: \(error.localizedDescription)"
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        MacPremiumInspectorSection(title: title) {
            content()
        }
    }

    private var inspectorMetricsSkeleton: some View {
        MacPremiumInspectorMetricGrid {
            ForEach(["Asistencia", "Media", "Incidencias", "Evidencias"], id: \.self) { label in
                VStack(alignment: .leading, spacing: 8) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MacAppStyle.subtleFill)
                        .frame(height: 18)
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private func injuryToggleButton(for row: KmpBridge.MacStudentRowSnapshot) -> some View {
        if row.isInjured {
            Button {
                Task { await toggleSelectedStudentInjury(row) }
            } label: {
                Label("Quitar lesión", systemImage: "heart.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                Task { await toggleSelectedStudentInjury(row) }
            } label: {
                Label("Marcar lesión", systemImage: "bandage")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func bootstrapStudents() async {
        guard !store.didBootstrap, !store.isBootstrapping else { return }
        store.isBootstrapping = true
        defer { store.isBootstrapping = false }
        if selectedClassId == nil {
            selectedClassId = studentsBridgeStore.selectedStudentsClassId
        }
        await bridge.selectStudentsClass(classId: selectedClassId)
        await reloadRows(preferredStudentId: selectedStudentId)
        store.didBootstrap = true
    }

    @MainActor
    private func reloadRows(preferredStudentId: Int64? = nil, showsLoading: Bool = true) async {
        if showsLoading {
            store.isLoadingRows = true
        }
        store.errorMessage = nil
        defer {
            if showsLoading {
                store.isLoadingRows = false
            }
        }
        do {
            store.rows = try await bridge.loadMacStudentRows(classId: selectedClassId)
            let visibleIds = filteredRows.map(\.id)
            if let preferredStudentId, visibleIds.contains(preferredStudentId) {
                store.localSelectedStudentId = preferredStudentId
            } else if let currentStudentId = store.localSelectedStudentId, visibleIds.contains(currentStudentId) {
                store.localSelectedStudentId = currentStudentId
            } else {
                store.localSelectedStudentId = visibleIds.first
            }
            selectedStudentId = store.localSelectedStudentId
            loadProfileForSelection(store.localSelectedStudentId)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyStudentSexInference(_ assignments: [StudentSexInferenceAssignment]) async {
        guard !assignments.isEmpty else { return }
        store.isLoadingRows = true
        store.errorMessage = nil
        defer { store.isLoadingRows = false }

        do {
            try await bridge.applyStudentSexInference(assignments)
            await bridge.selectStudentsClass(classId: selectedClassId)
            await reloadRows(preferredStudentId: store.localSelectedStudentId, showsLoading: false)
        } catch {
            store.errorMessage = "No se pudo aplicar la sugerencia: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func handleStudentImportFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            studentImportPreview = try await bridge.previewStudentImport(tsv: rows.tsvText)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadProfileForSelection(_ studentId: Int64?) {
        store.profileLoadTask?.cancel()
        store.profileErrorMessage = nil
        guard let studentId else {
            store.isLoadingProfile = false
            store.profileLoadingStudentId = nil
            store.profile = nil
            store.riskPack = nil
            store.profileErrorMessage = nil
            store.supportMeasures = []
            store.tutoringSessions = []
            return
        }

        let requestedClassId = selectedClassId ?? store.rows.first(where: { $0.id == studentId })?.classId
        store.profile = nil
        store.riskPack = nil
        store.isLoadingProfile = true
        store.profileLoadingStudentId = studentId

        store.profileLoadTask = Task {
            do {
                async let loadedProfile = bridge.loadStudentProfile(studentId: studentId, classId: requestedClassId)
                async let loadedRiskPack = StudentRiskEvidenceBuilder.build(bridge: bridge, classId: requestedClassId, studentId: studentId)
                async let loadedSupportMeasures = bridge.supportMeasures(for: studentId)
                async let loadedTutoringSessions = bridge.tutoringSessions(for: studentId)
                let resultProfile = try await loadedProfile
                let resultRiskPack = try? await loadedRiskPack
                let resultSupportMeasures = (try? await loadedSupportMeasures)?.map(\.asRow) ?? []
                let resultTutoringSessions = (try? await loadedTutoringSessions)?.map(\.asRow) ?? []
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard store.localSelectedStudentId == studentId,
                          selectedStudentId == studentId,
                          (selectedClassId ?? store.rows.first(where: { $0.id == studentId })?.classId) == requestedClassId else { return }
                    store.profile = resultProfile
                    store.riskPack = resultRiskPack
                    store.supportMeasures = resultSupportMeasures
                    store.tutoringSessions = resultTutoringSessions
                    store.profileLoadingStudentId = nil
                    store.isLoadingProfile = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard store.localSelectedStudentId == studentId,
                          selectedStudentId == studentId,
                          (selectedClassId ?? store.rows.first(where: { $0.id == studentId })?.classId) == requestedClassId else { return }
                    store.profile = nil
                    store.riskPack = nil
                    store.profileLoadingStudentId = nil
                    store.profileErrorMessage = error.localizedDescription
                    store.isLoadingProfile = false
                }
            }
        }
    }

    @MainActor
    private func applyInjuryLocally(studentId: Int64, isInjured: Bool) {
        store.rows = store.rows.map { row in
            guard row.id == studentId else { return row }
            let followUpLabel: String
            if isInjured {
                followUpLabel = "Lesión"
            } else if row.incidentCount > 0 {
                followUpLabel = "Incidencias"
            } else {
                followUpLabel = "Normal"
            }

            return KmpBridge.MacStudentRowSnapshot(
                id: row.id,
                student: row.student,
                classId: row.classId,
                className: row.className,
                allClassMemberships: row.allClassMemberships,
                followUpLabel: followUpLabel,
                recentAttendanceLabel: row.recentAttendanceLabel,
                averageText: row.averageText,
                incidentCount: row.incidentCount,
                lastObservationText: row.lastObservationText,
                isInjured: isInjured,
                isFollowUp: isInjured || row.incidentCount > 0,
                workGroupName: row.workGroupName
            )
        }
    }

    @MainActor
    private func toggleSelectedStudentInjury(_ row: KmpBridge.MacStudentRowSnapshot) async {
        let previousValue = row.isInjured
        let newValue = !previousValue
        selectedStudentId = row.id
        store.localSelectedStudentId = row.id
        applyInjuryLocally(studentId: row.id, isInjured: newValue)

        do {
            try await bridge.updateStudentInjuryStatus(
                studentId: row.id,
                isInjured: newValue,
                classId: selectedClassId ?? row.classId
            )
            loadProfileForSelection(row.id)
        } catch {
            applyInjuryLocally(studentId: row.id, isInjured: previousValue)
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveQuickNote() async {
        guard let studentId = store.localSelectedStudentId, let classId = selectedRowClassId else { return }
        let note = store.quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.isSavingNote = true
        defer { store.isSavingNote = false }
        do {
            try await bridge.saveQuickStudentNote(studentId: studentId, classId: classId, note: note)
            applyQuickNoteLocally(studentId: studentId, note: note)
            store.quickNoteText = ""
            await reloadRows(preferredStudentId: studentId, showsLoading: false)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyQuickNoteLocally(studentId: Int64, note: String) {
        store.rows = store.rows.map { row in
            guard row.id == studentId else { return row }
            return KmpBridge.MacStudentRowSnapshot(
                id: row.id,
                student: row.student,
                classId: row.classId,
                className: row.className,
                allClassMemberships: row.allClassMemberships,
                followUpLabel: row.followUpLabel,
                recentAttendanceLabel: row.recentAttendanceLabel,
                averageText: row.averageText,
                incidentCount: row.incidentCount,
                lastObservationText: note,
                isInjured: row.isInjured,
                isFollowUp: row.isFollowUp,
                workGroupName: row.workGroupName
            )
        }
    }

    private func openSelectedInNotebook() {
        openSelected(.notebook)
    }

    private func openSelected(_ module: AppWorkspaceModule) {
        guard let studentId = store.localSelectedStudentId else { return }
        selectedStudentId = studentId
        onOpenModule(module, selectedRowClassId, studentId)
    }

    @MainActor
    private func saveStudentDraft(_ draft: MacStudentDraft, mode: MacStudentEditorMode) async {
        store.errorMessage = nil
        do {
            switch mode {
            case .create(let classId):
                let studentId = try await bridge.createMacStudent(
                    firstName: draft.firstName,
                    lastName: draft.lastName,
                    email: draft.email,
                    isInjured: draft.isInjured,
                    classId: classId
                )
                store.studentEditorMode = nil
                await reloadRows(preferredStudentId: studentId)
            case .edit(let row):
                try await bridge.updateMacStudent(
                    student: row.student,
                    firstName: draft.firstName,
                    lastName: draft.lastName,
                    email: draft.email,
                    isInjured: draft.isInjured
                )
                store.studentEditorMode = nil
                await reloadRows(preferredStudentId: row.id)
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

enum MacStudentEditorMode: Identifiable {
    case create(classId: Int64)
    case edit(row: KmpBridge.MacStudentRowSnapshot)

    var id: String {
        switch self {
        case .create(let classId):
            return "create-\(classId)"
        case .edit(let row):
            return "edit-\(row.id)"
        }
    }
}

private struct MacStudentDraft {
    var firstName: String
    var lastName: String
    var email: String
    var isInjured: Bool
}

private struct MacStudentEditorSheet: View {
    let mode: MacStudentEditorMode
    let onSave: (MacStudentDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var isInjured: Bool

    init(mode: MacStudentEditorMode, onSave: @escaping (MacStudentDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _firstName = State(initialValue: "")
            _lastName = State(initialValue: "")
            _email = State(initialValue: "")
            _isInjured = State(initialValue: false)
        case .edit(let row):
            _firstName = State(initialValue: row.student.firstName)
            _lastName = State(initialValue: row.student.lastName)
            _email = State(initialValue: row.student.email ?? "")
            _isInjured = State(initialValue: row.isInjured)
        }
    }

    private var title: String {
        switch mode {
        case .create: return "Nuevo alumno"
        case .edit: return "Editar alumno"
        }
    }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Nombre")
                        .foregroundStyle(.secondary)
                    TextField("Nombre", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Apellidos")
                        .foregroundStyle(.secondary)
                    TextField("Apellidos", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Email")
                        .foregroundStyle(.secondary)
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Lesión")
                        .foregroundStyle(.secondary)
                    Toggle("Alumno lesionado", isOn: $isInjured)
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") {
                    dismiss()
                }
                Button("Guardar") {
                    onSave(
                        MacStudentDraft(
                            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            isInjured: isInjured
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
