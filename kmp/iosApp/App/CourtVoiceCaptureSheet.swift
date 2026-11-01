import SwiftUI
import UniformTypeIdentifiers
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
    @State private var captureDate: Date = .now
    @State private var activePendingNoteId: String?
    @State private var loadedStudents: [Student] = []
    @State private var loadedColumns: [NotebookColumnDefinition] = []
    @State private var sessionTitleHint: String?
    @State private var isLoadingClassContext = false
    @State private var draft: CourtVoiceCaptureDraft?
    @State private var metadata: AppleAIGenerationMetadata?
    @State private var isAnalyzing = false
    @State private var isApplying = false
    @State private var isAudioImporterPresented = false
    @State private var isAudioDropTargeted = false
    @State private var feedbackBanner: (message: String, isError: Bool)?
    @State private var pendingInbox: [PendingCourtVoiceNote] = []
    /// Criterios de rúbricas y plantillas de las columnas visibles, por `columnId`.
    @State private var criteriaInstruments: [String: CourtVoiceInstrumentDescriptor] = [:]
    @State private var refiningCriteriaActionIds: Set<String> = []
    /// «Hoy evalúo»: instrumento fijado para la sesión (se recuerda por clase).
    @State private var focusColumnId: String?
    @State private var selectedActionId: String?
    @State private var expandedActionId: String?
    @State private var isRubricPanelVisible = true
    @State private var isRubricSheetPresented = false
    /// Grabaciones: «Solo guardar» deja el dictado en la lista sin analizarlo.
    @AppStorage("court.voice.saveOnly.v1") private var saveOnly = false
    @State private var pendingRecordingId: String?
    @State private var pendingRecordingClassId: Int64?
    /// Ancho disponible: decide si la rúbrica cabe al lado (no basta la clase de tamaño en Split View o iOS 17).
    @State private var layoutWidth: CGFloat = 0
    @State private var classRecordings: [CourtVoiceRecording] = []
    @State private var isRecordingsSheetPresented = false
    /// Grabaciones de las que sale la bandeja actual: se borran al aplicar.
    @State private var draftRecordingIds: Set<String> = []
    @State private var batchProgress: (current: Int, total: Int, title: String)?
    @State private var isBatchCancelled = false

    // MARK: Datos cargados de forma aislada para la clase seleccionada (sin mutar el Cuaderno ni mezclar allStudents)

    private var activeClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == selectedClassId }) ?? bridge.classes.first
    }

    private var studentsInSelectedClass: [Student] {
        loadedStudents
    }

    private var evaluableColumns: [NotebookColumnDefinition] {
        loadedColumns.filter { col in
            col.type != .calculated &&
            col.type != .attendance &&
            !col.isLocked &&
            !col.isHidden &&
            col.visibility == .visible
        }
    }

    /// Da prioridad siempre a lo que el docente ha escrito o corregido en el campo de texto (`manualTranscript`),
    /// usando `recognizer.transcript` únicamente mientras está grabando en vivo y el campo manual está vacío.
    private var effectiveTranscript: String {
        let manual = manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return manual }
        return recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedActionsCount: Int {
        draft?.actions.filter { $0.isSelected && $0.isReadyToApply }.count ?? 0
    }

    private var canApply: Bool {
        selectedClassId != nil && selectedActionsCount > 0 && !isApplying && !isAnalyzing && !isLoadingClassContext
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerCard
            microphoneSection

            if !pendingInbox.isEmpty {
                pendingInboxSection
            }

            if let batchProgress {
                batchProgressView(batchProgress)
            } else if isAnalyzing || isLoadingClassContext {
                analyzingStateView
            } else if let draft {
                reviewTraySection(draft: draft)
            } else {
                examplesHintCard
            }
        }
        .padding(24)
    }

    /// Rúbrica a la derecha en iPad horizontal y Mac; en iPhone se abre en hoja aparte.
    private var showsRubricSideBySide: Bool {
        focusInstrument != nil && isRubricPanelVisible && layoutWidth >= 900
    }

    @ViewBuilder
    private var sessionLayout: some View {
        if let instrument = focusInstrument, showsRubricSideBySide {
            HStack(alignment: .top, spacing: 0) {
                ScrollView { mainColumn }
                    .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)
                Divider()
                ScrollView { rubricPanel(instrument, onHide: { isRubricPanelVisible = false }) }
                    .frame(minWidth: 480, maxWidth: .infinity)
            }
        } else {
            ScrollView {
                mainColumn
                    .frame(maxWidth: 720, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    var body: some View {
        NavigationStack {
            sessionLayout
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { layoutWidth = $0 }
            .background(EvaluationDesign.surface.opacity(0.45))
            .navigationTitle("Voz de Pista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        // Una grabación en curso no se pierde: se guarda en Grabaciones.
                        if recognizer.isRecording {
                            recognizer.stopRecording()
                            registerFinishedRecording(analyzeNow: false)
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
        .frame(
            minWidth: 620,
            idealWidth: focusInstrument != nil ? 1240 : 680,
            maxWidth: focusInstrument != nil ? .infinity : 760,
            minHeight: 580,
            idealHeight: focusInstrument != nil ? 820 : 680
        )
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .modifier(CourtVoicePageSizing())
        #endif
        .sheet(isPresented: $isRubricSheetPresented) {
            if let instrument = focusInstrument {
                NavigationStack {
                    ScrollView { rubricPanel(instrument, onHide: nil) }
                        .navigationTitle("Rúbrica")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cerrar") { isRubricSheetPresented = false }
                            }
                        }
                }
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
            }
        }
        .sheet(isPresented: $isRecordingsSheetPresented) {
            CourtVoiceRecordingsSheet(
                className: activeClass?.name ?? "Clase",
                recordings: classRecordings,
                onAnalyze: { selection in
                    Task { await analyzeRecordings(selection) }
                },
                onDelete: { ids in
                    CourtVoiceRecordingStore.shared.delete(ids: ids)
                    draftRecordingIds.subtract(ids)
                    reloadRecordings()
                }
            )
        }
        .appOnChange(of: recognizer.finishedRecording) { finished in
            guard finished != nil else { return }
            registerFinishedRecording(analyzeNow: !saveOnly)
        }
        .appOnChange(of: focusColumnId) { newValue in
            if let classId = selectedClassId {
                CourtVoiceFocusStore.save(columnId: newValue, classId: classId)
            }
            selectedActionId = nil
            expandedActionId = nil
            if draft != nil, !effectiveTranscript.isEmpty {
                Task { await analyzeCurrentTranscript() }
            }
        }
        .fileImporter(
            isPresented: $isAudioImporterPresented,
            allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await handleImportedAudioFile(url: url) }
            case .failure(let error):
                feedbackBanner = ("No se pudo abrir el audio: \(error.localizedDescription)", true)
            }
        }
        .onDrop(of: [.fileURL, .audio], isTargeted: $isAudioDropTargeted) { providers in
            handleDroppedAudioProviders(providers)
        }
        .onAppear {
            pendingInbox = CourtVoiceInboxStore.loadPending()
            let initialPending = pendingInbox.first
            selectedClassId = initialClassId
                ?? initialPending?.classIdHint
                ?? bridge.currentNotebookClassId
                ?? bridge.selectedStudentsClassId
                ?? bridge.classes.first?.id

            if !initialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                manualTranscript = initialTranscript
            } else if let firstPending = initialPending {
                manualTranscript = firstPending.transcript
                captureDate = firstPending.createdAt
                activePendingNoteId = firstPending.id
            }
            Task { await loadClassContextAndAnalyzeIfNeeded(shouldAutoAnalyze: true) }
        }
        .appOnChange(of: selectedClassId) { _ in
            Task { await loadClassContextAndAnalyzeIfNeeded(shouldAutoAnalyze: draft != nil) }
        }
        .appOnChange(of: recognizer.transcript) { newValue in
            if !newValue.isEmpty {
                manualTranscript = newValue
            }
        }
        .onDisappear {
            if recognizer.isRecording {
                recognizer.stopRecording()
                registerFinishedRecording(analyzeNow: false)
            }
        }
    }

    // MARK: - 1. Cabecera, selector de grupo y fecha de registro

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    if let sessionTitleHint, !sessionTitleHint.isEmpty {
                        Label("Sesión: \(sessionTitleHint)", systemImage: "figure.run")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EvaluationDesign.accent)
                    } else {
                        Text("Dicta en directo o sube una grabación de Notas de Voz para estructurar tu clase con calma.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    if !bridge.classes.isEmpty {
                        Picker("Grupo", selection: $selectedClassId) {
                            ForEach(bridge.classes, id: \.id) { schoolClass in
                                Text("\(schoolClass.name) · \(schoolClass.course)º")
                                    .tag(Optional(schoolClass.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(recognizer.isRecording)
                    }

                    DatePicker(
                        "Fecha",
                        selection: $captureDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .help("Fecha en la que se registrará la asistencia o nota")
                }
            }
        }
        .padding(16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !criteriaInstruments.isEmpty {
                focusRow
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }

    // MARK: - 2. Bloque de Micrófono, Subida de Audio y Transcripción Editable

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    if recognizer.isRecording {
                        // El registro y, si toca, el análisis los hace `registerFinishedRecording`.
                        recognizer.stopRecording()
                        if recognizer.finishedRecording == nil {
                            // No hubo archivo (no se pudo crear o se dañó): no se dice que está guardado.
                            pendingRecordingId = nil
                            pendingRecordingClassId = nil
                            feedbackBanner = ("No se pudo guardar el audio de este dictado.", true)
                            if !saveOnly && !effectiveTranscript.isEmpty {
                                Task { await analyzeCurrentTranscript() }
                            }
                        }
                    } else {
                        startDictation()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.headline.weight(.bold))
                        if recognizer.isRecording, let startedAt = recognizer.recordingStartedAt {
                            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                                Text("\(saveOnly ? "Parar y guardar" : "Parar y analizar") · \(CourtVoiceRecordingsSheet.durationText(context.date.timeIntervalSince(startedAt)))")
                                    .font(.headline.weight(.bold))
                                    .monospacedDigit()
                            }
                        } else {
                            Text("Pulsar y hablar")
                                .font(.headline.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(recognizer.isRecording ? .red : EvaluationDesign.accent)
                .disabled(recognizer.isTranscribingFile || batchProgress != nil)
                .accessibilityLabel(recognizer.isRecording ? (saveOnly ? "Parar y guardar la grabación" : "Parar y analizar") : "Empezar a dictar")

                Button {
                    feedbackBanner = nil
                    isAudioImporterPresented = true
                } label: {
                    HStack(spacing: 8) {
                        if recognizer.isTranscribingFile {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "waveform.badge.plus")
                                .font(.subheadline.weight(.bold))
                        }
                        Text(recognizer.isTranscribingFile ? "Transcribiendo…" : "Subir nota de voz")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(recognizer.isRecording || recognizer.isTranscribingFile || isAnalyzing)
                .help("Importa o arrastra un audio grabado con Notas de Voz (.m4a, .mp3, .wav)")

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
                .disabled(effectiveTranscript.isEmpty || isAnalyzing || recognizer.isTranscribingFile || isLoadingClassContext)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { recordingControls }
                VStack(alignment: .leading, spacing: 8) { recordingControls }
            }

            if let fileName = recognizer.importedFileName {
                HStack(spacing: 8) {
                    Image(systemName: "music.mic")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(EvaluationDesign.accent)
                    Text("Audio cargado: \(fileName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if recognizer.isTranscribingFile {
                        Text("· Convirtiendo voz a texto…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcripción de pista (puedes corregir cualquier nombre o arrastrar aquí un archivo de Notas de Voz)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !manualTranscript.isEmpty {
                        Button("Limpiar") {
                            manualTranscript = ""
                            recognizer.transcript = ""
                            recognizer.importedFileName = nil
                            activePendingNoteId = nil
                            draft = nil
                            draftRecordingIds = []
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
                        .stroke(
                            isAudioDropTargeted
                                ? EvaluationDesign.accent
                                : (recognizer.isRecording ? Color.red.opacity(0.45) : EvaluationDesign.border),
                            lineWidth: isAudioDropTargeted ? 2 : 1
                        )
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
                    activePendingNoteId = nil
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
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Analizar") {
                        recognizer.transcript = ""
                        manualTranscript = item.transcript
                        captureDate = item.createdAt
                        activePendingNoteId = item.id
                        if let hintedClass = item.classIdHint, bridge.classes.contains(where: { $0.id == hintedClass }) {
                            selectedClassId = hintedClass
                        }
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

    // MARK: - 4. Bandeja de Confirmación de 1 Toque (Apple HIG: Eficiencia radical y acciones en lote)

    private func reviewTraySection(draft: CourtVoiceCaptureDraft) -> some View {
        let evalActionsCount = draft.actions.filter { $0.kind == .quickEvaluation }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("Bandeja de confirmación (\(draft.actions.count))")
                    .font(.headline.weight(.bold))

                if !draft.actions.isEmpty {
                    Button(allActionsSelected ? "Desmarcar todo" : "Marcar todo") {
                        setAllActionsSelected(!allActionsSelected)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(EvaluationDesign.accent)
                }

                Spacer()

                if let metadata {
                    AppleAIStatusBadge(state: metadata.state, message: metadata.audit.provenanceLabel)
                }
            }

            // Barra rápida de lote (Batch Bar HIG): permite fijar el mismo instrumento para todas las notas de golpe o añadir otro alumno
            if !draft.actions.isEmpty {
                HStack(spacing: 12) {
                    if evalActionsCount > 0 && !evaluableColumns.isEmpty {
                        Menu {
                            ForEach(evaluableColumns, id: \.id) { col in
                                Button {
                                    applyColumnToAllEvaluations(columnId: col.id)
                                } label: {
                                    Label(col.title, systemImage: "tablecells")
                                }
                            }
                        } label: {
                            Label(
                                evalActionsCount == 1 ? "Elegir instrumento para la evaluación" : "Mismo instrumento en las \(evalActionsCount) notas",
                                systemImage: "arrow.triangle.branch"
                            )
                            .font(.caption.weight(.bold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Spacer()

                    if !studentsInSelectedClass.isEmpty {
                        Menu {
                            ForEach(studentsInSelectedClass, id: \.id) { student in
                                Button {
                                    addBlankAction(for: student)
                                } label: {
                                    Label(student.fullName, systemImage: "person.badge.plus")
                                }
                            }
                        } label: {
                            Label("Añadir alumno", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.bold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(EvaluationDesign.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    if usesCompactRow(for: action) {
                        compactActionRow(index: index, action: action)
                    } else {
                        actionRowCard(index: index, action: action)
                    }
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
        let isActionIncomplete = !action.isReadyToApply
        return VStack(alignment: .leading, spacing: 12) {
            // Fila superior: Check + Selector de Alumno directo + Selector de Tipo + Botón Copiar/Propagar
            HStack(alignment: .center, spacing: 10) {
                Button {
                    toggleActionSelection(at: index)
                } label: {
                    Image(systemName: (action.isSelected && action.isReadyToApply) ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.bold))
                        .foregroundStyle((action.isSelected && action.isReadyToApply) ? action.kind.tint : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isActionIncomplete)
                .help(isActionIncomplete ? "Completa el alumno, instrumento y nota para poder aplicar" : (action.isSelected ? "Incluida al aplicar" : "Ignorar esta acción"))

                Image(systemName: action.studentId != nil ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(action.studentId != nil ? Color.primary : Color.orange)

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
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                } else {
                    Text(action.studentName)
                        .font(.subheadline.weight(.bold))
                }

                Spacer(minLength: 4)

                // Conmutador rápido de 1 clic entre los 4 tipos de acción
                Menu {
                    ForEach(CourtVoiceActionKind.allCases) { kind in
                        Button {
                            updateActionKind(at: index, kind: kind)
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: action.kind.systemImage)
                        Text(action.kind.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(action.kind.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(action.kind.tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Cambiar entre Evaluación de instrumento, Observación, Asistencia o Lesión")

                // Menú HIG de eficiencia: Copiar esta misma nota/instrumento/acción a otro alumno o propagar al resto
                Menu {
                    if !studentsInSelectedClass.isEmpty {
                        Menu("Clonar esta acción para otro alumno…") {
                            ForEach(studentsInSelectedClass.filter { $0.id != action.studentId }, id: \.id) { student in
                                Button {
                                    duplicateAction(at: index, forStudent: student)
                                } label: {
                                    Text(student.fullName)
                                }
                            }
                        }
                    }

                    if action.kind == .quickEvaluation {
                        Divider()
                        Button {
                            propagateEvaluationSettings(from: index, copyScore: false)
                        } label: {
                            Label("Usar este instrumento en todas las notas", systemImage: "tablecells.badge.ellipsis")
                        }

                        Button {
                            propagateEvaluationSettings(from: index, copyScore: true)
                        } label: {
                            Label("Copiar instrumento y nota a todas las evaluaciones", systemImage: "doc.on.doc.fill")
                        }
                    }

                    Divider()
                    Button(role: .destructive) {
                        removeAction(at: index)
                    } label: {
                        Label("Eliminar de la bandeja", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Copiar nota/instrumento a otro alumno o aplicar al resto")
            }

            // Si hay ambigüedad de alumno (ej. dos "Lucía"), mostrar píldoras con los candidatos para resolver con 1 toque
            if action.studentId == nil && !action.studentCandidates.isEmpty {
                HStack(spacing: 6) {
                    Text("¿Quién es?")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    ForEach(action.studentCandidates) { cand in
                        Button {
                            updateActionStudent(at: index, studentId: cand.id)
                        } label: {
                            Text(cand.fullName)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let reason = action.resolutionReason, !reason.isEmpty {
                Label(reason, systemImage: isActionIncomplete ? "exclamationmark.circle" : "sparkle.magnifyingglass")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isActionIncomplete ? Color.orange : Color.secondary)
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
                                .foregroundStyle(isCurrent ? option.color : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .quickEvaluation:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "tablecells")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(action.columnId != nil ? EvaluationDesign.accent : Color.orange)
                            Picker("Instrumento", selection: Binding<String?>(
                                get: { action.columnId },
                                set: { updateColumn(at: index, columnId: $0) }
                            )) {
                                Text("Sin instrumento, elige uno…").tag(String?.none)
                                ForEach(evaluableColumns, id: \.id) { col in
                                    Text(col.title).tag(Optional(col.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Spacer()

                        if isStructuredColumn(action.columnId) {
                            Picker("Estado", selection: Binding<CourtVoiceDeliveryStatus?>(
                                get: { CourtVoiceDeliveryStatus.from(action.formattedScaleValue) },
                                set: { updateDeliveryStatus(at: index, status: $0) }
                            )) {
                                ForEach(CourtVoiceDeliveryStatus.allCases, id: \.self) { status in
                                    Text(status.label).tag(Optional(status))
                                }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        } else if !showsCriteriaEditor(for: action) {
                        HStack(spacing: 6) {
                            Text(action.rawUnit.map { "Marca (\($0)):" } ?? "Valor:")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(action.score != nil ? Color.secondary : Color.orange)
                            TextField("Sin nota", value: Binding<Double?>(
                                get: { action.score },
                                set: { updateScore(at: index, score: $0) }
                            ), format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 68)

                            Stepper("", value: Binding<Double>(
                                get: { action.score ?? 5.0 },
                                set: { updateScore(at: index, score: $0) }
                            ), in: 0...200, step: 0.5)
                            .labelsHidden()
                        }
                        }
                    }

                    // Si no se reconoció columna pero hay sugerencias, permitir elegir con 1 toque
                    if action.columnId == nil && !action.columnCandidates.isEmpty {
                        HStack(spacing: 6) {
                            Text("Sugerencias:")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(action.columnCandidates) { cand in
                                Button {
                                    updateColumn(at: index, columnId: cand.id)
                                } label: {
                                    Text(cand.title)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(EvaluationDesign.accent.opacity(0.14), in: Capsule())
                                        .foregroundStyle(EvaluationDesign.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Píldoras rápidas LOMLOE / Notas frecuentes para asignar o cambiar con 1 toque
                    if !isStructuredColumn(action.columnId) && !showsCriteriaEditor(for: action) {
                    HStack(spacing: 6) {
                        Text("Rápido:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach([("Insuf. 4", 4.0), ("Suf. 6", 6.0), ("Bien 7", 7.0), ("Not. 8", 8.0), ("Sob. 9.5", 9.5), ("10", 10.0)], id: \.0) { label, preset in
                            let isSelectedPreset = action.score != nil && abs((action.score ?? -1) - preset) < 0.05
                            Button {
                                updateScore(at: index, score: preset)
                            } label: {
                                Text(label)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        isSelectedPreset ? action.kind.tint.opacity(0.22) : Color.secondary.opacity(0.08),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(isSelectedPreset ? action.kind.tint : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    }

                    if showsCriteriaEditor(for: action), let proposals = action.criterionProposals {
                        CourtVoiceCriteriaEditor(
                            proposals: proposals,
                            isLoading: refiningCriteriaActionIds.contains(action.id),
                            onChoose: { criterionId, levelId in
                                chooseCriterionLevel(actionId: action.id, criterionId: criterionId, levelId: levelId)
                            }
                        )
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
                if let proposals = action.criterionProposals, let title = action.criteriaColumnTitle {
                    let count = proposals.filter(\.isMentioned).count
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            criteriaSuggestionLabel(count: count, title: title)
                            Spacer(minLength: 8)
                            criteriaSuggestionButtons(index: index)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            criteriaSuggestionLabel(count: count, title: title)
                            HStack(spacing: 12) { criteriaSuggestionButtons(index: index) }
                        }
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            TextField("Detalle u observación (opcional)", text: Binding<String>(
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
                .stroke(
                    isActionIncomplete
                        ? Color.orange.opacity(0.45)
                        : (action.isSelected ? action.kind.tint.opacity(0.35) : EvaluationDesign.border),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 5. Estados auxiliares y sugerencias rápidas

    private var analyzingStateView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(isLoadingClassContext ? "Cargando listado e instrumentos de la clase..." : "Cruzando nombres con el listado de clase y preparando acciones...")
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
                    recognizer.transcript = ""
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

    // MARK: - Lógica de Carga Aislada, Análisis y Aplicación en Bloque

    @MainActor
    private func handleImportedAudioFile(url: URL) async {
        feedbackBanner = nil
        draft = nil
        draftRecordingIds = []
        metadata = nil
        activePendingNoteId = nil
        if let transcribed = await recognizer.transcribeAudioFile(url: url),
           !transcribed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fileDate = recognizer.importedFileCreationDate {
                captureDate = fileDate
            }
            manualTranscript = transcribed
            await analyzeCurrentTranscript()
        }
    }

    private func handleDroppedAudioProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
        }) else {
            return false
        }

        let targetType = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            ? UTType.fileURL.identifier
            : UTType.audio.identifier

        provider.loadItem(forTypeIdentifier: targetType, options: nil) { item, _ in
            let resolvedURL: URL?
            if let url = item as? URL {
                resolvedURL = url
            } else if let data = item as? Data {
                resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                resolvedURL = nil
            }
            guard let url = resolvedURL else { return }
            Task { @MainActor in
                await handleImportedAudioFile(url: url)
            }
        }
        return true
    }

    /// Carga directamente desde los repositorios los alumnos, columnas y contexto de sesión de la clase seleccionada,
    /// esperando a que terminen antes de analizar y SIN llamar a `bridge.selectClass` para no mutar el Cuaderno ni mezclar `allStudents`.
    @MainActor
    private func loadClassContextAndAnalyzeIfNeeded(shouldAutoAnalyze: Bool) async {
        guard let classId = selectedClassId else {
            loadedStudents = []
            loadedColumns = []
            sessionTitleHint = nil
            criteriaInstruments = [:]
            return
        }

        isLoadingClassContext = true
        defer { isLoadingClassContext = false }

        let students = (try? await bridge.container.classesRepository.listStudentsInClass(classId: classId)) ?? []
        let columns = (try? await bridge.container.notebookConfigRepository.listColumns(classId: classId)) ?? []
        let context = try? await bridge.classroomCaptureContext(classId: classId, on: captureDate)

        loadedStudents = students
        loadedColumns = columns
        criteriaInstruments = await CourtVoiceInstrumentLoader.load(bridge: bridge, classId: classId, columns: evaluableColumns)
        let storedFocus = CourtVoiceFocusStore.columnId(classId: classId)
        focusColumnId = storedFocus.flatMap { criteriaInstruments[$0] != nil ? $0 : nil }
        reloadRecordings()
        sessionTitleHint = context?.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let studentDescriptors = buildStudentDescriptors()
        let columnDescriptors = buildColumnDescriptors()
        recognizer.updateContextualVocabulary(students: studentDescriptors, columns: columnDescriptors, classId: classId, extraPhrases: criteriaVocabulary)

        if shouldAutoAnalyze && !effectiveTranscript.isEmpty {
            await analyzeCurrentTranscript()
        }
    }

    private func buildStudentDescriptors() -> [CourtVoiceStudentDescriptor] {
        studentsInSelectedClass.map {
            CourtVoiceStudentDescriptor(
                id: $0.id,
                firstName: $0.firstName,
                lastName: $0.lastName,
                fullName: $0.fullName,
                isCurrentlyInjured: $0.isInjured
            )
        }
    }

    private func buildColumnDescriptors() -> [CourtVoiceColumnDescriptor] {
        evaluableColumns.map { col in
            CourtVoiceColumnDescriptor(
                id: col.id,
                title: col.title,
                evaluationId: col.evaluationId?.int64Value,
                columnType: col.type.name,
                inputKind: col.inputKind.name,
                scaleKind: CourtVoiceColumnScaleKind(rawValue: col.scaleKind.name) ?? .tenPoint,
                ordinalLevels: col.ordinalLevels,
                unitOrSituation: col.unitOrSituation,
                dateEpochMs: col.dateEpochMs?.int64Value,
                isLocked: col.isLocked,
                isHiddenOrArchived: col.isHidden || col.visibility != .visible,
                tabIds: col.tabIds
            )
        }
    }

    @MainActor
    private func analyzeCurrentTranscript() async {
        let text = effectiveTranscript
        guard !text.isEmpty, let classId = selectedClassId else { return }

        if loadedStudents.isEmpty && loadedColumns.isEmpty {
            await loadClassContextAndAnalyzeIfNeeded(shouldAutoAnalyze: false)
        }

        isAnalyzing = true
        feedbackBanner = nil
        defer { isAnalyzing = false }

        let studentDescriptors = buildStudentDescriptors()
        let columnDescriptors = buildColumnDescriptors()
        recognizer.updateContextualVocabulary(students: studentDescriptors, columns: columnDescriptors, classId: classId, extraPhrases: criteriaVocabulary)

        let input = CourtVoiceCaptureInput(
            transcript: text,
            classId: classId,
            className: activeClass?.name ?? "Clase activa",
            sessionTitle: sessionTitleHint,
            activeTabId: bridge.selectedNotebookTabId,
            referenceDate: captureDate,
            students: studentDescriptors,
            evaluableColumns: columnDescriptors,
            focusColumnId: focusColumnId
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
                draft = CourtVoiceCriteriaMatcher.attachSuggestions(to: parsedDraft, instruments: criteriaInstruments)
                metadata = generation.metadata
            }
        } catch {
            orchestrator.recordFailure(error)
            let fallbackService = AppleFoundationCourtVoiceService()
            let fallback = fallbackService.parseWithRulesFallback(from: input, reason: "Estructurado con motor de reglas locales.")
            draft = CourtVoiceCriteriaMatcher.attachSuggestions(to: fallback, instruments: criteriaInstruments)
        }
        await refineCriteriaWithModel()
    }

    /// Las reglas ya han rellenado la bandeja; Apple Intelligence afina criterios y niveles sin pisar lo que el docente tocó.
    @MainActor
    private func refineCriteriaWithModel() async {
        guard CourtVoiceCriteriaModelRefiner.isAvailable, let actions = draft?.actions else { return }
        let targets = actions.filter { $0.criterionProposals != nil && ($0.kind == .quickEvaluation || $0.kind == .observation) }.prefix(8)
        guard !targets.isEmpty else { return }
        refiningCriteriaActionIds = Set(targets.map(\.id))
        defer { refiningCriteriaActionIds = [] }
        for target in targets {
            guard let proposals = target.criterionProposals else { continue }
            let refined = await CourtVoiceCriteriaModelRefiner.refine(
                text: CourtVoiceCriteriaMatcher.evidenceText(for: target),
                proposals: proposals
            )
            guard let index = draft?.actions.firstIndex(where: { $0.id == target.id }),
                  draft?.actions[index].criteriaColumnId == target.criteriaColumnId,
                  let current = draft?.actions[index].criterionProposals else { continue }
            // Si el docente cambió algo mientras tanto, se respeta su elección criterio a criterio.
            let merged = refined.map { candidate -> CourtVoiceCriterionProposal in
                guard let live = current.first(where: { $0.id == candidate.id }) else { return candidate }
                return live.chosenLevelId != live.suggestedLevelId ? live : candidate
            }
            let wasReady = draft?.actions[index].isReadyToApply ?? false
            draft?.actions[index].criterionProposals = merged
            refiningCriteriaActionIds.remove(target.id)
            if let updated = draft?.actions[index], !wasReady, updated.isReadyToApply {
                draft?.actions[index].isSelected = updated.confidence >= 0.75
            }
        }
    }

    @MainActor
    private func applySelectedActions() async {
        guard let classId = selectedClassId, let currentDraft = draft else { return }
        let actionsToApply = currentDraft.actions.filter { $0.isSelected && $0.isReadyToApply }
        guard !actionsToApply.isEmpty else { return }

        isApplying = true
        feedbackBanner = nil
        defer { isApplying = false }

        var succeededIds: Set<String> = []
        var errorMessages: [String] = []
        var didModifyGradesOrCells = false
        let targetDate = captureDate

        for action in actionsToApply {
            guard let studentId = action.studentId else { continue }
            do {
                switch action.kind {
                case .attendance:
                    let status = action.attendanceStatus ?? "TARDE"
                    try await bridge.saveAttendance(
                        studentId: studentId,
                        classId: classId,
                        on: targetDate,
                        status: status,
                        note: action.note.isEmpty ? nil : action.note
                    )
                    succeededIds.insert(action.id)

                case .observation:
                    let detailText = action.note.isEmpty ? action.sourceExcerpt : action.note
                    _ = try await bridge.createIncident(
                        classId: classId,
                        studentId: studentId,
                        title: "Observación en pista",
                        detail: detailText,
                        severity: action.severity
                    )
                    succeededIds.insert(action.id)

                case .quickEvaluation:
                    guard let colId = action.columnId,
                          let targetCol = evaluableColumns.first(where: { $0.id == colId }) else {
                        throw NSError(domain: "CourtVoice", code: 422, userInfo: [NSLocalizedDescriptionKey: "Selecciona un instrumento válido para \(action.studentName)."])
                    }
                    try await persistSingleEvaluationAction(action: action, column: targetCol, classId: classId, studentId: studentId)
                    didModifyGradesOrCells = true
                    succeededIds.insert(action.id)

                case .injury:
                    let markInjured = action.markInjured ?? true
                    try await bridge.updateStudentInjuryStatus(
                        studentId: studentId,
                        isInjured: markInjured,
                        classId: classId
                    )
                    if !action.note.isEmpty {
                        _ = try await bridge.createIncident(
                            classId: classId,
                            studentId: studentId,
                            title: markInjured ? "Lesión / Adaptación en pista" : "Alta de lesión",
                            detail: action.note,
                            severity: "medium"
                        )
                    }
                    succeededIds.insert(action.id)
                }
            } catch {
                errorMessages.append("\(action.studentName): \(error.localizedDescription)")
            }
        }

        // Refrescamos una única vez al final sin cambiar la clase seleccionada del Cuaderno si era otra.
        if didModifyGradesOrCells {
            if bridge.currentNotebookClassId == classId {
                bridge.notebookViewModel.selectClass(classId: classId, force: true)
            }
            bridge.scheduleGradeSnapshotSync(forClassId: classId)
        }
        try? await bridge.refreshStudentsDirectory()
        try? await bridge.refreshDashboard()

        if errorMessages.isEmpty {
            // Las grabaciones se borran solo si de ellas no queda nada por aplicar ni por resolver.
            let appliedEverything = actionsToApply.count == currentDraft.actions.count && currentDraft.unmatchedSegments.isEmpty
            if !draftRecordingIds.isEmpty && appliedEverything {
                CourtVoiceRecordingStore.shared.delete(ids: draftRecordingIds)
            }
            draftRecordingIds = []
            if let pendingId = activePendingNoteId {
                CourtVoiceInboxStore.remove(id: pendingId)
                pendingInbox = CourtVoiceInboxStore.loadPending()
                activePendingNoteId = nil
            }
            bridge.status = succeededIds.count == 1
                ? "1 acción de Voz de Pista aplicada al cuaderno."
                : "\(succeededIds.count) acciones de Voz de Pista aplicadas al cuaderno."
            feedbackBanner = (bridge.status, false)
            try? await Task.sleep(nanoseconds: 650_000_000)
            dismiss()
        } else {
            // Si hubo errores, quitamos de la bandeja las acciones ya aplicadas y dejamos visibles las fallidas para reintentar sin duplicar.
            draft?.actions.removeAll { succeededIds.contains($0.id) }
            let summary = succeededIds.isEmpty
                ? "No se pudo aplicar: \(errorMessages.joined(separator: " · "))"
                : "Se aplicaron \(succeededIds.count), pero fallaron \(errorMessages.count): \(errorMessages.joined(separator: " · "))"
            feedbackBanner = (summary, true)
        }
    }

    /// Único camino de escritura determinista para evaluaciones según el tipo y escala de la columna.
    @MainActor
    private func persistSingleEvaluationAction(
        action: CourtVoiceProposedAction,
        column: NotebookColumnDefinition,
        classId: Int64,
        studentId: Int64
    ) async throws {
        let descriptor = buildColumnDescriptors().first(where: { $0.id == column.id })
        let converted = AppleFoundationCourtVoiceService.convertValueForColumn(
            rawScore: action.score,
            rawText: action.formattedScaleValue ?? action.note,
            unit: action.rawUnit,
            column: descriptor
        )

        // Criterios valorados en la bandeja: se guardan como evaluación de rúbrica o como respuestas de la plantilla.
        if action.hasChosenCriteria, let proposals = action.criterionProposals, let instrument = criteriaInstruments[column.id] {
            try await persistCriteria(proposals: proposals, instrument: instrument, note: action.note, classId: classId, studentId: studentId)
            return
        }

        // Instrumento estructurado: solo se marca el estado de entrega en el texto de la celda.
        // Nunca saveGrade: la nota real la deriva saveResponses al rellenar los indicadores.
        if column.inputKind.isStructuredInstrument {
            guard let status = CourtVoiceDeliveryStatus.from(converted.formattedText ?? action.formattedScaleValue) else {
                throw NSError(domain: "CourtVoice", code: 422, userInfo: [NSLocalizedDescriptionKey: "Indica si \(column.title) está completada o pendiente."])
            }
            try await bridge.container.notebookRepository.saveCell(
                classId: classId,
                studentId: studentId,
                columnId: column.id,
                textValue: status.rawValue,
                boolValue: nil,
                iconValue: nil,
                ordinalValue: nil,
                note: action.note.nilIfEmpty,
                colorHex: nil,
                attachmentUris: [],
                authorUserId: nil,
                associatedGroupId: nil
            )
            return
        }

        switch column.type {
        case .attendance:
            // La asistencia tiene su propia acción; una nota nunca se escribe en una columna de asistencia.
            throw NSError(domain: "CourtVoice", code: 422, userInfo: [NSLocalizedDescriptionKey: "\(column.title) es de asistencia: usa la acción Asistencia."])

        case .numeric, .rubric:
            guard let numericVal = converted.numericScore ?? action.score else {
                throw NSError(domain: "CourtVoice", code: 422, userInfo: [NSLocalizedDescriptionKey: "Falta calificación numérica."])
            }
            _ = try await bridge.container.notebookRepository.saveGrade(
                classId: classId,
                studentId: studentId,
                columnId: column.id,
                evaluationId: column.evaluationId,
                value: KotlinDouble(value: numericVal)
            )
            if !action.note.isEmpty {
                try? await bridge.container.notebookRepository.saveCell(
                    classId: classId,
                    studentId: studentId,
                    columnId: column.id,
                    textValue: nil,
                    boolValue: nil,
                    iconValue: nil,
                    ordinalValue: nil,
                    note: action.note,
                    colorHex: nil,
                    attachmentUris: [],
                    authorUserId: nil,
                    associatedGroupId: nil
                )
            }

        case .ordinal:
            let ordinalText = converted.formattedText
                ?? action.formattedScaleValue
                ?? action.score.map { IosFormatting.decimal(from: $0) }
            guard let ordinalText, !ordinalText.isEmpty else {
                throw NSError(domain: "CourtVoice", code: 422, userInfo: [NSLocalizedDescriptionKey: "Falta nivel para columna ordinal."])
            }
            try await bridge.container.notebookRepository.saveCell(
                classId: classId,
                studentId: studentId,
                columnId: column.id,
                textValue: nil,
                boolValue: nil,
                iconValue: nil,
                ordinalValue: ordinalText,
                note: action.note.nilIfEmpty,
                colorHex: nil,
                attachmentUris: [],
                authorUserId: nil,
                associatedGroupId: nil
            )

        case .check:
            let boolVal = (converted.formattedText == "true") || ((action.score ?? 0) >= 5.0)
            try await bridge.container.notebookRepository.saveCell(
                classId: classId,
                studentId: studentId,
                columnId: column.id,
                textValue: nil,
                boolValue: KotlinBoolean(value: boolVal),
                iconValue: nil,
                ordinalValue: nil,
                note: action.note.nilIfEmpty,
                colorHex: nil,
                attachmentUris: [],
                authorUserId: nil,
                associatedGroupId: nil
            )

        default:
            let textVal = converted.formattedText
                ?? action.formattedScaleValue
                ?? action.score.map { IosFormatting.decimal(from: $0) }
                ?? action.note
            try await bridge.container.notebookRepository.saveCell(
                classId: classId,
                studentId: studentId,
                columnId: column.id,
                textValue: textVal,
                boolValue: nil,
                iconValue: nil,
                ordinalValue: nil,
                note: action.note.nilIfEmpty,
                colorHex: nil,
                attachmentUris: [],
                authorUserId: nil,
                associatedGroupId: nil
            )
        }
    }

    /// Solo se escriben los criterios con nivel elegido; el resto de valoraciones existentes se conserva.
    @MainActor
    private func persistCriteria(
        proposals: [CourtVoiceCriterionProposal],
        instrument: CourtVoiceInstrumentDescriptor,
        note: String,
        classId: Int64,
        studentId: Int64
    ) async throws {
        let chosen = proposals.filter { $0.chosenLevelId != nil }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        switch instrument.source {
        case .rubric(let evaluationId, _):
            var resolvedScore: Double?
            for proposal in chosen {
                guard let criterionId = Int64(proposal.criterion.id),
                      let levelIdText = proposal.chosenLevelId,
                      let levelId = Int64(levelIdText) else { continue }
                let score = try await bridge.container.rubricsRepository.saveRubricAssessment(
                    studentId: studentId,
                    evaluationId: evaluationId,
                    criterionId: criterionId,
                    levelId: levelId,
                    updatedAtEpochMs: nowMs,
                    deviceId: bridge.localDeviceId,
                    syncVersion: 1
                )
                resolvedScore = score?.doubleValue ?? resolvedScore
            }
            let assessments = try await bridge.container.rubricsRepository.listRubricAssessments(
                studentId: studentId,
                evaluationId: evaluationId
            )
            let selections = assessments.map { "\($0.criterionId):\($0.levelId)" }.sorted().joined(separator: ",")
            guard let score = resolvedScore ?? proposals.previewScore else {
                throw NSError(domain: "CourtVoice", code: 422, userInfo: [NSLocalizedDescriptionKey: "No se pudo calcular la nota de \(instrument.title)."])
            }
            try await bridge.container.notebookRepository.upsertGrade(
                classId: classId,
                studentId: studentId,
                columnId: instrument.columnId,
                evaluationId: KotlinLong(value: evaluationId),
                numericValue: score,
                rubricSelections: selections.isEmpty ? nil : selections,
                evidence: note.nilIfEmpty,
                createdAtEpochMs: nowMs,
                updatedAtEpochMs: nowMs,
                deviceId: bridge.localDeviceId,
                syncVersion: 1
            )

        case .template:
            let existing = try await bridge.container.notebookInstrumentsRepository.listResponsesForCell(
                classId: classId,
                studentId: studentId,
                columnId: instrument.columnId
            )
            var byItem = Dictionary(existing.map { ($0.itemId, $0) }, uniquingKeysWith: { _, last in last })
            let trace = AuditTrace(
                authorUserId: nil,
                createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
                associatedGroupId: nil,
                deviceId: bridge.localDeviceId,
                syncVersion: 1
            )
            for proposal in chosen {
                guard let levelId = proposal.chosenLevelId else { continue }
                let isCheck = proposal.criterion.kind == .check
                byItem[proposal.criterion.id] = NotebookInstrumentResponse(
                    classId: classId,
                    studentId: studentId,
                    columnId: instrument.columnId,
                    itemId: proposal.criterion.id,
                    textValue: nil,
                    boolValue: isCheck ? KotlinBoolean(value: levelId == CourtVoiceCriterionLevel.checkYes.id) : nil,
                    numberValue: isCheck ? nil : Double(levelId).map { KotlinDouble(value: $0) },
                    trace: trace
                )
            }
            _ = try await bridge.container.notebookInstrumentsRepository.saveResponses(
                classId: classId,
                studentId: studentId,
                columnId: instrument.columnId,
                responses: Array(byItem.values),
                updatedAtEpochMs: nowMs,
                deviceId: bridge.localDeviceId,
                syncVersion: 1
            )
        }
    }

    // MARK: - «Hoy evalúo», rúbrica visible y grabaciones

    private var focusInstrument: CourtVoiceInstrumentDescriptor? {
        focusColumnId.flatMap { criteriaInstruments[$0] }
    }

    private var focusRow: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Hoy evalúo", selection: $focusColumnId) {
                    let today = instrumentsForToday
                    if !today.isEmpty {
                        Section("Sesión de hoy") {
                            ForEach(today) { instrument in focusOption(instrument) }
                        }
                    }
                    let rubrics = sortedInstruments.filter { if case .rubric = $0.source { return !today.contains($0) } else { return false } }
                    if !rubrics.isEmpty {
                        Section("Rúbricas") {
                            ForEach(rubrics) { instrument in focusOption(instrument) }
                        }
                    }
                    let templates = sortedInstruments.filter { $0.source == .template && !today.contains($0) }
                    if !templates.isEmpty {
                        Section("Listas y formularios") {
                            ForEach(templates) { instrument in focusOption(instrument) }
                        }
                    }
                    Divider()
                    Text("Detectar al dictar").tag(String?.none)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOY EVALÚO")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(focusInstrument != nil ? EvaluationDesign.accent : Color.secondary)
                        Text(focusInstrument?.title ?? "Detectar al dictar")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    focusInstrument != nil ? EvaluationDesign.accentSoft : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .disabled(recognizer.isRecording)
            .help(recognizer.isRecording ? "No se puede cambiar mientras se graba" : "Instrumento de la sesión")
            .accessibilityLabel("Hoy evalúo")
            .accessibilityValue(focusInstrument.map { "\($0.title), \($0.criteria.count) criterios" } ?? "Detectar al dictar")

            if focusInstrument != nil && !showsRubricSideBySide {
                Button {
                    if layoutWidth >= 900 {
                        isRubricPanelVisible = true
                    } else {
                        isRubricSheetPresented = true
                    }
                } label: {
                    Label("Ver rúbrica", systemImage: "tablecells")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func focusOption(_ instrument: CourtVoiceInstrumentDescriptor) -> some View {
        let noun = instrument.criteria.first?.kind == .check ? "ítems" : "criterios"
        return Text("\(instrument.title) · \(instrument.criteria.count) \(noun)").tag(Optional(instrument.columnId))
    }

    private var sortedInstruments: [CourtVoiceInstrumentDescriptor] {
        criteriaInstruments.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Instrumentos con fecha en el día de la captura (los de la sesión de hoy van arriba).
    private var instrumentsForToday: [CourtVoiceInstrumentDescriptor] {
        sortedInstruments.filter { instrument in
            guard let epoch = loadedColumns.first(where: { $0.id == instrument.columnId })?.dateEpochMs?.int64Value else { return false }
            return Calendar.current.isDate(Date(timeIntervalSince1970: TimeInterval(epoch) / 1000), inSameDayAs: captureDate)
        }
    }

    /// Acción que la rúbrica muestra: la tocada en la bandeja o la primera evaluación del instrumento.
    private var panelAction: CourtVoiceProposedAction? {
        guard let actions = draft?.actions, let focusColumnId else { return nil }
        if let selectedActionId, let selected = actions.first(where: { $0.id == selectedActionId && $0.criteriaColumnId == focusColumnId }) {
            return selected
        }
        return actions.first { $0.kind == .quickEvaluation && $0.criteriaColumnId == focusColumnId }
    }

    private func rubricPanel(_ instrument: CourtVoiceInstrumentDescriptor, onHide: (() -> Void)?) -> some View {
        let action = panelAction
        return CourtVoiceRubricPanel(
            instrument: instrument,
            studentName: action.map { $0.studentId != nil ? $0.studentName : "\($0.studentName) (por confirmar)" },
            proposals: action?.criterionProposals,
            onChoose: { criterionId, levelId in
                guard let actionId = action?.id else { return }
                chooseCriterionLevel(actionId: actionId, criterionId: criterionId, levelId: levelId)
            },
            onHide: onHide
        )
    }

    private func usesCompactRow(for action: CourtVoiceProposedAction) -> Bool {
        focusColumnId != nil && action.kind == .quickEvaluation && action.id != expandedActionId
    }

    /// Fila compacta de la bandeja con «Hoy evalúo»: alumna y niveles en chips. Tocar la marca en la rúbrica.
    private func compactActionRow(index: Int, action: CourtVoiceProposedAction) -> some View {
        let isCurrent = panelAction?.id == action.id
        let chosen = (action.criterionProposals ?? []).compactMap { proposal -> String? in
            guard let level = proposal.chosenLevel else { return nil }
            return "\(proposal.criterion.title) · \(level.name)"
        }
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggleActionSelection(at: index)
            } label: {
                Image(systemName: (action.isSelected && action.isReadyToApply) ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle((action.isSelected && action.isReadyToApply) ? EvaluationDesign.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!action.isReadyToApply)
            .accessibilityLabel(action.isSelected ? "Incluida al aplicar" : "No incluida")

            Button {
                selectedActionId = action.id
                if !showsRubricSideBySide { expandedActionId = action.id }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(action.studentId != nil ? action.studentName : "\(action.studentName) · por confirmar")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(action.studentId != nil ? Color.primary : Color.orange)
                        if isCurrent && showsRubricSideBySide {
                            Label("En la rúbrica", systemImage: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.accent)
                        }
                    }
                    if chosen.isEmpty {
                        Text("Sin niveles: toca para elegir")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowChips(items: chosen)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Muestra sus niveles en la rúbrica")

            Button {
                expandedActionId = action.id
                selectedActionId = action.id
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Editar acción de \(action.studentName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isCurrent && showsRubricSideBySide ? EvaluationDesign.accentSoft : NotebookStyle.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent && showsRubricSideBySide ? EvaluationDesign.accent : EvaluationDesign.border, lineWidth: isCurrent && showsRubricSideBySide ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private var recordingControls: some View {
        Picker("Al terminar", selection: $saveOnly) {
            Text("Analizar al parar").tag(false)
            Text("Solo guardar").tag(true)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .disabled(recognizer.isRecording)
        .accessibilityHint("«Solo guardar» deja el dictado en Grabaciones para analizarlo después")

        Button {
            reloadRecordings()
            isRecordingsSheetPresented = true
        } label: {
            Label(classRecordings.isEmpty ? "Grabaciones" : "Grabaciones (\(classRecordings.count))", systemImage: "waveform")
                .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(recognizer.isRecording || batchProgress != nil)
    }

    private func batchProgressView(_ progress: (current: Int, total: Int, title: String)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: Double(progress.current - 1), total: Double(max(progress.total, 1))) {
                Text("Transcribiendo \(progress.current) de \(progress.total) · \(progress.title)")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Se transcribe en este dispositivo. Al terminar se analiza todo junto en una sola bandeja.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Detener") { isBatchCancelled = true }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func startDictation() {
        feedbackBanner = nil
        activePendingNoteId = nil
        captureDate = .now
        var url: URL?
        if let classId = selectedClassId, let prepared = try? CourtVoiceRecordingStore.shared.prepareNewFile(classId: classId) {
            pendingRecordingId = prepared.id
            pendingRecordingClassId = classId
            url = prepared.url
        }
        recognizer.startRecording(saveTo: url)
    }

    /// Guarda en Grabaciones lo que acaba de grabar el reconocedor y, si toca, lo analiza.
    private func registerFinishedRecording(analyzeNow: Bool) {
        guard let finished = recognizer.finishedRecording,
              let id = pendingRecordingId,
              let classId = pendingRecordingClassId else { return }
        recognizer.finishedRecording = nil
        pendingRecordingId = nil
        pendingRecordingClassId = nil
        let recording = CourtVoiceRecordingStore.shared.register(
            id: id,
            classId: classId,
            createdAt: finished.startedAt,
            duration: finished.duration,
            instrumentColumnId: focusColumnId,
            instrumentTitle: focusInstrument?.title,
            transcript: finished.isTranscriptComplete ? finished.liveTranscript : nil
        )
        reloadRecordings()
        let liveText = finished.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if analyzeNow && !liveText.isEmpty {
            // Solo se borra al aplicar si el texto cubre toda la grabación; si no, queda para analizarla entera.
            draftRecordingIds = finished.isTranscriptComplete ? [recording.id] : []
            if !finished.isTranscriptComplete {
                feedbackBanner = ("El texto en directo se cortó: «\(recording.title)» queda en Grabaciones para analizarla entera.", true)
            }
            Task { await analyzeCurrentTranscript() }
        } else {
            feedbackBanner = ("Guardada en Grabaciones: \(recording.title) (\(CourtVoiceRecordingsSheet.durationText(recording.duration))).", false)
            if !analyzeNow, manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines) == liveText {
                manualTranscript = ""
                recognizer.transcript = ""
            }
        }
    }

    private func reloadRecordings() {
        guard let classId = selectedClassId else {
            classRecordings = []
            return
        }
        classRecordings = CourtVoiceRecordingStore.shared.list(classId: classId)
    }

    /// Transcribe una a una las grabaciones elegidas (o usa su texto ya guardado) y las analiza juntas.
    @MainActor
    private func analyzeRecordings(_ recordings: [CourtVoiceRecording]) async {
        guard !recordings.isEmpty else { return }
        isBatchCancelled = false
        feedbackBanner = nil
        var texts: [String] = []
        var usedIds: Set<String> = []
        var failed: [String] = []
        for (offset, recording) in recordings.enumerated() {
            if isBatchCancelled { break }
            batchProgress = (offset + 1, recordings.count, recording.title)
            if let cached = recording.transcript, !cached.isEmpty {
                texts.append(cached)
                usedIds.insert(recording.id)
                continue
            }
            let url = CourtVoiceRecordingStore.shared.fileURL(for: recording)
            if let text = await recognizer.transcribeAudioFile(url: url)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                CourtVoiceRecordingStore.shared.updateTranscript(id: recording.id, transcript: text)
                texts.append(text)
                usedIds.insert(recording.id)
            } else {
                failed.append(recording.title)
            }
        }
        batchProgress = nil
        recognizer.importedFileName = nil
        reloadRecordings()
        guard !texts.isEmpty else {
            feedbackBanner = (recognizer.statusMessage ?? "No se pudo transcribir ninguna grabación.", true)
            return
        }
        draftRecordingIds = usedIds
        manualTranscript = texts.joined(separator: "\n")
        await analyzeCurrentTranscript()
        if !failed.isEmpty {
            feedbackBanner = ("No se pudo transcribir: \(failed.joined(separator: ", ")). \(recognizer.statusMessage ?? "")", true)
        }
    }

    // MARK: - Mutaciones locales de la bandeja y Aprendizaje de Alias

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
        if kind == .injury && draft?.actions[index].markInjured == nil {
            draft?.actions[index].markInjured = true
        }
        if let action = draft?.actions[index] {
            draft?.actions[index].isSelected = action.isReadyToApply
        }
    }

    private func updateActionStudent(at index: Int, studentId: Int64?) {
        guard draft?.actions.indices.contains(index) == true else { return }
        let previousMention = draft?.actions[index].studentMention ?? ""
        draft?.actions[index].studentId = studentId
        if let studentId, let student = studentsInSelectedClass.first(where: { $0.id == studentId }) {
            draft?.actions[index].studentName = student.fullName
            if let classId = selectedClassId, !previousMention.isEmpty,
               AppleFoundationCourtVoiceService.normalized(previousMention) != AppleFoundationCourtVoiceService.normalized(student.fullName) {
                CourtVoiceAliasStore.learnStudentAlias(mention: previousMention, studentId: studentId, classId: classId)
                draft?.actions[index].resolutionReason = "Aprendido: «\(previousMention)» → \(student.fullName)"
            }
            if let updated = draft?.actions[index] {
                draft?.actions[index].isSelected = updated.isReadyToApply
            }
        } else {
            draft?.actions[index].isSelected = false
        }
    }

    private var allActionsSelected: Bool {
        guard let actions = draft?.actions, !actions.isEmpty else { return false }
        return actions.allSatisfy { $0.isSelected && $0.isReadyToApply }
    }

    private func setAllActionsSelected(_ isSelected: Bool) {
        guard let count = draft?.actions.count else { return }
        for idx in 0..<count {
            draft?.actions[idx].isSelected = isSelected && (draft?.actions[idx].isReadyToApply ?? false)
        }
    }

    private func applyColumnToAllEvaluations(columnId: String) {
        guard let count = draft?.actions.count else { return }
        let title = evaluableColumns.first(where: { $0.id == columnId })?.title
        for idx in 0..<count where draft?.actions[idx].kind == .quickEvaluation {
            draft?.actions[idx].columnId = columnId
            draft?.actions[idx].columnTitle = title
            refreshCriteria(at: idx)
            if let updated = draft?.actions[idx], updated.isReadyToApply {
                draft?.actions[idx].isSelected = true
            }
        }
    }

    private func addBlankAction(for student: Student) {
        let newAction = CourtVoiceProposedAction(
            isSelected: false,
            kind: .quickEvaluation,
            studentId: student.id,
            studentName: student.fullName,
            note: "",
            severity: "low",
            score: nil,
            columnId: nil,
            columnTitle: nil,
            sourceExcerpt: "Añadido manualmente en bandeja",
            resolutionReason: "Elige instrumento y nota para aplicar"
        )
        draft?.actions.append(newAction)
    }

    private func duplicateAction(at index: Int, forStudent student: Student) {
        guard let source = draft?.actions[safe: index] else { return }
        let cloned = CourtVoiceProposedAction(
            isSelected: source.isReadyToApply,
            kind: source.kind,
            studentId: student.id,
            studentName: student.fullName,
            attendanceStatus: source.attendanceStatus,
            note: source.note,
            severity: source.severity,
            score: source.score,
            formattedScaleValue: source.formattedScaleValue,
            rawUnit: source.rawUnit,
            columnId: source.columnId,
            columnTitle: source.columnTitle,
            markInjured: source.markInjured,
            sourceExcerpt: source.sourceExcerpt
        )
        let insertIndex = min((draft?.actions.count ?? 0), index + 1)
        draft?.actions.insert(cloned, at: insertIndex)
    }

    private func propagateEvaluationSettings(from index: Int, copyScore: Bool) {
        guard let source = draft?.actions[safe: index],
              let count = draft?.actions.count else { return }
        for idx in 0..<count where idx != index && draft?.actions[idx].kind == .quickEvaluation {
            draft?.actions[idx].columnId = source.columnId
            draft?.actions[idx].columnTitle = source.columnTitle
            if copyScore, source.hasChosenCriteria {
                draft?.actions[idx].criterionProposals = source.criterionProposals
                draft?.actions[idx].criteriaColumnId = source.criteriaColumnId
            } else {
                refreshCriteria(at: idx)
            }
            if copyScore, let score = source.score {
                draft?.actions[idx].score = score
                draft?.actions[idx].formattedScaleValue = source.formattedScaleValue
                draft?.actions[idx].rawUnit = source.rawUnit
            }
            if let updated = draft?.actions[idx], updated.isReadyToApply {
                draft?.actions[idx].isSelected = true
            }
        }
    }

    private func removeAction(at index: Int) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions.remove(at: index)
    }

    private func updateAttendanceStatus(at index: Int, status: String) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].attendanceStatus = status
    }

    private func updateScore(at index: Int, score: Double?) {
        guard draft?.actions.indices.contains(index) == true else { return }
        if let score {
            let colId = draft?.actions[index].columnId
            let colDesc = buildColumnDescriptors().first(where: { $0.id == colId })
            let maxAllowed = (colDesc?.scaleKind.isRawPhysicalMark == true || colDesc?.scaleKind == .percentage) ? 1000.0 : 10.0
            let clamped = min(maxAllowed, max(0.0, score))
            draft?.actions[index].score = clamped
            draft?.actions[index].deliveryRawScore = nil
            if let colDesc {
                let conv = AppleFoundationCourtVoiceService.convertValueForColumn(rawScore: clamped, rawText: "", unit: draft?.actions[index].rawUnit, column: colDesc)
                draft?.actions[index].formattedScaleValue = conv.formattedText
            }
        } else {
            draft?.actions[index].score = nil
            draft?.actions[index].formattedScaleValue = nil
        }
        if let updated = draft?.actions[index] {
            draft?.actions[index].isSelected = updated.isReadyToApply
        }
    }

    /// Títulos de criterios de las rúbricas y plantillas cargadas, para que el dictado los reconozca mejor.
    private var criteriaVocabulary: [String] {
        Array(Set(criteriaInstruments.values.flatMap { $0.criteria.map(\.title) })).filter { $0.count <= 60 }
    }

    private func showsCriteriaEditor(for action: CourtVoiceProposedAction) -> Bool {
        guard let columnId = action.columnId else { return false }
        return action.criteriaColumnId == columnId && action.criterionProposals != nil
    }

    private func criteriaSuggestionLabel(count: Int, title: String) -> some View {
        Label {
            Text(count == 1 ? "Encaja con 1 criterio de «\(title)»" : "Encaja con \(count) criterios de «\(title)»")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "sparkles").foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private func criteriaSuggestionButtons(index: Int) -> some View {
        Button("Ahora no") { dismissCriteriaSuggestion(at: index) }
            .buttonStyle(.borderless)
        Button("Evaluar con rúbrica") { convertObservationToEvaluation(at: index) }
            .buttonStyle(.borderedProminent)
    }

    private func chooseCriterionLevel(actionId: String, criterionId: String, levelId: String?) {
        guard let index = draft?.actions.firstIndex(where: { $0.id == actionId }),
              let criterionIndex = draft?.actions[index].criterionProposals?.firstIndex(where: { $0.id == criterionId }) else { return }
        draft?.actions[index].criterionProposals?[criterionIndex].chosenLevelId = levelId
        if let updated = draft?.actions[index] {
            draft?.actions[index].isSelected = updated.isReadyToApply
        }
    }

    private func dismissCriteriaSuggestion(at index: Int) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].criterionProposals = nil
        draft?.actions[index].criteriaColumnId = nil
        draft?.actions[index].criteriaColumnTitle = nil
    }

    /// Crea una evaluación con los criterios sugeridos justo debajo y conserva la observación.
    private func convertObservationToEvaluation(at index: Int) {
        guard let source = draft?.actions[index],
              let columnId = source.criteriaColumnId,
              let proposals = source.criterionProposals else { return }
        var evaluation = CourtVoiceProposedAction(
            kind: .quickEvaluation,
            studentId: source.studentId,
            studentName: source.studentName,
            studentMention: source.studentMention,
            studentCandidates: source.studentCandidates,
            columnId: columnId,
            columnTitle: source.criteriaColumnTitle,
            sourceExcerpt: source.sourceExcerpt.isEmpty ? source.note : source.sourceExcerpt,
            resolutionReason: "Evaluación creada desde la observación",
            confidence: source.confidence
        )
        evaluation.criterionProposals = proposals
        evaluation.criteriaColumnId = columnId
        evaluation.isSelected = evaluation.isReadyToApply
        dismissCriteriaSuggestion(at: index)
        draft?.actions.insert(evaluation, at: index + 1)
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: "Evaluación con rúbrica añadida. Se conserva la observación.")
        #endif
    }

    /// Recalcula los criterios cuando el docente cambia de instrumento en la tarjeta.
    private func refreshCriteria(at index: Int) {
        guard let action = draft?.actions[index] else { return }
        if let columnId = action.columnId, let instrument = criteriaInstruments[columnId] {
            draft?.actions[index].criterionProposals = CourtVoiceCriteriaMatcher.match(
                text: CourtVoiceCriteriaMatcher.evidenceText(for: action),
                instrument: instrument
            )
            draft?.actions[index].criteriaColumnId = columnId
        } else {
            draft?.actions[index].criterionProposals = nil
            draft?.actions[index].criteriaColumnId = nil
        }
        draft?.actions[index].criteriaColumnTitle = nil
    }

    private func isStructuredColumn(_ columnId: String?) -> Bool {
        guard let columnId else { return false }
        return evaluableColumns.first(where: { $0.id == columnId })?.inputKind.isStructuredInstrument ?? false
    }

    private func updateDeliveryStatus(at index: Int, status: CourtVoiceDeliveryStatus?) {
        guard draft?.actions.indices.contains(index) == true else { return }
        draft?.actions[index].score = nil
        draft?.actions[index].formattedScaleValue = status?.rawValue
        draft?.actions[index].deliveryRawScore = status.map { $0 == .completed ? 10.0 : 0.0 }
        if let updated = draft?.actions[index] {
            draft?.actions[index].isSelected = updated.isReadyToApply
        }
    }

    private func updateColumn(at index: Int, columnId: String?) {
        guard draft?.actions.indices.contains(index) == true else { return }
        let col = evaluableColumns.first(where: { $0.id == columnId })
        draft?.actions[index].columnId = columnId
        draft?.actions[index].columnTitle = col?.title
        if let classId = selectedClassId,
           let columnId,
           let mention = draft?.actions[index].columnMention,
           !mention.isEmpty {
            CourtVoiceAliasStore.learnColumnAlias(mention: mention, columnId: columnId, classId: classId)
        }
        refreshCriteria(at: index)
        if let colDesc = buildColumnDescriptors().first(where: { $0.id == columnId }),
           let action = draft?.actions[index] {
            // Si lo dictado fue una entrega, se reconvierte desde ella (no desde una nota) al cambiar de columna.
            let isDelivery = action.deliveryRawScore != nil
            let rawScore = isDelivery ? action.deliveryRawScore : action.score
            if rawScore != nil || CourtVoiceDeliveryStatus.from(action.formattedScaleValue) != nil {
                let conv = AppleFoundationCourtVoiceService.convertValueForColumn(
                    rawScore: rawScore,
                    rawText: isDelivery ? action.sourceExcerpt : action.note,
                    unit: action.rawUnit,
                    column: colDesc,
                    isDeliveryStatement: isDelivery
                )
                draft?.actions[index].score = conv.numericScore
                draft?.actions[index].formattedScaleValue = conv.formattedText
            }
        }
        if let updated = draft?.actions[index] {
            draft?.actions[index].isSelected = updated.isReadyToApply
        }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

