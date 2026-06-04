import SwiftUI
import PhotosUI
import MiGestorKit

struct NotebookStudentInspector: View {
    let bridge: KmpBridge
    let classId: Int64?
    let studentId: Int64
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

    @State private var trends: KmpBridge.AITrendsSnapshot? = nil
    @State private var isLoadingTrends = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader
                detailsSection
                trendsSection
                aiSection
                quickActions
                evidenceEditor
                auditHistorySection
            }
            .padding(24)
        }
        .background(EvaluationBackdrop())
        .task(id: studentId) {
            await loadTrends()
        }
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

    @ViewBuilder
    private var trendsSection: some View {
        NotebookInspectorSection(title: "Análisis de Tendencias IA", systemImage: "chart.line.uptrend.xyaxis") {
            if isLoadingTrends {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(NotebookStyle.primaryTint)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let trends = trends {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        let directionInfo = trendDirectionInfo(trends.trendDirection, delta: trends.averageGradeDelta)
                        Image(systemName: directionInfo.icon)
                            .foregroundStyle(directionInfo.color)
                        Text(directionInfo.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(directionInfo.color)
                        
                        Spacer()
                        
                        Text("Asistencia: \(IosFormatting.decimal(from: trends.attendanceRate))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(trendBgColor(trends.trendDirection).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    if !trends.recentGrades.isEmpty {
                        HStack(spacing: 4) {
                            Text("Últimas notas:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            ForEach(trends.recentGrades.prefix(5), id: \.self) { grade in
                                Text(IosFormatting.decimal(from: grade))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    
                    if !trends.attendanceCorrelationNote.isEmpty {
                        Text(trends.attendanceCorrelationNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    
                    if !trends.behaviorIncidentSummary.isEmpty {
                        Text(trends.behaviorIncidentSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    
                    Divider()
                        .background(NotebookStyle.softBorder)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Cobertura Curricular LOMLOE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(IosFormatting.decimal(from: trends.curriculumCoveragePct))%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(NotebookStyle.primaryTint)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(NotebookStyle.softBorder)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(NotebookStyle.primaryTint)
                                    .frame(width: geo.size.width * CGFloat(trends.curriculumCoveragePct / 100.0), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    
                    if !trends.missingCompetencyLabels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Falta evaluar en cuaderno:")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            
                            FlexibleTagRow(
                                items: trends.missingCompetencyLabels,
                                selected: ""
                            ) { _ in }
                            .disabled(true)
                        }
                    }
                }
            } else {
                Text("No hay datos históricos suficientes para trazar tendencias.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trendDirectionInfo(_ direction: String, delta: Double) -> (icon: String, label: String, color: Color) {
        switch direction {
        case "UPWARD":
            return ("arrow.up.right", "Rendimiento al alza (+ \(IosFormatting.decimal(from: delta)))", .green)
        case "DOWNWARD":
            return ("arrow.down.right", "Rendimiento a la baja (- \(IosFormatting.decimal(from: abs(delta))))", .red)
        case "STABLE":
            return ("arrow.right", "Estable", .blue)
        default:
            return ("questionmark.circle", "Insuficiente", .gray)
        }
    }
    
    private func trendBgColor(_ direction: String) -> Color {
        switch direction {
        case "UPWARD": return .green
        case "DOWNWARD": return .red
        case "STABLE": return .blue
        default: return .gray
        }
    }

    private func loadTrends() async {
        guard let classId = classId else { return }
        isLoadingTrends = true
        do {
            trends = try await bridge.getAITrendsAndMetrics(classId: classId, studentId: studentId)
        } catch {
            print("Error loading trends: \(error)")
        }
        isLoadingTrends = false
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
