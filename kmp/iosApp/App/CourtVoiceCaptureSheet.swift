import SwiftUI
import MiGestorKit

#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Cola Persistente de Notas de Voz de Pista (Para Botón de Acción / Siri / Offline)

struct PendingCourtVoiceNote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let transcript: String
    let classIdHint: Int64?

    init(id: String = UUID().uuidString, createdAt: Date = .now, transcript: String, classIdHint: Int64? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.classIdHint = classIdHint
    }
}

enum CourtVoiceInboxStore {
    private static let storageKey = "court.voice.pending.inbox.v1"
    static let didEnqueueNotification = Notification.Name("CourtVoiceInboxDidEnqueueNotification")

    static func loadPending() -> [PendingCourtVoiceNote] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PendingCourtVoiceNote].self, from: data) else {
            return []
        }
        return decoded
    }

    static func enqueue(transcript: String, classIdHint: Int64? = nil) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = loadPending()
        current.insert(PendingCourtVoiceNote(transcript: trimmed, classIdHint: classIdHint), at: 0)
        if let encoded = try? JSONEncoder().encode(Array(current.prefix(25))) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        NotificationCenter.default.post(name: didEnqueueNotification, object: nil)
    }

    static func remove(id: String) {
        let updated = loadPending().filter { $0.id != id }
        if let encoded = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - App Intent para Botón de Acción del iPhone / Atajos / Apple Watch / Siri

#if canImport(AppIntents)
@available(iOS 17.0, macOS 14.0, *)
struct CaptureCourtVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Capturar Voz de Pista"
    static var description = IntentDescription("Registra una nota de voz en pista (asistencia, actitud, evaluación o lesión) para confirmarla en Mi Gestor Evaluaciones.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Dictado de pista", requestValueDialog: IntentDialog("¿Qué quieres anotar de la clase?"))
    var spokenNote: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clean = spokenNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .result(dialog: "No se detectó ninguna nota para registrar.")
        }
        CourtVoiceInboxStore.enqueue(transcript: clean)
        return .result(dialog: "Nota de pista guardada en la bandeja de confirmación.")
    }
}
#endif

// MARK: - Hoja Principal "Voz de Pista" (Jobs Design Philosophy: 8pt grid, simplicidad radical)

struct CourtVoiceCaptureSheet: View {
    @ObservedObject var bridge: KmpBridge
    let initialClassId: Int64?
    var initialTranscript: String = ""
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recognizer = CourtVoiceLiveRecognizer()
    private let orchestrator = AppleAIOrchestrator()

    @State private var selectedClassId: Int64?
    @State private var manualTranscript: String = ""
    @State private var draft: CourtVoiceCaptureDraft?
    @State private var metadata: AppleAIGenerationMetadata?
    @State private var isAnalyzing = false
    @State private var isApplying = false
    @State private var feedbackBanner: (message: String, isError: Bool)?
    @State private var pendingInbox: [PendingCourtVoiceNote] = []

    // MARK: Datos derivados del Bridge

