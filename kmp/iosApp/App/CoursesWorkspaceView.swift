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
    @State private var pendingDeleteClass: SchoolClass?
    @State private var pendingDeleteAcademicYear: KmpBridge.AcademicYearSnapshot?

    private var isActiveAcademicYearWritable: Bool {
        bridge.activeAcademicYear?.isActive == true && bridge.activeAcademicYear?.status == "ACTIVE"
    }

    var body: some View {
        courseWorkspaceContent
            .sheet(isPresented: $showingClassEditor) {
                CourseClassEditorSheet(
                    schoolClass: editingClass,
                    onSave: { draft in
                        Task { await saveClassDraft(draft) }
                    }
                )
                .environmentObject(bridge)
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
                .environmentObject(bridge)
            }
            .sheet(item: $archivedYearDetail) { year in
                ArchivedAcademicYearDetailSheet(
                    year: year,
                    onDelete: {
                        pendingDeleteAcademicYear = year
                    }
                )
                .environmentObject(bridge)
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
            .confirmationDialog(
                "Eliminar grupo",
                isPresented: Binding(
                    get: { pendingDeleteClass != nil },
                    set: { if !$0 { pendingDeleteClass = nil } }
                ),
                presenting: pendingDeleteClass
            ) { schoolClass in
                Button("Eliminar \(schoolClass.name)", role: .destructive) {
                    Task { await deleteClass(schoolClass) }
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteClass = nil
                }
            } message: { schoolClass in
                Text("Se eliminará el grupo \(schoolClass.name) y sus datos vinculados. Esta acción no elimina el alumnado global.")
            }
            .confirmationDialog(
                "Eliminar curso escolar",
                isPresented: Binding(
                    get: { pendingDeleteAcademicYear != nil },
                    set: { if !$0 { pendingDeleteAcademicYear = nil } }
                ),
                presenting: pendingDeleteAcademicYear
            ) { year in
                Button("Eliminar \(year.name)", role: .destructive) {
                    Task { await deleteArchivedAcademicYear(year) }
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteAcademicYear = nil
                }
            } message: { year in
                Text("Se eliminarán \(year.classCount) grupos y \(year.enrollmentCount) matrículas archivadas de \(year.name).")
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

    @ViewBuilder
    private var courseWorkspaceContent: some View {
        ViewThatFits(in: .horizontal) {
            regularCourseWorkspace
            compactCourseWorkspace
        }
        .background(appPageBackground(for: colorScheme))
    }

    private var regularCourseWorkspace: some View {
        HStack(spacing: 0) {
            courseListPane
                .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            courseDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760)
    }

    private var compactCourseWorkspace: some View {
        VStack(spacing: 16) {
            courseListPane
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360, maxHeight: 520)

            courseDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    private var courseListPane: some View {
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(activeYear.name)
                            .font(.headline)
                        Text("\(activeYear.classCount) grupos · \(activeYear.enrollmentCount) matriculas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
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
                    .padding(.vertical, 8)
                }

                Button {
                    showingAcademicYearWizard = true
                } label: {
                    Label("Nuevo curso escolar", systemImage: "calendar.badge.plus")
                }
            }

            Section("Grupos") {
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
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteClass = schoolClass
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            .disabled(!isActiveAcademicYearWritable)

                            Button {
                                editingClass = schoolClass
                                showingClassEditor = true
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                            .disabled(!isActiveAcademicYearWritable)
                        }
                        .contextMenu {
                            Button {
                                editingClass = schoolClass
                                showingClassEditor = true
                            } label: {
                                Label("Editar grupo", systemImage: "pencil")
                            }
                            .disabled(!isActiveAcademicYearWritable)

                            Button(role: .destructive) {
                                pendingDeleteClass = schoolClass
                            } label: {
                                Label("Eliminar grupo", systemImage: "trash")
                            }
                            .disabled(!isActiveAcademicYearWritable)
                        }
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

                            Button(role: .destructive) {
                                pendingDeleteAcademicYear = year
                            } label: {
                                Label("Eliminar curso", systemImage: "trash")
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
        .listStyle(.sidebar)
        .background(appCardBackground(for: colorScheme))
    }

    @ViewBuilder
    private var courseDetailPane: some View {
        Group {
            if let summary = selectedSummary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                            WorkspaceInspectorHero(
                                title: summary.schoolClass.name,
                                subtitle: summary.schoolClass.description_.flatMap { $0.isEmpty ? nil : $0 } ?? classSubtitle(for: summary.schoolClass)
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
                                    Text("Todavía no hay alumnado matriculado en este grupo.")
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
                    title: "Selecciona un grupo",
                    subtitle: "Desde aquí centralizamos el acceso a cuaderno, asistencia, diario e informes."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appPageBackground(for: colorScheme))
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
    private func deleteClass(_ schoolClass: SchoolClass) async {
        do {
            try await bridge.deleteClass(id: schoolClass.id)
            pendingDeleteClass = nil
            if selectedClassId == schoolClass.id {
                selectedClassId = bridge.classes.first?.id
            }
            if let selectedClassId {
                await loadSummary(for: selectedClassId)
            } else {
                selectedSummary = nil
            }
        } catch {
            bridge.status = "No se pudo eliminar el grupo: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteArchivedAcademicYear(_ year: KmpBridge.AcademicYearSnapshot) async {
        do {
            try await bridge.deleteArchivedAcademicYear(id: year.id)
            archivedYearDetail = nil
            pendingDeleteAcademicYear = nil
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

private struct CourseSheetScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let primaryTitle: String
    let canPrimary: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        primaryTitle: String,
        canPrimary: Bool = true,
        onCancel: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.primaryTitle = primaryTitle
        self.canPrimary = canPrimary
        self.onCancel = onCancel
        self.onPrimary = onPrimary
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CourseSheetHero(title: title, subtitle: subtitle, systemImage: systemImage)
                    content
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(EvaluationDesign.surface.opacity(0.4))
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryTitle, action: onPrimary)
                        .fontWeight(.semibold)
                        .disabled(!canPrimary)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 580, idealWidth: 680, maxWidth: 800, minHeight: 520, idealHeight: 660)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }
}

private struct CourseSheetHero: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(EvaluationDesign.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CourseSheetTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
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
        CourseSheetScaffold(
            title: "Historial",
            subtitle: "Consulta el resumen del curso archivado antes de exportarlo o eliminarlo.",
            systemImage: "archivebox.fill",
            primaryTitle: "Cerrar",
            onCancel: { dismiss() },
            onPrimary: { dismiss() }
        ) {
            PremiumCard.section(title: "Curso escolar", systemImage: "calendar.badge.clock") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Nombre", value: year.name)
                    LabeledContent("Estado", value: "Archivado")
                    LabeledContent("Grupos", value: "\(year.classCount)")
                    LabeledContent("Matriculas", value: "\(year.enrollmentCount)")
                    LabeledContent("Inicio", value: formatted(year.startDate))
                    LabeledContent("Fin", value: formatted(year.endDate))
                }
            }

            PremiumCard.section(title: "Exportación", systemImage: "square.and.arrow.up") {
                VStack(alignment: .leading, spacing: 12) {
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
            }

            PremiumCard.section(title: "Zona sensible", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 12) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Eliminar curso archivado", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Text("Se eliminaran grupos, matriculas y datos vinculados a esos grupos. El alumnado global no se elimina.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        CourseSheetScaffold(
            title: "Curso escolar",
            subtitle: "Prepara el curso activo con fechas, estructura y traspaso controlado.",
            systemImage: "calendar.badge.plus",
            primaryTitle: step < 2 ? "Continuar" : "Crear",
            canPrimary: canContinue,
            onCancel: { dismiss() },
            onPrimary: continueOrCreate
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Paso", selection: $step) {
                    Text("Fechas").tag(0)
                    Text("Estructura").tag(1)
                    Text("Resumen").tag(2)
                }
                .pickerStyle(.segmented)

                if step == 0 {
                    PremiumCard.section(title: "Nuevo curso escolar", systemImage: "calendar") {
                        VStack(alignment: .leading, spacing: 16) {
                            CourseSheetTextField(title: "Nombre", placeholder: "2026/2027", text: $name)
                        DatePicker("Inicio", selection: $startDate, displayedComponents: .date)
                        DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                    }
                    }
                } else if step == 1 {
                    PremiumCard.section(title: "Estructura", systemImage: "rectangle.stack.badge.plus") {
                        VStack(alignment: .leading, spacing: 16) {
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
                    }

                    PremiumCard.section(title: "No se copia", systemImage: "lock.doc") {
                        VStack(alignment: .leading, spacing: 12) {
                        Toggle("Copiar instrumentos como plantillas", isOn: .constant(false))
                            .disabled(true)
                        Toggle("Copiar situaciones como plantillas", isOn: .constant(false))
                            .disabled(true)
                        Text("Notas, asistencia, celdas, evaluaciones e informes no se copian al curso nuevo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    PremiumCard.section(title: "Resumen", systemImage: "checkmark.seal") {
                        VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Curso", value: name)
                        LabeledContent("Grupos") {
                            Text(copyGroups ? "Copiar estructura" : "Curso vacio")
                        }
                        LabeledContent("Alumnado") {
                            Text(promoteStudents ? "Promocionar matriculas" : "Sin alumnado inicial")
                        }
                    }
                    }

                    if activeYear != nil {
                        PremiumCard.section(title: "Curso actual", systemImage: "archivebox") {
                            VStack(alignment: .leading, spacing: 12) {
                            Button(role: .destructive) {
                                onArchiveActive()
                                dismiss()
                            } label: {
                                Label("Archivar curso activo", systemImage: "archivebox")
                            }
                                .buttonStyle(.bordered)
                            .disabled(!canArchiveActiveYear)
                        }
                    }
                }
                }
            }
        }
        .onAppear {
            if sourceAcademicYearId == nil {
                sourceAcademicYearId = activeYear?.id
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

    private var canArchiveActiveYear: Bool {
        guard let activeYear else { return false }
        return academicYears.contains { $0.id != activeYear.id && $0.status != "TRASHED" }
    }

    private func continueOrCreate() {
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
    @EnvironmentObject var bridge: KmpBridge
    let schoolClass: SchoolClass?
    let onSave: (CourseClassDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var course: String
    @State private var subjectId: Int64?

    init(schoolClass: SchoolClass?, onSave: @escaping (CourseClassDraft) -> Void) {
        self.schoolClass = schoolClass
        self.onSave = onSave
        _name = State(initialValue: schoolClass?.name ?? "")
        _course = State(initialValue: schoolClass.map { "\($0.course)" } ?? "")
        _subjectId = State(initialValue: schoolClass?.subjectId?.int64Value)
    }

    var body: some View {
        CourseSheetScaffold(
            title: schoolClass == nil ? "Nuevo grupo" : "Editar grupo",
            subtitle: "Define el grupo docente y su asignatura para usarlo en el workspace diario.",
            systemImage: "person.3.sequence.fill",
            primaryTitle: "Guardar",
            canPrimary: canSave,
            onCancel: { dismiss() },
            onPrimary: save
        ) {
            PremiumCard.section(title: "Grupo", systemImage: "rectangle.and.pencil.and.ellipsis") {
                VStack(alignment: .leading, spacing: 16) {
                    CourseSheetTextField(title: "Nombre", placeholder: "1º ESO A", text: $name)
                    CourseSheetTextField(title: "Curso", placeholder: "1", text: $course)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                }
            }

            PremiumCard.section(title: "Asignatura", systemImage: "books.vertical") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Asignatura", selection: $subjectId) {
                        Text("Sin asignatura").tag(Int64?.none)
                        ForEach(bridge.subjects, id: \.id) { subject in
                            Text(subject.name).tag(Optional(subject.id))
                        }
                    }
                    Text("La asignatura ayuda a filtrar contexto y mantener el cuaderno ordenado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int32(course.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func save() {
        guard let courseNumber = Int32(course.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        onSave(CourseClassDraft(
            original: schoolClass,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            course: courseNumber,
            subjectId: subjectId
        ))
        dismiss()
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
        CourseSheetScaffold(
            title: "Asignaturas",
            subtitle: "Mantén un catálogo breve y reutilizable para los grupos del curso.",
            systemImage: "books.vertical.fill",
            primaryTitle: "Cerrar",
            onCancel: { dismiss() },
            onPrimary: { dismiss() }
        ) {
            PremiumCard.section(title: editingSubject == nil ? "Nueva asignatura" : "Editar asignatura", systemImage: "tag") {
                VStack(alignment: .leading, spacing: 16) {
                    subjectFields

                    HStack(spacing: 12) {
                        Button {
                        Task { await saveCurrentDraft() }
                        } label: {
                            Label(editingSubject == nil ? "Añadir asignatura" : "Guardar cambios", systemImage: "checkmark.circle.fill")
                    }
                        .buttonStyle(.borderedProminent)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if editingSubject != nil {
                            Button("Cancelar edición", role: .cancel) {
                                resetDraft()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if isSaving {
                        ProgressView()
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            PremiumCard.section(title: "Catálogo", systemImage: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 12) {
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
        }
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
    }

    private var subjectFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            CourseSheetTextField(title: "Nombre", placeholder: "Matemáticas", text: $name)
            CourseSheetTextField(title: "Código", placeholder: "MAT", text: $code)
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
