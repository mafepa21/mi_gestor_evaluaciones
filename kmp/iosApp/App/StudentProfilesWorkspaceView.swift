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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar alumno…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        VStack(alignment: .leading, spacing: 20) {
                            WorkspaceInspectorHero(
                                title: "\(profile.student.firstName) \(profile.student.lastName)",
                                subtitle: profile.schoolClass?.name ?? "Sin grupo activo"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                                WorkspaceMetricCard(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum")
                                WorkspaceMetricCard(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                                WorkspaceMetricCard(title: "Seguimiento", value: "\(profile.followUpCount)", systemImage: "arrow.triangle.branch")
                                WorkspaceMetricCard(title: "Instrumentos", value: "\(profile.instrumentsCount)", systemImage: "chart.bar.doc.horizontal")
                                WorkspaceMetricCard(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                                WorkspaceMetricCard(title: "Sesiones diario", value: "\(profile.journalSessionCount)", systemImage: "doc.text.fill")
                                WorkspaceMetricCard(title: "Notas individuales", value: "\(profile.journalNoteCount)", systemImage: "note.text")
                            }

                            HStack(spacing: 12) {
                                WorkspaceCompactStat(
                                    title: "Último estado",
                                    value: profile.latestAttendanceStatus ?? "Sin registros",
                                    tint: profile.latestAttendanceStatus?.uppercased().contains("AUS") == true ? .red : .green
                                )
                                WorkspaceCompactStat(
                                    title: "Perfil físico",
                                    value: profile.student.isInjured ? "Lesionado" : "Disponible",
                                    tint: profile.student.isInjured ? .orange : .blue
                                )
                                WorkspaceCompactStat(
                                    title: "Familias",
                                    value: "\(profile.familyCommunicationCount)",
                                    tint: .indigo
                                )
                            }

                            if !profile.recentAttendance.isEmpty {
                                let recentAttendance = Array(profile.recentAttendance.prefix(4))
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Asistencia reciente")
                                        .font(.headline)
                                    ForEach(recentAttendance, id: \.id) { attendance in
                                        recentAttendanceCard(attendance)
                                    }
                                }
                            }

                            if !profile.incidents.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Incidencias destacadas")
                                        .font(.headline)
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
                                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            }

                            if !profile.evaluationTitles.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Instrumentos vinculados")
                                        .font(.headline)
                                    WorkspaceFlowLayout(spacing: 10) {
                                        ForEach(profile.evaluationTitles, id: \.self) { evaluation in
                                            WorkspaceTag(text: evaluation, systemImage: "checklist")
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Resumen docente")
                                    .font(.headline)

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
                                .padding(14)
                                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            if profile.adaptationsSummary != nil || profile.familyCommunicationSummary != nil {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Contexto pedagógico")
                                        .font(.headline)

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

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Timeline docente")
                                    .font(.headline)
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
                                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Button("Ir a asistencia") {
                                    onOpenModule(.attendance, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                                Button("Abrir diario") {
                                    onOpenModule(.diary, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                                Button("Abrir cuaderno") {
                                    onOpenModule(.notebook, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Ver informes") {
                                    onOpenModule(.reports, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona un alumno",
                        subtitle: "La ficha reúne asistencia, evolución, incidencias y evidencias en un mismo flujo."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
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
        let background = appCardBackground(for: colorScheme)
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
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    func reloadProfile() async {
        guard let selectedStudentId else { return }
        profile = try? await bridge.loadStudentProfile(studentId: selectedStudentId, classId: selectedClassId)
    }
}

