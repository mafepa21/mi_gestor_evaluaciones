import SwiftUI
import MiGestorKit

/// Vista de consulta: qué alumnos del grupo tienen medidas de apoyo Nivel III/IV activas
/// y cuáles son, de un vistazo. Solo lectura — para registrar o retirar medidas se usa
/// la ficha de alumno (`StudentProfilesWorkspaceView`/`MacStudentsView`).
struct SupportMeasureGroupOverviewSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let className: String
    let roster: [Student]

    @State private var activeMeasuresByStudent: [Int64: [SupportMeasureRow]] = [:]
    @State private var isLoading = true
    @State private var showAllStudents = false

    private var studentsWithMeasures: [Student] {
        roster
            .filter { !(activeMeasuresByStudent[$0.id]?.isEmpty ?? true) }
            .sorted { $0.fullName < $1.fullName }
    }

    private var studentsWithoutMeasures: [Student] {
        roster
            .filter { activeMeasuresByStudent[$0.id]?.isEmpty ?? true }
            .sorted { $0.fullName < $1.fullName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Cargando medidas…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    summary
                    studentsList
                }
                .background(appSecondarySystemBackgroundColor().opacity(0.35))
            }
        }
        .background(appPageBackground(for: colorScheme))
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 680)
        .task { await loadMeasures() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Medidas de apoyo del grupo")
                    .font(.title2.weight(.bold))
                Text(className.isEmpty ? "Alumnado con medidas Nivel III/IV activas." : "\(className) · alumnado con medidas Nivel III/IV activas.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            importMetric("Con medidas", "\(studentsWithMeasures.count)")
            importMetric("Sin medidas", "\(studentsWithoutMeasures.count)")
            importMetric("Total grupo", "\(roster.count)")
            Spacer()
            Toggle("Ver todos", isOn: $showAllStudents)
                .toggleStyle(.switch)
        }
        .padding(20)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        }
        .padding(24)
    }

    private var studentsList: some View {
        LazyVStack(spacing: 8) {
            if studentsWithMeasures.isEmpty {
                Text("Ningún alumno del grupo tiene medidas Nivel III/IV activas.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(studentsWithMeasures, id: \.id) { student in
                    studentRow(student, measures: activeMeasuresByStudent[student.id] ?? [])
                }
            }

            if showAllStudents && !studentsWithoutMeasures.isEmpty {
                Text("SIN MEDIDAS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(studentsWithoutMeasures, id: \.id) { student in
                    Text(student.fullName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func studentRow(_ student: Student, measures: [SupportMeasureRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(student.fullName)
                    .font(.body.weight(.semibold))
                let hasIV = measures.contains { $0.level == .iv }
                if hasIV {
                    Text("Nivel IV")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.indigo, in: Capsule())
                }
                if measures.contains(where: { $0.reviewStatus == .overdue }) {
                    Label("Revisión vencida", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(IOSAppStyle.danger)
                } else if measures.contains(where: { $0.reviewStatus == .dueSoon }) {
                    Label("Revisión próxima", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(IOSAppStyle.warning)
                }
            }

            WorkspaceFlowLayout(spacing: 6) {
                ForEach(measures) { measure in
                    WorkspaceTag(text: measure.measureType.displayName, systemImage: "checkmark.seal")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.softBorder.opacity(0.8), lineWidth: 1)
        }
    }

    private func importMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
        }
        .frame(minWidth: 96, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @MainActor
    private func loadMeasures() async {
        isLoading = true
        var result: [Int64: [SupportMeasureRow]] = [:]
        for student in roster {
            let snapshots = (try? await bridge.supportMeasures(for: student.id)) ?? []
            result[student.id] = snapshots.map(\.asRow).filter(\.isActive)
        }
        activeMeasuresByStudent = result
        isLoading = false
    }
}