    private var activeClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == selectedClassId }) ?? bridge.classes.first
    }

    private var studentsInSelectedClass: [Student] {
        if !bridge.studentsInClass.isEmpty {
            return bridge.studentsInClass
        }
        return bridge.allStudents
    }

    private var evaluableColumns: [NotebookColumnDefinition] {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return [] }
        return data.sheet.columns.filter { col in
            col.evaluationId != nil && col.type != .calculated
        }
    }

    private var effectiveTranscript: String {
        let live = recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedActionsCount: Int {
        draft?.actions.filter { $0.isSelected && $0.studentId != nil }.count ?? 0
    }

    private var canApply: Bool {
        selectedClassId != nil && selectedActionsCount > 0 && !isApplying && !isAnalyzing
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard
                    microphoneSection

                    if !pendingInbox.isEmpty {
                        pendingInboxSection
                    }

                    if isAnalyzing {
                        analyzingStateView
                    } else if let draft {
                        reviewTraySection(draft: draft)
                    } else {
                        examplesHintCard
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(EvaluationDesign.surface.opacity(0.45))
            .navigationTitle("Voz de Pista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        if recognizer.isRecording {
                            recognizer.stopRecording()
                        }
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if draft != nil && !(draft?.actions.isEmpty ?? true) {
                        Button {
                            Task { await applySelectedActions() }
                        } label: {
                            if isApplying {
                                ProgressView()
                            } else {
                                Label(
                                    selectedActionsCount == 1 ? "Aplicar 1 acción" : "Aplicar \(selectedActionsCount) acciones",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .fontWeight(.bold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canApply)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 680, maxWidth: 760, minHeight: 580, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            selectedClassId = initialClassId ?? bridge.selectedStudentsClassId ?? bridge.classes.first?.id
            pendingInbox = CourtVoiceInboxStore.loadPending()
            if !initialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                manualTranscript = initialTranscript
            } else if let firstPending = pendingInbox.first {
                manualTranscript = firstPending.transcript
            }
            loadClassRosterAndNotebook()
        }
        .appOnChange(of: selectedClassId) { _ in
            loadClassRosterAndNotebook()
        }
        .appOnChange(of: recognizer.transcript) { newValue in
            if !newValue.isEmpty {
                manualTranscript = newValue
            }
        }
        .onDisappear {
            if recognizer.isRecording {
                recognizer.stopRecording()
            }
        }
    }

    // MARK: - 1. Cabecera y selector de grupo

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(recognizer.isRecording ? Color.red.opacity(0.16) : EvaluationDesign.accentSoft)
                    .frame(width: 56, height: 56)
                Image(systemName: recognizer.isRecording ? "waveform" : "mic.badge.plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(recognizer.isRecording ? Color.red : EvaluationDesign.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Captura manos libres en pista")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Dicta retrasos, actitud, notas rápidas o lesiones de varios alumnos a la vez.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !bridge.classes.isEmpty {
                Picker("Grupo", selection: $selectedClassId) {
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text("\(schoolClass.name) · \(schoolClass.course)º")
                            .tag(Optional(schoolClass.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }

    // MARK: - 2. Bloque de Micrófono y Transcripción Editable

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    if recognizer.isRecording {
                        recognizer.stopRecording()
                        Task { await analyzeCurrentTranscript() }
                    } else {
                        feedbackBanner = nil
                        recognizer.startRecording()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.headline.weight(.bold))
                        Text(recognizer.isRecording ? "Detener y analizar" : "Pulsar y hablar")
                            .font(.headline.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(recognizer.isRecording ? .red : EvaluationDesign.accent)

                Button {
                    Task { await analyzeCurrentTranscript() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                        Text("Estructurar")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(effectiveTranscript.isEmpty || isAnalyzing)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcripción de pista")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !manualTranscript.isEmpty {
                        Button("Limpiar") {
                            manualTranscript = ""
                            recognizer.transcript = ""
                            draft = nil
                            metadata = nil
                            feedbackBanner = nil
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                TextField(
                    "Ej.: Sofía y Mateo llegan 5 minutos tarde. Hugo muy participativo recogiendo el material. Ponle un 8,5 a Lucía.",
                    text: $manualTranscript,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .font(.body)
                .padding(12)
                .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(recognizer.isRecording ? Color.red.opacity(0.45) : EvaluationDesign.border, lineWidth: 1)
                )
            }

            if let statusMsg = recognizer.statusMessage {
                Label(statusMsg, systemImage: "info.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let banner = feedbackBanner {
                HStack(spacing: 10) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(banner.isError ? .orange : .green)
                    Text(banner.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(12)
                .background(
                    (banner.isError ? Color.orange : Color.green).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
        .padding(16)
        .background(NotebookStyle.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }

    // MARK: - 3. Bandeja de Notas Pendientes (Desde Botón de Acción / Atajos / Reloj)

    private var pendingInboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Notas capturadas al vuelo (\(pendingInbox.count))", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button("Vaciar") {
                    CourtVoiceInboxStore.clearAll()
                    pendingInbox = []
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ForEach(pendingInbox.prefix(3)) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.transcript)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Analizar") {
                        manualTranscript = item.transcript
                        CourtVoiceInboxStore.remove(id: item.id)
                        pendingInbox = CourtVoiceInboxStore.loadPending()
                        Task { await analyzeCurrentTranscript() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(NotebookStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 4. Bandeja de Confirmación de 1 Toque (Tarjetas de Acción)

    private func reviewTraySection(draft: CourtVoiceCaptureDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("Bandeja de confirmación (\(draft.actions.count))")
                    .font(.headline.weight(.bold))

                Spacer()

                if let metadata {
                    AppleAIStatusBadge(state: metadata.state, message: metadata.audit.provenanceLabel)
                }
            }

            if draft.actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No se detectaron acciones concretas para los alumnos del grupo.", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    Text("Asegúrate de mencionar el nombre del alumno y qué acción quieres registrar (retraso, falta, actitud, nota o lesión).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(Array(draft.actions.enumerated()), id: \.element.id) { index, action in
                    actionRowCard(index: index, action: action)
                }
            }

            if !draft.unmatchedSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Fragmentos sin alumno identificado", systemImage: "questionmark.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(draft.unmatchedSegments, id: \.self) { seg in
                        Text("• \(seg)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NotebookStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func actionRowCard(index: Int, action: CourtVoiceProposedAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    toggleActionSelection(at: index)
                } label: {
                    Image(systemName: action.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(action.isSelected ? action.kind.tint : .secondary)
                }
                .buttonStyle(.plain)

                Label(action.kind.title, systemImage: action.kind.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(action.kind.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(action.kind.tint.opacity(0.12), in: Capsule())

                Spacer()

                // Selector rápido para cambiar el tipo de acción si el docente lo prefiere
                Menu {
                    ForEach(CourtVoiceActionKind.allCases) { kind in
                        Button {
                            updateActionKind(at: index, kind: kind)
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Selector de alumno (con aviso si requiere confirmación manual)
            HStack(spacing: 12) {
                Image(systemName: action.studentId != nil ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(action.studentId != nil ? .primary : .orange)

                if !studentsInSelectedClass.isEmpty {
                    Picker("Alumno", selection: Binding<Int64?>(
                        get: { action.studentId },
                        set: { newId in
                            updateActionStudent(at: index, studentId: newId)
                        }
                    )) {
                        Text("Elegir alumno (\(action.studentName))").tag(Int64?.none)
                        ForEach(studentsInSelectedClass, id: \.id) { student in
                            Text(student.fullName).tag(Optional(student.id))
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(action.studentName)
                        .font(.subheadline.weight(.bold))
                }

                Spacer()
            }

            // Controles específicos según el tipo de acción
            switch action.kind {
            case .attendance:
                HStack(spacing: 8) {
                    ForEach(AttendanceStatusOption.all) { option in
                        let isCurrent = (action.attendanceStatus ?? "TARDE") == option.id
                        Button {
                            updateAttendanceStatus(at: index, status: option.id)
                        } label: {
                            Text(option.label)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    isCurrent ? option.color.opacity(0.22) : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                                .foregroundStyle(isCurrent ? option.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .quickEvaluation:
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Nota:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("0-10", value: Binding<Double>(
                            get: { action.score ?? 7.0 },
                            set: { updateScore(at: index, score: $0) }
                        ), format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                    }

                    if !evaluableColumns.isEmpty {
                        Picker("Columna", selection: Binding<String?>(
                            get: { action.columnId ?? evaluableColumns.first?.id },
                            set: { updateColumn(at: index, columnId: $0) }
                        )) {
                            ForEach(evaluableColumns, id: \.id) { col in
                                Text(col.title).tag(Optional(col.id))
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Text("Se guardará como acción rápida de evaluación")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            case .injury:
                Toggle(
                    isOn: Binding<Bool>(
                        get: { action.markInjured ?? true },
                        set: { updateInjuryFlag(at: index, markInjured: $0) }
                    )
                ) {
                    Text((action.markInjured ?? true) ? "Marcar como lesionado / adaptación hoy" : "Retirar lesión (ya disponible)")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)

            case .observation:
                EmptyView()
            }

            TextField("Nota o detalle", text: Binding<String>(
                get: { action.note },
                set: { updateNote(at: index, note: $0) }
            ))
            .font(.subheadline)
            .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(action.isSelected ? action.kind.tint.opacity(0.35) : EvaluationDesign.border, lineWidth: 1)
        )
    }

    // MARK: - 5. Estados auxiliares y sugerencias rápidas

    private var analyzingStateView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Cruzando nombres con el listado de clase y preparando acciones...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var examplesHintCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prueba un ejemplo rápido con alumnos de esta clase", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.bold))

            Text("Pulsa en cualquiera de estas frases reales de patio para ver cómo se descompone en acciones de un toque:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(sampleVoicePrompts, id: \.self) { sample in
                Button {
                    manualTranscript = sample
                    Task { await analyzeCurrentTranscript() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "quote.opening")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                        Text(sample)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(EvaluationDesign.accent)
                    }
                    .padding(12)
                    .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(NotebookStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var sampleVoicePrompts: [String] {
        let names = studentsInSelectedClass.prefix(4).map(\.fullName)
        let s1 = names.indices.contains(0) ? names[0] : "Sofía"
        let s2 = names.indices.contains(1) ? names[1] : "Mateo"
        let s3 = names.indices.contains(2) ? names[2] : "Hugo"
        let s4 = names.indices.contains(3) ? names[3] : "Lucía"
        let colName = evaluableColumns.first?.title ?? "rúbrica de golpeo"

        return [
            "\(s1) y \(s2) llegan 5 minutos tarde. \(s3) muy participativo ayudando a recoger el material.",
            "Ponle un 8.5 en \(colName) a \(s4) por su progreso técnico; \(s1) tiene molestia en el tobillo hoy.",
            "\(s2) viene sin material deportivo hoy. Aviso a \(s3) por juego brusco en pista."
        ]
    }

    // MARK: - Lógica de Carga, Análisis y Aplicación en Bloque

    private func loadClassRosterAndNotebook() {
        Task { @MainActor in
            guard let classId = selectedClassId else { return }
            bridge.selectClass(id: classId)
            await bridge.selectStudentsClass(classId: classId)
            if !manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft == nil {
                await analyzeCurrentTranscript()
            }
        }
    }

    @MainActor
    private func analyzeCurrentTranscript() async {
        let text = effectiveTranscript
        guard !text.isEmpty, let classId = selectedClassId else { return }

        isAnalyzing = true
        feedbackBanner = nil
        defer { isAnalyzing = false }

        let studentDescriptors = studentsInSelectedClass.map {
            CourtVoiceStudentDescriptor(id: $0.id, fullName: $0.fullName, isCurrentlyInjured: $0.isInjured)
        }
        let columnDescriptors = evaluableColumns.map {
            CourtVoiceColumnDescriptor(id: $0.id, title: $0.title, evaluationId: $0.evaluationId?.int64Value)
        }
        let input = CourtVoiceCaptureInput(
            transcript: text,
            classId: classId,
            className: activeClass?.name ?? "Clase activa",
            sessionTitle: nil,
            students: studentDescriptors,
            evaluableColumns: columnDescriptors
        )

        do {
            let generation = try await orchestrator.generateWithTrace(
                capability: .courtVoiceCapture,
                input: .courtVoice(input),
                dataSource: "Voz de Pista · \(activeClass?.name ?? "Grupo")",
                includedEvidence: [
                    "Alumnado en grupo: \(studentDescriptors.count)",
                    "Columnas evaluables: \(columnDescriptors.count)"
                ]
            )
            if case .courtVoiceCapture(let parsedDraft) = generation.result {
                draft = parsedDraft
                metadata = generation.metadata
            }
        } catch {
            orchestrator.recordFailure(error)
            let fallbackService = AppleFoundationCourtVoiceService()
            draft = fallbackService.parseWithRulesFallback(from: input, reason: "Estructurado con motor de reglas locales.")
        }
    }

    @MainActor
    private func applySelectedActions() async {
        guard let classId = selectedClassId, let currentDraft = draft else { return }
        let actionsToApply = currentDraft.actions.filter { $0.isSelected && $0.studentId != nil }
        guard !actionsToApply.isEmpty else { return }

        isApplying = true
        feedbackBanner = nil
        defer { isApplying = false }

        var appliedCount = 0
        let now = Date()

        for action in actionsToApply {
            guard let studentId = action.studentId else { continue }
            do {
                switch action.kind {
                case .attendance:
                    let status = action.attendanceStatus ?? "TARDE"
                    try await bridge.saveAttendance(
                        studentId: studentId,
                        classId: classId,
                        on: now,
                        status: status,
                        note: action.note.isEmpty ? nil : action.note
                    )
                    appliedCount += 1

                case .observation:
                    let detailText = action.note.isEmpty ? action.sourceExcerpt : action.note
                    _ = try await bridge.createIncident(
                        classId: classId,
                        studentId: studentId,
                        title: "Observación en pista",
                        detail: detailText,
                        severity: action.severity
                    )
                    try? await bridge.saveQuickStudentNote(
                        studentId: studentId,
                        classId: classId,
                        note: detailText
                    )
                    appliedCount += 1

                case .quickEvaluation:
                    let scoreValue = action.score ?? 7.0
                    let targetCol = evaluableColumns.first(where: { $0.id == action.columnId }) ?? evaluableColumns.first
                    if let col = targetCol {
                        bridge.selectClass(id: classId)
                        bridge.saveColumnGrade(
                            studentId: studentId,
                            column: col,
                            value: IosFormatting.decimal(from: scoreValue)
                        )
                    }
                    let evalId = targetCol?.evaluationId?.int64Value
                    await bridge.performQuickAction(
                        type: .quickEvaluation,
                        mode: .classroom,
                        classId: classId,
                        studentId: studentId,
                        evaluationId: evalId,
                        note: action.note.isEmpty ? nil : action.note,
                        score: scoreValue
                    )
                    appliedCount += 1

                case .injury:
                    let markInjured = action.markInjured ?? true
                    try await bridge.updateStudentInjuryStatus(
                        studentId: studentId,
                        isInjured: markInjured,
                        classId: classId
                    )
                    if !action.note.isEmpty {
                        _ = try? await bridge.createIncident(
                            classId: classId,
                            studentId: studentId,
                            title: markInjured ? "Lesión / Adaptación en pista" : "Alta de lesión",
                            detail: action.note,
                            severity: "medium"
                        )
                    }
                    appliedCount += 1
                }
            } catch {
                feedbackBanner = ("Error al aplicar una acción: \(error.localizedDescription)", true)
            }
        }

        try? await bridge.refreshStudentsDirectory()
        try? await bridge.refreshDashboard()
        bridge.status = appliedCount == 1
            ? "1 acción de Voz de Pista aplicada al cuaderno."
            : "\(appliedCount) acciones de Voz de Pista aplicadas al cuaderno."
        feedbackBanner = (bridge.status, false)

        try? await Task.sleep(nanoseconds: 750_000_000)
        dismiss()
    }

    // MARK: - Mutaciones locales de la bandeja

    private func toggleActionSelection(at index: Int) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].isSelected.toggle()
    }

    private func updateActionKind(at index: Int, kind: CourtVoiceActionKind) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].kind = kind
        if kind == .attendance && draft?.actions[index].attendanceStatus == nil {
            draft?.actions[index].attendanceStatus = "TARDE"
        }
        if kind == .quickEvaluation && draft?.actions[index].score == nil {
            draft?.actions[index].score = 7.5
            draft?.actions[index].columnId = evaluableColumns.first?.id
            draft?.actions[index].columnTitle = evaluableColumns.first?.title
        }
        if kind == .injury && draft?.actions[index].markInjured == nil {
            draft?.actions[index].markInjured = true
        }
    }

    private func updateActionStudent(at index: Int, studentId: Int64?) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].studentId = studentId
        if let studentId, let student = studentsInSelectedClass.first(where: { $0.id == studentId }) {
            draft?.actions[index].studentName = student.fullName
            draft?.actions[index].isSelected = true
        }
    }

    private func updateAttendanceStatus(at index: Int, status: String) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].attendanceStatus = status
    }

    private func updateScore(at index: Int, score: Double) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].score = min(10.0, max(0.0, score))
    }

    private func updateColumn(at index: Int, columnId: String?) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].columnId = columnId
        draft?.actions[index].columnTitle = evaluableColumns.first(where: { $0.id == columnId })?.title
    }

    private func updateInjuryFlag(at index: Int, markInjured: Bool) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].markInjured = markInjured
    }

    private func updateNote(at index: Int, note: String) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].note = note
    }
}
