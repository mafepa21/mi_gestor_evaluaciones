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
    let onClose: (() -> Void)?
    let auditEvents: [NotebookCellAuditEvent]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader
                detailsSection
                aiSection
                quickActions
                evidenceEditor
                auditHistorySection
            }
            .padding(24)
        }
        .background(EvaluationBackdrop())
    }

    private var inspectorHeader: some View {
        NotebookSurface(cornerRadius: 16, fill: NotebookStyle.surface, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.headline)
                        .foregroundStyle(NotebookStyle.primaryTint)
                        .frame(width: 36, height: 36)
                        .background(NotebookStyle.primaryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(studentName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        Text(columnTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if let onClose = onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(-4)
                    }
                }

                HStack(spacing: 8) {
                    NotebookPill(label: valueText.isEmpty ? "Sin valor" : valueText, systemImage: "number", active: true, tint: NotebookStyle.primaryTint, compact: true)
                    NotebookPill(label: "Peso \(weightText)", systemImage: "scalemass", active: false, tint: NotebookStyle.primaryTint, compact: true)
                }
            }
        }
    }

    private var detailsSection: some View {
        NotebookInspectorSection(title: "Detalle", systemImage: "tablecells") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(detailRows, id: \.title) { row in
                    NotebookInspectorInfoRow(title: row.title, value: row.value)
                }
            }
        }
    }

    private var detailRows: [(title: String, value: String)] {
        [
            ("Categoría", categoryText),
            ("Tipo", typeText),
            ("Fecha", dateText),
            ("Criterio asociado", criteriaText),
            ("Evidencia", evidenceText),
            ("Evaluación", evaluationText),
            ("Rúbrica", rubricText)
        ]
    }

    private var auditHistorySection: some View {
        NotebookInspectorSection(title: "Historial de cambios", systemImage: "clock.arrow.circlepath") {
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
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        }
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
            NotebookInspectorSection(title: aiSectionTitle, systemImage: "sparkles") {
                NotebookInspectorInfoRow(title: "Origen", value: aiSectionOrigin)
                NotebookInspectorInfoRow(title: "Regeneración", value: "Disponible desde este inspector o por lote")
                Button {
                    onRegenerateAI()
                } label: {
                    Label(aiRegenerateTitle, systemImage: "arrow.triangle.2.circlepath")
                }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var quickActions: some View {
        NotebookInspectorSection(title: "Accesos rápidos", systemImage: "arrow.up.forward.app") {
            VStack(spacing: 8) {
                Button {
                    onOpenStudent()
                } label: {
                    Label("Abrir alumno", systemImage: "person.text.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .buttonStyle(.borderedProminent)

                Button {
                    onOpenEvaluation()
                } label: {
                    Label("Ir a evaluación", systemImage: "checklist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .buttonStyle(.bordered)
                    .disabled(!canOpenEvaluation)

                Button {
                    onOpenRubric()
                } label: {
                    Label("Ver rúbrica", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .buttonStyle(.bordered)
                    .disabled(!canOpenRubric)

                if showsAttendanceShortcut {
                    Button {
                        onOpenAttendance()
                    } label: {
                        Label("Abrir asistencia", systemImage: "calendar.badge.clock")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var evidenceEditor: some View {
        NotebookInspectorSection(title: "Comentario y evidencia", systemImage: "note.text") {
            TextEditor(text: $noteDraft)
                .frame(minHeight: 140)
                .padding(8)
                .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NotebookStyle.softBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("Icono semántico")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                FlexibleTagRow(items: semanticIcons, selected: iconDraft) { icon in
                    iconDraft = icon == iconDraft ? "" : icon
                }
            }

            attachmentsSection

            Button {
                onSaveContext()
            } label: {
                Label("Guardar contexto", systemImage: "square.and.arrow.down")
            }
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

private struct NotebookInspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        NotebookSurface(cornerRadius: 16, fill: NotebookStyle.surface, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)

                content()
            }
        }
    }
}
