import SwiftUI
import MiGestorKit

struct CoursesWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onCreateStudent: (Int64) -> Void
    @State var selectedSummary: KmpBridge.CourseInspectorSnapshot?
    @State private var editingClass: SchoolClass?
    @State private var showingClassEditor = false
    @State private var showingSubjectCatalog = false
    @State private var showingAcademicYearWizard = false
    @State private var archivedYearDetail: KmpBridge.AcademicYearSnapshot?

    private var isActiveAcademicYearWritable: Bool {
        bridge.activeAcademicYear?.isActive == true && bridge.activeAcademicYear?.status == "ACTIVE"
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(
                get: { selectedClassId },
                set: { newValue in
                    selectedClassId = newValue
                    guard let newValue else { return }
                    Task { await loadSummary(for: newValue) }
                }
            )) {
                Section("Curso escolar activo") {
                    if let activeYear = bridge.activeAcademicYear {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activeYear.name)
                                .font(.headline)
                            Text("\(activeYear.classCount) grupos · \(activeYear.enrollmentCount) matriculas")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sin curso activo")
                                .font(.subheadline.weight(.semibold))
                            Text("Restaura un curso del historial o crea uno nuevo para volver a ver grupos.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !bridge.archivedAcademicYears.isEmpty {
                                Menu {
                                    ForEach(bridge.archivedAcademicYears) { year in
                                        Button(year.name) {
                                            Task { await activateAcademicYear(year) }
                                        }
                                    }
                                } label: {
                                    Label("Restaurar curso", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showingAcademicYearWizard = true
                    } label: {
                        Label("Nuevo curso escolar", systemImage: "calendar.badge.plus")
                    }
                }

                Section("Cursos") {
                    if bridge.classes.isEmpty {
                        Text(bridge.activeAcademicYear == nil ? "No hay curso activo." : "Este curso escolar no tiene grupos.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Button {
                                selectedClassId = schoolClass.id
                                Task { await loadSummary(for: schoolClass.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(schoolClass.name)
                                        .font(.headline)
                                    Text(classSubtitle(for: schoolClass))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !bridge.archivedAcademicYears.isEmpty {
                    Section("Historial") {
                        ForEach(bridge.archivedAcademicYears) { year in
                            Menu {
                                Button {
                                    archivedYearDetail = year
                                } label: {
                                    Label("Ver resumen", systemImage: "doc.text.magnifyingglass")
                                }

                                Button {
                                    Task { await activateAcademicYear(year) }
                                } label: {
                                    Label("Restaurar como activo", systemImage: "arrow.triangle.2.circlepath")
                                }

                                Button {
                                    archivedYearDetail = year
                                } label: {
                                    Label("Exportar curso", systemImage: "square.and.arrow.up")
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(year.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(year.classCount) grupos · \(year.enrollmentCount) matriculas · Archivado")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        editingClass = nil
                        showingClassEditor = true
                    } label: {
                        Label("Nuevo grupo", systemImage: "plus.circle.fill")
                    }
                    .disabled(!isActiveAcademicYearWritable)

                    Button {
                        showingSubjectCatalog = true
                    } label: {
                        Label("Asignaturas", systemImage: "books.vertical.fill")
                    }
                }
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if let summary = selectedSummary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkspaceInspectorHero(
                                title: summary.schoolClass.name,
                                subtitle: summary.schoolClass.description_?.isEmpty == false ? summary.schoolClass.description_! : classSubtitle(for: summary.schoolClass)
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Alumnado", value: "\(summary.studentCount)", systemImage: "person.3.fill")
                                WorkspaceMetricCard(title: "Asignatura", value: subjectName(for: summary.schoolClass.subjectId?.int64Value) ?? "Sin asignatura", systemImage: "books.vertical.fill")
                                WorkspaceMetricCard(title: "Lesionados", value: "\(summary.injuredStudentCount)", systemImage: "figure.run.circle")
                                WorkspaceMetricCard(title: "Asistencia", value: "\(summary.attendanceRate)%", systemImage: "checklist.checked")
                                WorkspaceMetricCard(title: "Evaluaciones", value: "\(summary.evaluationCount)", systemImage: "chart.bar.doc.horizontal")
                                WorkspaceMetricCard(title: "Incidencias", value: "\(summary.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                                WorkspaceMetricCard(title: "Huecos semanales", value: "\(summary.weeklySlotCount)", systemImage: "calendar.badge.clock")
                                WorkspaceMetricCard(title: "Media", value: IosFormatting.decimal(from: summary.averageScore), systemImage: "sum")
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pulso de hoy")
                                    .font(.headline)
                                HStack(spacing: 12) {
                                    WorkspaceCompactStat(title: "Presentes", value: "\(summary.todayPresentCount)", tint: .green)
                                    WorkspaceCompactStat(title: "Ausencias", value: "\(summary.todayAbsentCount)", tint: .red)
                                    WorkspaceCompactStat(title: "Retrasos", value: "\(summary.todayLateCount)", tint: .orange)
                                    WorkspaceCompactStat(title: "Críticas", value: "\(summary.severeIncidentCount)", tint: .pink)
                                }
                            }

                            if !summary.activeEvaluationNames.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Evaluaciones activas")
                                        .font(.headline)
                                    WorkspaceFlowLayout(spacing: 10) {
                                        ForEach(Array(summary.activeEvaluationNames.enumerated()), id: \.offset) { _, name in
                                            WorkspaceTag(text: name, systemImage: "chart.bar.doc.horizontal")
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Roster rápido")
                                    .font(.headline)
                                if summary.rosterPreview.isEmpty {
                                    Text("Todavía no hay alumnado asignado a este curso.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(summary.rosterPreview, id: \.id) { student in
                                        Button {
                                            onOpenModule(.students, summary.schoolClass.id, student.id)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Circle()
                                                    .fill(student.isInjured ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.16))
                                                    .frame(width: 38, height: 38)
                                                    .overlay(
                                                        Image(systemName: student.isInjured ? "cross.case.fill" : "person.fill")
                                                            .font(.caption.bold())
                                                            .foregroundStyle(student.isInjured ? Color.orange : Color.accentColor)
                                                    )
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("\(student.firstName) \(student.lastName)")
                                                        .font(.subheadline.weight(.bold))
                                                        .foregroundStyle(.primary)
                                                    Text(student.isInjured ? "Seguimiento físico activo" : "Abrir ficha")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(12)
                                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            WorkspaceActionRow(title: "Abrir cuaderno", systemImage: "book.closed.fill") {
                                onOpenModule(.notebook, summary.schoolClass.id, nil)
                            }
                            WorkspaceActionRow(title: "Abrir alumnado", systemImage: "person.text.rectangle.fill") {
                                onOpenModule(.students, summary.schoolClass.id, summary.rosterPreview.first?.id)
                            }
                            WorkspaceActionRow(title: "Pasar a asistencia", systemImage: "checklist.checked") {
                                onOpenModule(.attendance, summary.schoolClass.id, nil)
                            }
                            WorkspaceActionRow(title: "Entrar al diario", systemImage: "doc.text.fill") {
                                onOpenModule(.diary, summary.schoolClass.id, nil)
                            }
                            WorkspaceActionRow(title: "Ver informes", systemImage: "doc.richtext.fill") {
                                onOpenModule(.reports, summary.schoolClass.id, nil)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Acciones de grupo")
                                    .font(.headline)

                                if !isActiveAcademicYearWritable {
                                    Label("Curso archivado o no editable", systemImage: "lock.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)
                                }

                                Button {
                                    onCreateStudent(summary.schoolClass.id)
                                } label: {
                                    Label("Alta rápida de alumno", systemImage: "person.badge.plus")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!isActiveAcademicYearWritable)

                                Button {
                                    editingClass = summary.schoolClass
                                    showingClassEditor = true
                                } label: {
                                    Label("Editar grupo y asignatura", systemImage: "pencil")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!isActiveAcademicYearWritable)

                                if bridge.classes.contains(where: { $0.id != summary.schoolClass.id }) {
                                    Menu {
                                        ForEach(bridge.classes.filter { $0.id != summary.schoolClass.id }, id: \.id) { targetClass in
                                            Button(targetClass.name) {
                                                Task { await duplicateNotebookStructure(from: summary.schoolClass.id, to: targetClass.id) }
                                            }
                                        }
                                    } label: {
                                        Label("Duplicar estructura de cuaderno", systemImage: "square.on.square")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!isActiveAcademicYearWritable)
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona un curso",
                        subtitle: "Desde aquí centralizamos el acceso a cuaderno, asistencia, diario e informes."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .sheet(isPresented: $showingClassEditor) {
            CourseClassEditorSheet(
                schoolClass: editingClass,
                subjects: bridge.subjects,
                onSave: { draft in
                    Task { await saveClassDraft(draft) }
                }
            )
        }
        .sheet(isPresented: $showingSubjectCatalog) {
            SubjectCatalogSheet(
                onSave: { draft in
                    await saveSubjectDraft(draft)
                },
                onDelete: { subject in
                    Task { await deleteSubject(subject) }
                }
            )
        }
        .sheet(item: $archivedYearDetail) { year in
            ArchivedAcademicYearDetailSheet(
                year: year,
                onDelete: {
                    Task { await deleteArchivedAcademicYear(year) }
                }
            )
        }
        .sheet(isPresented: $showingAcademicYearWizard) {
            AcademicYearWizardSheet(
                activeYear: bridge.activeAcademicYear,
                academicYears: bridge.academicYears,
                onCreate: { draft in
                    Task { await createAcademicYear(draft) }
                },
                onArchiveActive: {
                    Task { await archiveActiveAcademicYear() }
                }
            )
        }
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = bridge.classes.first?.id
            }
            if let selectedClassId {
                await loadSummary(for: selectedClassId)
            }
        }
    }

    private func subjectName(for subjectId: Int64?) -> String? {
        guard let subjectId else { return nil }
        return bridge.subjects.first(where: { $0.id == subjectId })?.name
    }

    private func classSubtitle(for schoolClass: SchoolClass) -> String {
        let subject = subjectName(for: schoolClass.subjectId?.int64Value) ?? "Sin asignatura"
        return "Curso \(schoolClass.course) · \(subject)"
    }

    @MainActor
    private func deleteArchivedAcademicYear(_ year: KmpBridge.AcademicYearSnapshot) async {
        do {
            try await bridge.deleteArchivedAcademicYear(id: year.id)
            archivedYearDetail = nil
        } catch {
            bridge.status = "No se pudo eliminar el curso escolar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func createAcademicYear(_ draft: AcademicYearDraft) async {
        do {
            let sourceYearId = draft.copyGroups ? draft.sourceAcademicYearId : nil
            _ = try await bridge.createAcademicYear(
                name: draft.name,
                startDate: draft.startDate,
                endDate: draft.endDate,
                copyGroupsFrom: sourceYearId,
                promoteStudents: draft.copyGroups && draft.promoteStudents
            )
            selectedClassId = bridge.classes.first?.id
            if let selectedClassId {
                await loadSummary(for: selectedClassId)
            } else {
                selectedSummary = nil
            }
            showingAcademicYearWizard = false
        } catch {
            bridge.status = "No se pudo crear el curso escolar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func activateAcademicYear(_ year: KmpBridge.AcademicYearSnapshot) async {
        do {
            try await bridge.setActiveAcademicYear(id: year.id)
            selectedClassId = bridge.classes.first?.id
            if let selectedClassId {
                await loadSummary(for: selectedClassId)
            } else {
                selectedSummary = nil
            }
        } catch {
            bridge.status = "No se pudo activar el curso escolar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func archiveActiveAcademicYear() async {
        guard let activeYear = bridge.activeAcademicYear else { return }
        do {
            try await bridge.archiveAcademicYear(id: activeYear.id)
            selectedClassId = bridge.classes.first?.id
            selectedSummary = nil
        } catch {
            bridge.status = "No se pudo archivar el curso escolar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveClassDraft(_ draft: CourseClassDraft) async {
        do {
            if let original = draft.original {
                try await bridge.updateClass(
                    id: original.id,
                    name: draft.name,
                    course: draft.course,
                    description: original.description_,
                    centerId: original.centerId?.int64Value,
                    academicYearId: original.academicYearId?.int64Value,
                    stageCycleId: original.stageCycleId?.int64Value,
                    subjectId: draft.subjectId
                )
                selectedClassId = original.id
                await loadSummary(for: original.id)
            } else {
                let classId = try await bridge.createClass(name: draft.name, course: draft.course, subjectId: draft.subjectId)
                selectedClassId = classId
                await loadSummary(for: classId)
            }
            showingClassEditor = false
        } catch {
            bridge.status = "No se pudo guardar el grupo: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveSubjectDraft(_ draft: SubjectDraft) async -> Bool {
        do {
            _ = try await bridge.saveSubject(id: draft.id, code: draft.code, name: draft.name)
            return true
        } catch {
            bridge.status = "No se pudo guardar la asignatura: \(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    private func deleteSubject(_ subject: KmpSubject) async {
        do {
            try await bridge.deleteSubject(id: subject.id)
            if let selectedClassId {
                await loadSummary(for: selectedClassId)
            }
        } catch {
            bridge.status = "No se pudo eliminar la asignatura: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadSummary(for classId: Int64) async {
        selectedSummary = try? await bridge.loadCourseSummary(classId: classId)
    }

    @MainActor
    func duplicateNotebookStructure(from sourceClassId: Int64, to targetClassId: Int64) async {
        do {
            bridge.selectClass(id: sourceClassId)
            try await bridge.duplicateNotebookStructure(to: targetClassId)
            let destinationName = bridge.classes.first(where: { $0.id == targetClassId })?.name ?? "el curso destino"
            bridge.status = "Estructura duplicada en \(destinationName)."
        } catch {
            bridge.status = "No se pudo duplicar la estructura: \(error.localizedDescription)"
        }
    }
}

private struct CourseClassDraft {
    let original: SchoolClass?
    let name: String
    let course: Int32
    let subjectId: Int64?
}

private struct SubjectDraft {
    let id: Int64?
    let code: String
    let name: String
}

private struct AcademicYearDraft {
    let name: String
    let startDate: Date
    let endDate: Date
    let sourceAcademicYearId: Int64?
    let copyGroups: Bool
    let promoteStudents: Bool
}

private struct ArchivedAcademicYearDetailSheet: View {
    let year: KmpBridge.AcademicYearSnapshot
    let onDelete: () -> Void
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var exportText = ""
    @State private var exportError: String?
    @State private var isLoadingExport = false

    var body: some View {
        NavigationStack {
            List {
                Section("Curso escolar") {
                    LabeledContent("Nombre", value: year.name)
                    LabeledContent("Estado", value: "Archivado")
                    LabeledContent("Grupos", value: "\(year.classCount)")
                    LabeledContent("Matriculas", value: "\(year.enrollmentCount)")
                    LabeledContent("Inicio", value: formatted(year.startDate))
                    LabeledContent("Fin", value: formatted(year.endDate))
                }

                Section {
                    if isLoadingExport {
                        ProgressView("Preparando exportacion")
                    } else {
                        ShareLink(item: resolvedExportText) {
                            Label("Exportar resumen", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Eliminar curso archivado", systemImage: "trash")
                    }
                } footer: {
                    Text("Se eliminaran grupos, matriculas y datos vinculados a esos grupos. El alumnado global no se elimina.")
                }
            }
            .navigationTitle("Historial")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .alert("Eliminar curso archivado", isPresented: $showingDeleteConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("Esta accion eliminara \(year.classCount) grupos y \(year.enrollmentCount) matriculas archivadas de \(year.name).")
            }
            .task {
                await loadExportText()
            }
        }
    }

    private var resolvedExportText: String {
        exportText.isEmpty ? fallbackExportText : exportText
    }

    private var fallbackExportText: String {
        """
        Curso escolar: \(year.name)
        Estado: Archivado
        Inicio: \(formatted(year.startDate))
        Fin: \(formatted(year.endDate))
        Grupos: \(year.classCount)
        Matriculas: \(year.enrollmentCount)
        """
    }

    @MainActor
    private func loadExportText() async {
        guard exportText.isEmpty else { return }
        isLoadingExport = true
        defer { isLoadingExport = false }
        do {
            exportText = try await bridge.archivedAcademicYearExportText(id: year.id)
            exportError = nil
        } catch {
            exportText = fallbackExportText
            exportError = "No se pudo preparar el detalle completo. Se exportara el resumen."
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }
}

private struct AcademicYearWizardSheet: View {
    let activeYear: KmpBridge.AcademicYearSnapshot?
    let academicYears: [KmpBridge.AcademicYearSnapshot]
    let onCreate: (AcademicYearDraft) -> Void
    let onArchiveActive: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var name = AcademicYearWizardSheet.defaultName()
    @State private var startDate = AcademicYearWizardSheet.defaultStartDate()
    @State private var endDate = AcademicYearWizardSheet.defaultEndDate()
    @State private var copyGroups = false
    @State private var promoteStudents = false
    @State private var sourceAcademicYearId: Int64?

    var sourceOptions: [KmpBridge.AcademicYearSnapshot] {
        academicYears.sorted { $0.name > $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                if step == 0 {
                    Section("Nuevo curso escolar") {
                        TextField("Nombre", text: $name)
                        DatePicker("Inicio", selection: $startDate, displayedComponents: .date)
                        DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                    }
                } else if step == 1 {
                    Section("Estructura") {
                        Toggle("Copiar grupos de otro curso", isOn: $copyGroups)
                        if copyGroups {
                            Picker("Curso origen", selection: $sourceAcademicYearId) {
                                Text("Seleccionar").tag(Int64?.none)
                                ForEach(sourceOptions) { year in
                                    Text(year.name).tag(Optional(year.id))
                                }
                            }
                            Toggle("Promocionar alumnado", isOn: $promoteStudents)
                        }
                    }

                    Section {
                        Toggle("Copiar instrumentos como plantillas", isOn: .constant(false))
                            .disabled(true)
                        Toggle("Copiar situaciones como plantillas", isOn: .constant(false))
                            .disabled(true)
                    } footer: {
                        Text("Notas, asistencia, celdas, evaluaciones e informes no se copian al curso nuevo.")
                    }
                } else {
                    Section("Resumen") {
                        LabeledContent("Curso", value: name)
                        LabeledContent("Grupos") {
                            Text(copyGroups ? "Copiar estructura" : "Curso vacio")
                        }
                        LabeledContent("Alumnado") {
                            Text(promoteStudents ? "Promocionar matriculas" : "Sin alumnado inicial")
                        }
                    }

                    if activeYear != nil {
                        Section("Curso actual") {
                            Button(role: .destructive) {
                                onArchiveActive()
                                dismiss()
                            } label: {
                                Label("Archivar curso activo", systemImage: "archivebox")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Curso escolar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(step < 2 ? "Continuar" : "Crear") {
                        if step < 2 {
                            step += 1
                        } else {
                            onCreate(AcademicYearDraft(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                startDate: startDate,
                                endDate: endDate,
                                sourceAcademicYearId: sourceAcademicYearId,
                                copyGroups: copyGroups,
                                promoteStudents: promoteStudents
                            ))
                        }
                    }
                    .disabled(!canContinue)
                }
            }
            .onAppear {
                if sourceAcademicYearId == nil {
                    sourceAcademicYearId = activeYear?.id
                }
            }
        }
    }

    private var canContinue: Bool {
        if step == 0 {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startDate < endDate
        }
        if step == 1 {
            return !copyGroups || sourceAcademicYearId != nil
        }
        return true
    }

    private static func defaultName() -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let month = calendar.component(.month, from: Date())
        let startYear = month >= 8 ? year : year - 1
        return "\(startYear)/\(startYear + 1)"
    }

    private static func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let year = calendar.component(.month, from: Date()) >= 8 ? calendar.component(.year, from: Date()) : calendar.component(.year, from: Date()) - 1
        return calendar.date(from: DateComponents(year: year, month: 9, day: 1)) ?? Date()
    }

    private static func defaultEndDate() -> Date {
        let calendar = Calendar.current
        let year = calendar.component(.month, from: Date()) >= 8 ? calendar.component(.year, from: Date()) + 1 : calendar.component(.year, from: Date())
        return calendar.date(from: DateComponents(year: year, month: 6, day: 30)) ?? Date()
    }
}

private struct CourseClassEditorSheet: View {
    let schoolClass: SchoolClass?
    let subjects: [KmpSubject]
    let onSave: (CourseClassDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var course: String
    @State private var subjectId: Int64?

    init(schoolClass: SchoolClass?, subjects: [KmpSubject], onSave: @escaping (CourseClassDraft) -> Void) {
        self.schoolClass = schoolClass
        self.subjects = subjects
        self.onSave = onSave
        _name = State(initialValue: schoolClass?.name ?? "")
        _course = State(initialValue: schoolClass.map { "\($0.course)" } ?? "")
        _subjectId = State(initialValue: schoolClass?.subjectId?.int64Value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Grupo") {
                    TextField("Nombre", text: $name)
                    TextField("Curso", text: $course)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }

                Section("Asignatura") {
                    Picker("Asignatura", selection: $subjectId) {
                        Text("Sin asignatura").tag(Int64?.none)
                        ForEach(subjects, id: \.id) { subject in
                            Text(subject.name).tag(Optional(subject.id))
                        }
                    }
                }
            }
            .navigationTitle(schoolClass == nil ? "Nuevo grupo" : "Editar grupo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let courseNumber = Int32(course.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        onSave(CourseClassDraft(
                            original: schoolClass,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            course: courseNumber,
                            subjectId: subjectId
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Int32(course.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                }
            }
        }
    }
}

private struct SubjectCatalogSheet: View {
    let onSave: (SubjectDraft) async -> Bool
    let onDelete: (KmpSubject) -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @State private var editingSubject: KmpSubject?
    @State private var pendingDeleteSubject: KmpSubject?
    @State private var code = ""
    @State private var name = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Nueva asignatura") {
                    subjectFields
                    Button(editingSubject == nil ? "Añadir asignatura" : "Guardar cambios") {
                        Task { await saveCurrentDraft() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isSaving {
                        ProgressView()
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if editingSubject != nil {
                        Button("Cancelar edición", role: .cancel) {
                            resetDraft()
                        }
                    }
                }

                Section("Catálogo") {
                    if bridge.subjects.isEmpty {
                        Text("Todavía no hay asignaturas.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bridge.subjects, id: \.id) { subject in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subject.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(subject.code)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    editingSubject = subject
                                    code = subject.code
                                    name = subject.name
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    pendingDeleteSubject = subject
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Asignaturas")
            .confirmationDialog(
                "Eliminar asignatura",
                isPresented: Binding(
                    get: { pendingDeleteSubject != nil },
                    set: { if !$0 { pendingDeleteSubject = nil } }
                ),
                presenting: pendingDeleteSubject
            ) { subject in
                Button("Eliminar \(subject.name)", role: .destructive) {
                    onDelete(subject)
                    pendingDeleteSubject = nil
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteSubject = nil
                }
            } message: { subject in
                Text("Los grupos que usen \(subject.name) quedarán como Sin asignatura.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var subjectFields: some View {
        Group {
            TextField("Nombre", text: $name)
            TextField("Código", text: $code)
        }
    }

    @MainActor
    private func saveCurrentDraft() async {
        isSaving = true
        saveError = nil
        let draft = SubjectDraft(
            id: editingSubject?.id,
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let didSave = await onSave(draft)
        isSaving = false
        if didSave {
            resetDraft()
        } else {
            saveError = "No se pudo guardar. Revisa nombre y código."
        }
    }

    private func resetDraft() {
        editingSubject = nil
        code = ""
        name = ""
        saveError = nil
    }
}
