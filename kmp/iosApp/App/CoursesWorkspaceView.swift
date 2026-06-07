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
                Section("Cursos") {
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

                Section {
                    Button {
                        editingClass = nil
                        showingClassEditor = true
                    } label: {
                        Label("Nuevo grupo", systemImage: "plus.circle.fill")
                    }

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

                                Button {
                                    onCreateStudent(summary.schoolClass.id)
                                } label: {
                                    Label("Alta rápida de alumno", systemImage: "person.badge.plus")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    editingClass = summary.schoolClass
                                    showingClassEditor = true
                                } label: {
                                    Label("Editar grupo y asignatura", systemImage: "pencil")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)

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
                subjects: bridge.subjects,
                onSave: { draft in
                    Task { await saveSubjectDraft(draft) }
                },
                onDelete: { subject in
                    Task { await deleteSubject(subject) }
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
    private func saveSubjectDraft(_ draft: SubjectDraft) async {
        do {
            _ = try await bridge.saveSubject(id: draft.id, code: draft.code, name: draft.name)
        } catch {
            bridge.status = "No se pudo guardar la asignatura: \(error.localizedDescription)"
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
    let subjects: [KmpSubject]
    let onSave: (SubjectDraft) -> Void
    let onDelete: (KmpSubject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingSubject: KmpSubject?
    @State private var pendingDeleteSubject: KmpSubject?
    @State private var code = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Nueva asignatura") {
                    subjectFields
                    Button(editingSubject == nil ? "Añadir asignatura" : "Guardar cambios") {
                        onSave(SubjectDraft(
                            id: editingSubject?.id,
                            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        resetDraft()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if editingSubject != nil {
                        Button("Cancelar edición", role: .cancel) {
                            resetDraft()
                        }
                    }
                }

                Section("Catálogo") {
                    if subjects.isEmpty {
                        Text("Todavía no hay asignaturas.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subjects, id: \.id) { subject in
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

    private func resetDraft() {
        editingSubject = nil
        code = ""
        name = ""
    }
}
