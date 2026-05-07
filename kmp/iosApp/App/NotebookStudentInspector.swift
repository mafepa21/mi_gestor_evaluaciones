import SwiftUI
import PhotosUI
import MiGestorKit

struct NotebookStudentInspector: View {
    let studentName: String
    let columnTitle: String
    let valueText: String
    let categoryText: String
    let weightText: String
    let typeText: String
    let dateText: String
    let criteriaText: String
    let evidenceText: String
    let evaluationText: String
    let rubricText: String
    let semanticIcons: [String]
    let aiSectionTitle: String?
    let aiSectionOrigin: String?
    let aiRegenerateTitle: String?
    let canOpenEvaluation: Bool
    let canOpenRubric: Bool
    let showsAttendanceShortcut: Bool
    @Binding var noteDraft: String
    @Binding var iconDraft: String
    @Binding var attachmentUris: [String]
    @Binding var selectedAttachmentPhoto: PhotosPickerItem?
    let onOpenStudent: () -> Void
    let onOpenEvaluation: () -> Void
    let onOpenRubric: () -> Void
    let onOpenAttendance: () -> Void
    let onRegenerateAI: () -> Void
    let onSaveContext: () -> Void
    let auditEvents: [NotebookCellAuditEvent]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inspector")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                NotebookInspectorInfoRow(title: "Alumno", value: studentName)
                NotebookInspectorInfoRow(title: "Columna", value: columnTitle)
                NotebookInspectorInfoRow(title: "Valor", value: valueText)
                NotebookInspectorInfoRow(title: "Categoría", value: categoryText)
                NotebookInspectorInfoRow(title: "Peso", value: weightText)
                NotebookInspectorInfoRow(title: "Tipo", value: typeText)
                NotebookInspectorInfoRow(title: "Fecha", value: dateText)
                NotebookInspectorInfoRow(title: "Criterio asociado", value: criteriaText)
                NotebookInspectorInfoRow(title: "Evidencia", value: evidenceText)
                NotebookInspectorInfoRow(title: "Evaluación", value: evaluationText)
                NotebookInspectorInfoRow(title: "Rúbrica", value: rubricText)

                aiSection
                quickActions
                evidenceEditor
                auditHistorySection
            }
            .padding(24)
        }
        .background(EvaluationBackdrop())
    }

    private var auditHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historial de cambios")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            
            if auditEvents.isEmpty {
                Text("Sin registros históricos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(auditEvents, id: \.id) { event in
                        auditEventRow(event)
                    }
                }
            }
        }
    }

    private func auditEventRow(_ event: NotebookCellAuditEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(event.action.name.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(event.action == .created ? .green : .blue)
                Spacer()
                Text(formatTimestamp(event.changedAtEpochMs))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            
            if let prevNum = event.previousNumericValue {
                Text("De: \(String(format: "%.1f", prevNum.doubleValue))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let prevText = event.previousTextValue {
                Text("De: \(prevText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            if let nextNum = event.newNumericValue {
                Text("A: \(String(format: "%.1f", nextNum.doubleValue))")
                    .font(.caption2.bold())
            } else if let nextText = event.newTextValue {
                Text("A: \(nextText)")
                    .font(.caption2.bold())
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotebookStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var aiSection: some View {
        if let aiSectionTitle,
           let aiSectionOrigin,
           let aiRegenerateTitle {
            VStack(alignment: .leading, spacing: 10) {
                Text(aiSectionTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                NotebookInspectorInfoRow(title: "Origen", value: aiSectionOrigin)
                NotebookInspectorInfoRow(title: "Regeneración", value: "Disponible desde este inspector o por lote")
                Button(aiRegenerateTitle, action: onRegenerateAI)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accesos rápidos")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            HStack(spacing: 10) {
                Button("Abrir alumno", action: onOpenStudent)
                    .buttonStyle(.borderedProminent)

                Button("Ir a evaluación", action: onOpenEvaluation)
                    .buttonStyle(.bordered)
                    .disabled(!canOpenEvaluation)

                Button("Ver rúbrica", action: onOpenRubric)
                    .buttonStyle(.bordered)
                    .disabled(!canOpenRubric)
            }

            if showsAttendanceShortcut {
                Button("Abrir asistencia", action: onOpenAttendance)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var evidenceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comentario y evidencia")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            TextEditor(text: $noteDraft)
                .frame(minHeight: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NotebookStyle.surface)
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("Icono semántico")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                FlexibleTagRow(items: semanticIcons, selected: iconDraft) { icon in
                    iconDraft = icon == iconDraft ? "" : icon
                }
            }

            attachmentsSection

            Button("Guardar contexto", action: onSaveContext)
                .buttonStyle(.borderedProminent)
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Adjuntos")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $selectedAttachmentPhoto, matching: .images) {
                    Label("Añadir foto", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            if attachmentUris.isEmpty {
                Text("Sin adjuntos todavía")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachmentUris, id: \.self) { uri in
                    HStack(spacing: 8) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(NotebookStyle.primaryTint)
                        Text(URL(fileURLWithPath: uri).lastPathComponent)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            attachmentUris.removeAll { $0 == uri }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Eliminar adjunto")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NotebookStyle.surface)
                    )
                }
            }
        }
    }
}

private struct NotebookInspectorInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
