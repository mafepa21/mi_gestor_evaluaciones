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
    let groupComparison: NotebookGroupComparison?
    let semanticIcons: [String]
    let aiSectionTitle: String?
    let aiSectionOrigin: String?
    let aiRegenerateTitle: String?
    let averageExplanation: NotebookAverageExplanation?
    let studentInsightEvidence: StudentInsightEvidence
    let pendingColumns: [PendingCell]
    let recentObservations: [NotebookInspectorObservation]
    let rubricSummaries: [NotebookInspectorRubricSummary]
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
    @State private var educationalInsight: StudentInsightDraft? = nil
    @State private var averageInsight: AverageExplanationDraft? = nil
    @State private var tutorMeetingSummary: TutorMeetingSummaryDraft? = nil
    @State private var earlyWarning: EarlyWarning? = nil
    @State private var educationalInsightMetadata: AppleAIGenerationMetadata? = nil
    @State private var isLoadingEducationalInsight = false
    @State private var educationalInsightError: String? = nil
    @State private var educationalInsightOrchestrator = AppleAIOrchestrator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader
                averageSection
                educationalInsightSection
                pendingColumnsSection
                observationsSection
                rubricSection
                quickActions
                detailsSection
                trendsSection
                aiSection
                evidenceEditor
                auditHistorySection
            }
            .padding(24)
        }
        .background(EvaluationBackdrop())
        .task(id: studentId) {
            await loadTrends()
            await refreshEducationalInsight()
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
                        .accessibilityLabel("Cerrar inspector")
                    }
                }

                HStack(spacing: 8) {
                    NotebookPill(label: valueText.isEmpty ? "Sin valor" : valueText, systemImage: "number", active: true, tint: NotebookStyle.primaryTint, compact: true)
                    NotebookPill(label: "Peso \(weightText)", systemImage: "scalemass", active: false, tint: NotebookStyle.primaryTint, compact: true)
                }

                if let groupComparison {
                    HStack(spacing: 6) {
                        Image(systemName: groupComparison.systemImage)
                            .font(.caption.weight(.bold))
                        Text(groupComparison.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(groupComparison.tint)
                }
            }
        }
    }

    private var averageSection: some View {
        NotebookInspectorSection(title: "Media explicada", systemImage: "function") {
            NotebookAverageCompactSummaryView(explanation: averageExplanation)
        }
    }

    private var educationalInsightSection: some View {
        NotebookInspectorSection(title: "Insight educativo", systemImage: "sparkles") {
            NotebookEducationalInsightView(
                insight: educationalInsight,
                averageInsight: averageInsight,
                tutorMeetingSummary: tutorMeetingSummary,
                earlyWarning: earlyWarning,
                metadata: educationalInsightMetadata,
                isLoading: isLoadingEducationalInsight,
                errorMessage: educationalInsightError,
                onRefresh: {
                    Task { await refreshEducationalInsight() }
                }
            )
        }
    }

    @ViewBuilder
    private var pendingColumnsSection: some View {
        NotebookInspectorSection(title: "Columnas pendientes", systemImage: "clock.badge.exclamationmark") {
            if pendingColumns.isEmpty {
                NotebookInspectorEmptyLine(text: "Sin columnas evaluables pendientes.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pendingColumns, id: \.columnId) { pending in
                        NotebookInspectorPendingRow(pending: pending)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var observationsSection: some View {
        NotebookInspectorSection(title: "Últimas observaciones", systemImage: "text.bubble") {
            if recentObservations.isEmpty {
                NotebookInspectorEmptyLine(text: "Sin observaciones registradas para este alumno.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentObservations) { observation in
                        NotebookInspectorObservationRow(observation: observation)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rubricSection: some View {
        NotebookInspectorSection(title: "Rúbricas asociadas", systemImage: "list.bullet.rectangle") {
            if rubricSummaries.isEmpty {
                NotebookInspectorEmptyLine(text: "No hay rúbricas asociadas en este cuaderno.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rubricSummaries) { rubric in
                        NotebookInspectorRubricRow(summary: rubric)
                    }
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

    private static let quickObservationPresets = [
        "No trae material",
        "Falta entrega",
        "Participación destacada",
        "Necesita refuerzo"
    ]

    private static let quickObservationTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    private func appendQuickObservation(_ text: String) {
        let entry = "[\(Self.quickObservationTimestampFormatter.string(from: Date()))] \(text)"
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        noteDraft = trimmed.isEmpty ? entry : trimmed + "\n" + entry
        onSaveContext()
    }

    private var quickObservationChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Incidencia rápida")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.quickObservationPresets, id: \.self) { preset in
                        Button {
                            appendQuickObservation(preset)
                        } label: {
                            Text(preset)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(NotebookStyle.primaryTint.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NotebookStyle.primaryTint)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var evidenceEditor: some View {
        NotebookInspectorSection(title: "Comentario y evidencia", systemImage: "note.text") {
            quickObservationChips

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
            trends = nil
        }
        isLoadingTrends = false
    }

    private func refreshEducationalInsight() async {
        let evidence = studentInsightEvidence.withTrends(trends)
        isLoadingEducationalInsight = true
        educationalInsightError = nil
        defer { isLoadingEducationalInsight = false }

        do {
            let insightGeneration = try await educationalInsightOrchestrator.generateWithTrace(
                capability: .studentInsight,
                input: .student(evidence),
                dataSource: "Inspector del Cuaderno",
                includedEvidence: evidence.evidenceLines
            )
            educationalInsightMetadata = insightGeneration.metadata
            if case .studentInsight(let draft) = insightGeneration.result {
                educationalInsight = draft
            }

            if let explanation = averageExplanation {
                let averageGeneration = try await educationalInsightOrchestrator.generateWithTrace(
                    capability: .averageExplanation,
                    input: .average(explanation, evidence),
                    dataSource: "Inspector del Cuaderno",
                    includedEvidence: evidence.evidenceLines
                )
                if case .averageExplanation(let draft) = averageGeneration.result {
                    averageInsight = draft
                }
            } else {
                averageInsight = nil
            }

            let tutorGeneration = try await educationalInsightOrchestrator.generateWithTrace(
                capability: .tutorMeetingSummary,
                input: .student(evidence),
                dataSource: "Inspector del Cuaderno",
                includedEvidence: evidence.evidenceLines
            )
            if case .tutorMeetingSummary(let summary) = tutorGeneration.result {
                tutorMeetingSummary = summary
            }

            let warningGeneration = try await educationalInsightOrchestrator.generateWithTrace(
                capability: .earlyWarning,
                input: .student(evidence),
                dataSource: "Inspector del Cuaderno",
                includedEvidence: evidence.evidenceLines
            )
            if case .earlyWarning(let warning) = warningGeneration.result {
                earlyWarning = warning
            }
        } catch {
            educationalInsightError = error.localizedDescription
        }
    }
}

struct NotebookGroupComparison {
    let studentValue: Double
    let groupAverage: Double
    let sampleSize: Int

    private var delta: Double { studentValue - groupAverage }

    var label: String {
        let averageText = String(format: "%.1f", groupAverage)
        if abs(delta) < 0.05 {
            return "En la media del grupo (\(averageText))"
        }
        let deltaText = String(format: "%+.1f", delta)
        return "\(deltaText) vs. media del grupo (\(averageText))"
    }

    var tint: Color {
        if abs(delta) < 0.05 { return .secondary }
        return delta > 0 ? NotebookStyle.successTint : NotebookStyle.warningTint
    }

    var systemImage: String {
        if abs(delta) < 0.05 { return "equal.circle" }
        return delta > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }
}

struct NotebookInspectorObservation: Identifiable, Hashable {
    let id: String
    let columnTitle: String
    let note: String
    let icon: String
    let attachmentCount: Int
}

struct NotebookInspectorRubricSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let isPending: Bool
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

private struct NotebookInspectorPendingRow: View {
    let pending: PendingCell

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NotebookStyle.warningTint)
                .frame(width: 24, height: 24)
                .background(NotebookStyle.warningTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(pending.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("Peso previsto \(formattedDecimal(pending.expectedWeight))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formattedDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

private func notebookSystemIconName(for icon: String) -> String {
    switch icon {
    case "✅": return "checkmark.circle.fill"
    case "⭐": return "star.fill"
    case "⚠️": return "exclamationmark.triangle.fill"
    case "🏠": return "house.fill"
    case "🧩": return "puzzlepiece.extension.fill"
    case "📌": return "pin.fill"
    case "💬": return "bubble.left.fill"
    case "": return "note.text"
    default: return icon
    }
}

private struct NotebookInspectorObservationRow: View {
    let observation: NotebookInspectorObservation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: notebookSystemIconName(for: observation.icon))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotebookStyle.primaryTint)
                    .frame(width: 24, height: 24)
                    .background(NotebookStyle.primaryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                Text(observation.columnTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if observation.attachmentCount > 0 {
                    Label("\(observation.attachmentCount)", systemImage: "paperclip")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(observation.note)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(8)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotebookInspectorRubricRow: View {
    let summary: NotebookInspectorRubricSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: summary.isPending ? "circle.dotted" : "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(summary.isPending ? NotebookStyle.warningTint : NotebookStyle.successTint)
                .frame(width: 24, height: 24)
                .background(
                    (summary.isPending ? NotebookStyle.warningTint : NotebookStyle.successTint).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(summary.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(8)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotebookEducationalInsightView: View {
    let insight: StudentInsightDraft?
    let averageInsight: AverageExplanationDraft?
    let tutorMeetingSummary: TutorMeetingSummaryDraft?
    let earlyWarning: EarlyWarning?
    let metadata: AppleAIGenerationMetadata?
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoading && insight == nil {
                        ProgressView()
                            .tint(NotebookStyle.primaryTint)
                    } else if let insight {
                        Text(insight.summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(insight.confidenceNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(errorMessage ?? "Sin lectura educativa disponible todavía.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onRefresh) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .accessibilityLabel("Actualizar insight educativo")
            }

            if let metadata {
                AppleAIStatusBadge(state: metadata.state, message: metadata.availabilityMessage)
            }

            if let insight {
                if let earlyWarning {
                    NotebookEarlyWarningView(warning: earlyWarning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    NotebookInsightSignalRow(title: "Rendimiento", value: insight.performanceSignal, systemImage: "chart.line.uptrend.xyaxis")
                    NotebookInsightSignalRow(title: "Asistencia", value: insight.attendanceSignal, systemImage: "calendar.badge.clock")
                }

                NotebookInsightTagGroup(title: "Fortalezas", systemImage: "checkmark.seal", items: insight.strengths, tint: NotebookStyle.successTint)
                NotebookInsightTagGroup(title: "A mejorar", systemImage: "target", items: insight.improvementAreas, tint: NotebookStyle.warningTint)

                if !insight.risks.isEmpty {
                    NotebookInsightTagGroup(title: "Señales a revisar", systemImage: "exclamationmark.triangle", items: insight.risks, tint: NotebookStyle.warningTint)
                }

                NotebookInsightTagGroup(title: "Recomendaciones", systemImage: "arrow.right.circle", items: insight.recommendations, tint: NotebookStyle.primaryTint)
            }

            if let tutorMeetingSummary {
                NotebookTutorMeetingSummaryView(summary: tutorMeetingSummary)
            }

            if let averageInsight {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Lectura de media", systemImage: "function")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(averageInsight.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([averageInsight.includedSummary, averageInsight.pendingSummary, averageInsight.weightSummary].joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

}

private struct NotebookTutorMeetingSummaryView: View {
    let summary: TutorMeetingSummaryDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tutoría", systemImage: "person.crop.rectangle.stack")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if !summary.keyPoints.isEmpty {
                NotebookInsightTagGroup(
                    title: "Puntos clave",
                    systemImage: "list.bullet.clipboard",
                    items: summary.keyPoints,
                    tint: NotebookStyle.primaryTint
                )
            }

            if !summary.concerns.isEmpty {
                NotebookInsightTagGroup(
                    title: "A revisar",
                    systemImage: "exclamationmark.triangle",
                    items: summary.concerns,
                    tint: NotebookStyle.warningTint
                )
            }

            if !summary.actions.isEmpty {
                NotebookInsightTagGroup(
                    title: "Acciones",
                    systemImage: "checklist",
                    items: summary.actions,
                    tint: NotebookStyle.successTint
                )
            }

            Text(summary.familyFacingSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotebookEarlyWarningView: View {
    let warning: EarlyWarning

    private var tint: Color {
        switch warning.severity {
        case .normal: return NotebookStyle.successTint
        case .moderate: return NotebookStyle.warningTint
        case .priority: return .red
        }
    }

    private var icon: String {
        switch warning.severity {
        case .normal: return "checkmark.seal"
        case .moderate: return "exclamationmark.triangle"
        case .priority: return "exclamationmark.octagon"
        }
    }

    private var confidenceLabel: String {
        switch warning.confidence {
        case ..<0.4: return "Confianza baja"
        case ..<0.7: return "Confianza media"
        default: return "Confianza alta"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Señal preventiva")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(warning.severity.title)
                        .font(.subheadline.weight(.semibold))
                }

                Spacer(minLength: 8)

                Text(confidenceLabel)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if !warning.causes.isEmpty {
                Text(warning.causes.prefix(2).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let recommendation = warning.recommendations.first {
                Text(recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(warning.confidenceNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tint.opacity(0.18)))
    }
}

private struct NotebookInsightSignalRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 24, height: 24)
                .background(NotebookStyle.primaryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotebookInsightTagGroup: View {
    let title: String
    let systemImage: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("Sin datos destacados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(tint)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(8)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct NotebookInspectorEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
