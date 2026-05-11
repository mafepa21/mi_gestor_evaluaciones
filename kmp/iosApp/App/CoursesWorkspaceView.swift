import SwiftUI
import MiGestorKit

struct CoursesWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onCreateStudent: (Int64) -> Void
    @State var selectedSummary: KmpBridge.CourseInspectorSnapshot?

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
                                Text("Curso \(schoolClass.course)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
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
                                subtitle: summary.schoolClass.description_?.isEmpty == false ? summary.schoolClass.description_! : "Curso \(summary.schoolClass.course)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Alumnado", value: "\(summary.studentCount)", systemImage: "person.3.fill")
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
                                        ForEach(summary.activeEvaluationNames, id: \.self) { name in
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

