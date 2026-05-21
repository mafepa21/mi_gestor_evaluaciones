import SwiftUI
import MiGestorKit

struct StudentProfilesWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State var searchText = ""
    @State var profile: KmpBridge.StudentProfileSnapshot?

    var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        guard !query.isEmpty else { return base }
        return base.filter {
            "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                IOSSearchField(text: $searchText, placeholder: "Buscar alumno…")
                    .padding(16)

                List(filteredStudents, id: \.id) { student in
                    Button {
                        selectedStudentId = student.id
                        Task { await reloadProfile() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(student.firstName) \(student.lastName)")
                                .font(.headline)
                            Text(student.isInjured ? "Seguimiento físico activo" : "Alumno")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if let profile {
                    ScrollView {
                        VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                            WorkspaceInspectorHero(
                                title: "\(profile.student.firstName) \(profile.student.lastName)",
                                subtitle: profile.schoolClass?.name ?? "Sin grupo activo"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                IOSMetricCard(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                                IOSMetricCard(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum")
                                IOSMetricCard(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                                IOSMetricCard(title: "Seguimiento", value: "\(profile.followUpCount)", systemImage: "arrow.triangle.branch")
                                IOSMetricCard(title: "Instrumentos", value: "\(profile.instrumentsCount)", systemImage: "chart.bar.doc.horizontal")
                                IOSMetricCard(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                                IOSMetricCard(title: "Sesiones diario", value: "\(profile.journalSessionCount)", systemImage: "doc.text.fill")
                                IOSMetricCard(title: "Notas individuales", value: "\(profile.journalNoteCount)", systemImage: "note.text")
                            }

                            HStack(spacing: 12) {
                                IOSMetricCard(
                                    title: "Último estado",
                                    value: profile.latestAttendanceStatus ?? "Sin registros",
                                    tint: profile.latestAttendanceStatus?.uppercased().contains("AUS") == true ? IOSAppStyle.danger : IOSAppStyle.success
                                )
                                IOSMetricCard(
                                    title: "Perfil físico",
                                    value: profile.student.isInjured ? "Lesionado" : "Disponible",
                                    tint: profile.student.isInjured ? IOSAppStyle.warning : IOSAppStyle.info
                                )
                                IOSMetricCard(
                                    title: "Familias",
                                    value: "\(profile.familyCommunicationCount)",
                                    tint: .indigo
                                )
                            }

                            if !profile.recentAttendance.isEmpty {
                                let recentAttendance = Array(profile.recentAttendance.prefix(4))
                                IOSSectionCard(title: "Asistencia reciente", systemImage: "checklist.checked") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(recentAttendance, id: \.id) { attendance in
                                            recentAttendanceCard(attendance)
                                        }
                                    }
                                }
                            }

                            if !profile.incidents.isEmpty {
                                IOSSectionCard(title: "Incidencias destacadas", systemImage: "exclamationmark.bubble.fill") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(profile.incidents.prefix(3), id: \.id) { incident in
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(incident.title)
                                                        .font(.subheadline.weight(.bold))
                                                    Spacer()
                                                    Text(incident.severity.capitalized)
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(.secondary)
                                                }
                                                Text(incident.detail ?? "Sin detalle")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(12)
                                            .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
                                        }
                                    }
                                }
                            }

                            if !profile.evaluationTitles.isEmpty {
                                IOSSectionCard(title: "Instrumentos vinculados", systemImage: "checklist") {
                                    WorkspaceFlowLayout(spacing: 10) {
                                        ForEach(Array(profile.evaluationTitles.enumerated()), id: \.offset) { _, evaluation in
                                            WorkspaceTag(text: evaluation, systemImage: "checklist")
                                        }
                                    }
                                }
                            }

                            IOSSectionCard(title: "Resumen docente", systemImage: "doc.text.magnifyingglass") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ProfileSummaryLine(
                                        title: "Grupo activo",
                                        value: profile.schoolClass?.name ?? "Sin grupo filtrado"
                                    )
                                    ProfileSummaryLine(
                                        title: "Seguimientos abiertos",
                                        value: "\(profile.followUpCount)"
                                    )
                                    ProfileSummaryLine(
                                        title: "Registros con evidencia",
                                        value: "\(profile.evidenceCount)"
                                    )
                                    ProfileSummaryLine(
                                        title: "Instrumentos evaluativos",
                                        value: "\(profile.instrumentsCount)"
                                    )
                                    ProfileSummaryLine(
                                        title: "Sesiones con seguimiento",
                                        value: "\(profile.journalSessionCount)"
                                    )
                                }
                            }

                            if profile.adaptationsSummary != nil || profile.familyCommunicationSummary != nil {
                                IOSSectionCard(title: "Contexto pedagógico", systemImage: "person.text.rectangle") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        if let adaptationsSummary = profile.adaptationsSummary {
                                            WorkspaceDetailBlock(
                                                title: "Adaptaciones recientes",
                                                content: adaptationsSummary
                                            )
                                        }

                                        if let familyCommunicationSummary = profile.familyCommunicationSummary {
                                            WorkspaceDetailBlock(
                                                title: "Comunicación con familias",
                                                content: familyCommunicationSummary
                                            )
                                        }
                                    }
                                }
                            }

                            IOSSectionCard(title: "Timeline docente", systemImage: "clock.arrow.circlepath") {
                                VStack(alignment: .leading, spacing: 10) {
                                    if profile.timeline.isEmpty {
                                        Text("Todavía no hay registros vinculados en esta clase.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(profile.timeline) { entry in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.title)
                                                    .font(.subheadline.weight(.bold))
                                                Text(entry.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(12)
                                            .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Button("Asistencia") {
                                    onOpenModule(.attendance, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                                Button("Diario") {
                                    onOpenModule(.diary, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                                IOSPrimaryActionButton(label: "Cuaderno", systemImage: "doc.text.fill", action: {
                                    onOpenModule(.notebook, selectedClassId, profile.student.id)
                                })
                                Button("Informes") {
                                    onOpenModule(.reports, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(IOSAppStyle.pagePadding)
                    }
                } else {
                    IOSEmptyState(
                        title: "Selecciona un alumno",
                        subtitle: "La ficha reúne asistencia, evolución, incidencias y evidencias en un mismo flujo.",
                        systemImage: "person.text.rectangle"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IOSAppStyle.pageBackground)
        }
        .task {
            await bridge.ensureClassesLoaded()
            await bridge.selectStudentsClass(classId: selectedClassId)
            if selectedStudentId == nil {
                selectedStudentId = bridge.studentsInClass.first?.id ?? bridge.allStudents.first?.id
            }
            await reloadProfile()
        }
        .appOnChange(of: selectedClassId) { _ in
            Task {
                await bridge.selectStudentsClass(classId: selectedClassId)
                if selectedStudentId == nil {
                    selectedStudentId = bridge.studentsInClass.first?.id
                }
                await reloadProfile()
            }
        }
        .appOnChange(of: selectedStudentId) { _ in
            Task { await reloadProfile() }
        }
    }

    func recentAttendanceCard(_ attendance: KmpBridge.AttendanceRecordSnapshot) -> some View {
        let note = attendance.note.isEmpty ? "Registro diario" : attendance.note
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(attendance.status)
                    .font(.subheadline.weight(.bold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(attendance.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
    }

    @MainActor
    func reloadProfile() async {
        guard let selectedStudentId else { return }
        profile = try? await bridge.loadStudentProfile(studentId: selectedStudentId, classId: selectedClassId)
    }
}
