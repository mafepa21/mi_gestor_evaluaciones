import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import QuickLook
import MiGestorKit

enum SessionJournalEFVisibility {
    case always
    case contextual
    case hidden
}

enum PlannerJournalPresentationMode {
    case minimal
    case full
}

struct PlannerJournalDetailPane: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var efVisibility: SessionJournalEFVisibility = .always
    var presentationMode: PlannerJournalPresentationMode = .minimal
    @StateObject private var recorder = PlannerAudioRecorder()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isAdvancedReflectionPresented = false

    var body: some View {
        Group {
            if let session = vm.selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: EvaluationDesign.cardSpacing) {
                        SessionJournalQuickPulseCard(vm: vm)
                        SessionJournalQuickObservationCard(vm: vm)
                        SessionJournalQuickNextStepCard(vm: vm)

                        if presentationMode == .full {
                            advancedJournalContent(for: session)
                        } else {
                            DisclosureGroup(isExpanded: $isAdvancedReflectionPresented) {
                                VStack(alignment: .leading, spacing: EvaluationDesign.cardSpacing) {
                                    advancedJournalContent(for: session)
                                }
                                .padding(.top, 12)
                            } label: {
                                HStack {
                                    Label("Reflexión avanzada", systemImage: "slider.horizontal.3")
                                        .font(.headline.weight(.semibold))
                                    Spacer()
                                    Text("Opcional")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            .plannerGlassPanel(.content, cornerRadius: 16)
                        }
                    }
                    .padding(EvaluationDesign.screenPadding)
                }
                .appOnChange(of: vm.journalDraft) { _ in
                    vm.scheduleAutosave()
                }
                .appOnChange(of: selectedPhoto) { item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let url = persistMediaData(data, ext: "jpg") {
                            vm.journalDraft.media.append(
                                PlannerJournalDraftMedia(type: .photo, uri: url.absoluteString, caption: "Foto de sesión")
                            )
                        }
                        selectedPhoto = nil
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selecciona una sesión")
                        .font(.title2.weight(.black))
                    Text("La ficha de diario aparecerá aquí con edición inline, métricas y multimedia.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(EvaluationDesign.screenPadding)
            }
        }
    }

    @ViewBuilder
    private func advancedJournalContent(for session: PlanningSession) -> some View {
        SessionJournalHeaderCard(vm: vm, session: session)
        SessionJournalDevelopmentCard(vm: vm)
        SessionJournalEvaluationCard(vm: vm)
        SessionJournalClosingCard(vm: vm)
        JournalIndividualNotesList(vm: vm)
        JournalActionBar(vm: vm)
        JournalMediaDock(
            vm: vm,
            recorder: recorder,
            selectedPhoto: $selectedPhoto
        )
        if shouldShowEFCard(for: session) {
            SessionJournalEFCard(vm: vm)
        }
    }

    private func shouldShowEFCard(for session: PlanningSession) -> Bool {
        switch efVisibility {
        case .always:
            return true
        case .hidden:
            return false
        case .contextual:
            if vm.journalDraft.intensityScore > 0
                || vm.journalDraft.warmupMinutes > 0
                || vm.journalDraft.mainPartMinutes > 0
                || vm.journalDraft.cooldownMinutes > 0 {
                return true
            }

            let efTexts = [
                vm.journalDraft.weatherText,
                vm.journalDraft.usedSpace,
                vm.journalDraft.materialUsedText,
                vm.journalDraft.physicalIncidentsText,
                vm.journalDraft.injuriesText,
                vm.journalDraft.unequippedStudentsText,
                vm.journalDraft.stationObservationsText,
                session.groupName,
                session.teachingUnitName,
                session.objectives,
                session.activities,
                session.evaluation
            ]
                .joined(separator: " ")
                .lowercased()

            let efSignals = [
                "educación física",
                "educacion fisica",
                "ef",
                "calentamiento",
                "vuelta a la calma",
                "material",
                "pista",
                "circuito",
                "motriz"
            ]

            return efSignals.contains { efTexts.contains($0) }
        }
    }

    private func persistMediaData(_ data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("planner_media_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private struct SessionJournalHeaderCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession

    var body: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 14) {
                EvaluationSectionTitle(
                    eyebrow: "Diario",
                    title: session.teachingUnitName,
                    subtitle: "\(session.groupName) · \(vm.timeLabel(for: Int(session.period)))"
                )

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    quickField("Fecha", value: vm.dateRangeLabel)
                    quickField("Grupo", value: session.groupName)
                    quickField("Hora", value: vm.timeLabel(for: Int(session.period)))
                    editableField("Profesor", text: $vm.journalDraft.teacherName)
                    editableField("Espacio", text: $vm.journalDraft.scheduledSpace)
                    editableField("Unidad / SA", text: $vm.journalDraft.unitLabel)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Objetivo previsto")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Pase y juego sin balón", text: $vm.journalDraft.objectivePlanned)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }

    private func quickField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Sin dato" : value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editableField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalQuickPulseCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSectionTitle(
                    eyebrow: "10 segundos",
                    title: "Pulso de la sesión",
                    subtitle: "Cierra lo esencial sin convertir el diario en un informe."
                )

                HStack(spacing: 8) {
                    pulseButton("Muy bien", icon: "checkmark.circle.fill", climate: 5, usefulTime: 5, difficulty: 1, tint: EvaluationDesign.success)
                    pulseButton("Normal", icon: "circle.lefthalf.filled", climate: 3, usefulTime: 3, difficulty: 3, tint: EvaluationDesign.accent)
                    pulseButton("Revisar", icon: "exclamationmark.triangle.fill", climate: 2, usefulTime: 2, difficulty: 5, tint: IOSAppStyle.warning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Participación")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        participationButton("Baja", value: 2)
                        participationButton("Media", value: 3)
                        participationButton("Alta", value: 5)
                    }
                }
            }
        }
    }

    private func pulseButton(_ title: String, icon: String, climate: Int, usefulTime: Int, difficulty: Int, tint: Color) -> some View {
        let isSelected = vm.journalDraft.climateScore == climate
            && vm.journalDraft.usefulTimeScore == usefulTime
            && vm.journalDraft.perceivedDifficultyScore == difficulty
        return Button {
            vm.journalDraft.climateScore = climate
            vm.journalDraft.usefulTimeScore = usefulTime
            vm.journalDraft.perceivedDifficultyScore = difficulty
            if title == "Revisar", !vm.journalDraft.incidentTags.contains("Revisión") {
                vm.journalDraft.incidentTags.append("Revisión")
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : tint)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tint : tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
        )
    }

    private func participationButton(_ title: String, value: Int) -> some View {
        let isSelected = vm.journalDraft.participationScore == value
        return Button {
            vm.journalDraft.participationScore = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : EvaluationDesign.accent)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? EvaluationDesign.accent : EvaluationDesign.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.accent.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
        )
    }
}

private struct SessionJournalQuickObservationCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "30 segundos",
            title: "Observación rápida",
            subtitle: "Una nota breve basta para mantener trazabilidad diaria."
        ) {
            TextField("Han necesitado más tiempo para la actividad 2…", text: $vm.journalDraft.groupObservations, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalQuickNextStepCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Siguiente sesión",
            title: "Próximo paso",
            subtitle: "Una decisión breve para no perder continuidad."
        ) {
            TextField("Repetir actividad 2, avanzar, adaptar material…", text: $vm.journalDraft.nextStepText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalDevelopmentCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Reflexión completa",
            title: "Lo planificado y lo realizado",
            subtitle: "Completar solo cuando haga falta más detalle pedagógico."
        ) {
            JournalTextBlock(title: "Qué estaba planificado", text: $vm.journalDraft.plannedText)
            JournalTextBlock(title: "Qué se ha hecho realmente", text: $vm.journalDraft.actualText)
            JournalTextBlock(title: "Nivel de consecución", text: $vm.journalDraft.attainmentText)
            JournalTextBlock(title: "Adaptaciones realizadas", text: $vm.journalDraft.adaptationsText)
            JournalTextBlock(title: "Incidencias", text: $vm.journalDraft.incidentsText)
            JournalTextBlock(title: "Observaciones del grupo", text: $vm.journalDraft.groupObservations)

            JournalQuickChips(
                title: "Incidencias",
                options: ["Lesión", "Equipación", "Material", "Clima", "Espacio", "Tiempo"],
                selected: $vm.journalDraft.incidentTags
            )
        }
    }
}

private struct SessionJournalEvaluationCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Evaluación",
            title: "Cómo ha funcionado la sesión",
            subtitle: "Valora rápidamente el clima, la participación y el tiempo útil."
        ) {
            JournalMetricStrip(title: "Clima de aula", value: $vm.journalDraft.climateScore)
            JournalMetricStrip(title: "Participación", value: $vm.journalDraft.participationScore)
            JournalMetricStrip(title: "Tiempo útil", value: $vm.journalDraft.usefulTimeScore)
            JournalMetricStrip(title: "Dificultad percibida", value: $vm.journalDraft.perceivedDifficultyScore)

            VStack(alignment: .leading, spacing: 8) {
                Text("Decisión pedagógica")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    decisionButton("Repetir", value: .repeatSession)
                    decisionButton("Reforzar", value: .reinforce)
                    decisionButton("Avanzar", value: .advance)
                }
            }
        }
    }

    private func decisionButton(_ title: String, value: SessionJournalDecision) -> some View {
        Button(title) {
            vm.journalDraft.pedagogicalDecision = value
        }
        .buttonStyle(.bordered)
        .tint(vm.journalDraft.pedagogicalDecision == value ? EvaluationDesign.accent : .gray)
    }
}

private struct SessionJournalClosingCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Cierre",
            title: "Qué queda pendiente",
            subtitle: "Prepara la siguiente sesión y deja trazabilidad docente."
        ) {
            JournalTextBlock(title: "Tareas pendientes", text: $vm.journalDraft.pendingTasksText)
            JournalTextBlock(title: "Material a preparar", text: $vm.journalDraft.materialToPrepareText)
            JournalTextBlock(title: "Alumnado a revisar", text: $vm.journalDraft.studentsToReviewText)
            JournalTextBlock(title: "Comunicación con familias", text: $vm.journalDraft.familyCommunicationText)
            JournalTextBlock(title: "Siguiente paso", text: $vm.journalDraft.nextStepText)

            VStack(alignment: .leading, spacing: 8) {
                Text("Próxima acción")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    actionChip("Repetir tarea 2")
                    actionChip("Adaptar a Pablo")
                    actionChip("Llevar más conos")
                }
            }
        }
    }

    private func actionChip(_ title: String) -> some View {
        Button(title) {
            if !vm.journalDraft.actions.contains(where: { $0.title == title }) {
                vm.journalDraft.actions.append(PlannerJournalDraftAction(title: title))
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct SessionJournalEFCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "EF",
            title: "Bloque específico de Educación Física",
            subtitle: "Meteorología, material, lesiones e intensidad en una misma ficha."
        ) {
            editableGridField("Meteorología", text: $vm.journalDraft.weatherText)
            editableGridField("Espacio usado", text: $vm.journalDraft.usedSpace)
            editableGridField("Material empleado", text: $vm.journalDraft.materialUsedText)
            editableGridField("Incidencias físicas", text: $vm.journalDraft.physicalIncidentsText)
            editableGridField("Lesiones / molestias", text: $vm.journalDraft.injuriesText)
            editableGridField("Sin equipación", text: $vm.journalDraft.unequippedStudentsText)

            JournalMetricStrip(title: "Intensidad percibida", value: $vm.journalDraft.intensityScore)

            HStack(spacing: 12) {
                minuteStepper("Calentamiento", value: $vm.journalDraft.warmupMinutes)
                minuteStepper("Parte principal", value: $vm.journalDraft.mainPartMinutes)
                minuteStepper("Vuelta a la calma", value: $vm.journalDraft.cooldownMinutes)
            }

            JournalTextBlock(title: "Observaciones motrices por grupos o estaciones", text: $vm.journalDraft.stationObservationsText)
        }
    }

    private func editableGridField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private func minuteStepper(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Stepper("\(value.wrappedValue) min", value: value, in: 0...90, step: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalIndividualNotesList: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Alumnado",
            title: "Observaciones individuales",
            subtitle: "Notas breves por alumno con intención de seguimiento."
        ) {
            ForEach(vm.journalDraft.notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Alumno", text: noteBinding(note.id, \.studentName))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Tag", text: noteBinding(note.id, \.tag))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(role: .destructive) {
                            vm.journalDraft.notes.removeAll { $0.id == note.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Observación", text: noteBinding(note.id, \.note), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.vertical, 4)
            }

            Button {
                vm.journalDraft.notes.append(PlannerJournalDraftNote())
            } label: {
                Label("Añadir observación individual", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func noteBinding(_ id: UUID, _ keyPath: WritableKeyPath<PlannerJournalDraftNote, String>) -> Binding<String> {
        Binding(
            get: {
                vm.journalDraft.notes.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = vm.journalDraft.notes.firstIndex(where: { $0.id == id }) else { return }
                vm.journalDraft.notes[index][keyPath: keyPath] = newValue
            }
        )
    }
}

private struct JournalMediaDock: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @ObservedObject var recorder: PlannerAudioRecorder
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Multimedia",
            title: "Fotos, audio y transcripción",
            subtitle: "Captura evidencia ligera sin salir del diario."
        ) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Añadir foto", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                Button {
                    if recorder.isRecording {
                        if let url = recorder.stop() {
                            vm.journalDraft.media.append(
                                PlannerJournalDraftMedia(type: .audio, uri: url.absoluteString, caption: "Audio de sesión")
                            )
                        }
                    } else {
                        recorder.start()
                    }
                } label: {
                    Label(recorder.isRecording ? "Detener audio" : "Grabar audio", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    vm.journalDraft.media.append(
                        PlannerJournalDraftMedia(type: .transcript, uri: "", transcript: "", caption: "Dictado / transcripción")
                    )
                } label: {
                    Label("Añadir dictado", systemImage: "waveform.and.mic")
                }
                .buttonStyle(.bordered)
            }

            ForEach(vm.journalDraft.media, id: \.id) { media in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(media.type.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            vm.journalDraft.media.removeAll { $0.id == media.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Título", text: mediaBinding(media.id, \.caption))
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                    if !media.uri.isEmpty {
                        Text(media.uri)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    TextField("Transcripción editable", text: mediaBinding(media.id, \.transcript), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func mediaBinding(_ id: UUID, _ keyPath: WritableKeyPath<PlannerJournalDraftMedia, String>) -> Binding<String> {
        Binding(
            get: {
                vm.journalDraft.media.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = vm.journalDraft.media.firstIndex(where: { $0.id == id }) else { return }
                vm.journalDraft.media[index][keyPath: keyPath] = newValue
            }
        )
    }
}

private struct JournalActionBar: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Acciones",
            title: "Integraciones y seguimiento",
            subtitle: "Lanza acciones explícitas y deja trazabilidad de lo ya trasladado."
        ) {
            HStack(spacing: 10) {
                Button("Enviar observación al cuaderno") {
                    vm.appendTraceLink(type: .notebook, label: "Pendiente de trasladar al cuaderno")
                }
                .buttonStyle(.bordered)

                Button("Registrar incidencia") {
                    Task { await vm.appendIncidentLink() }
                }
                .buttonStyle(.bordered)

                Button("Reflejar asistencia") {
                    vm.appendTraceLink(type: .attendance, label: "Asistencia / participación reflejada")
                }
                .buttonStyle(.bordered)

                Button("Seguimiento familias") {
                    vm.appendTraceLink(type: .family, label: "Seguimiento familiar marcado")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                saveStateLabel
                    .font(.caption)
                    .foregroundStyle(saveStateColor)
                Spacer()
                Button("Guardar ahora") { Task { await vm.saveJournal() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.journalSaveState == .saving)
            }

            ForEach(vm.journalDraft.links) { link in
                HStack {
                    Text(link.type.title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(link.label)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var saveStateLabel: Text {
        switch vm.journalSaveState {
        case .idle:
            return Text("Usa el dictado nativo del teclado en cualquier campo de texto para capturar voz.")
        case .saving:
            return Text("Guardando...")
        case .saved(let date):
            let seconds = max(0, Int(Date().timeIntervalSince(date)))
            return Text(seconds < 3 ? "Guardado ahora" : "Guardado hace \(seconds) s")
        case .failed(let message):
            return Text("Error al guardar: \(message)")
        }
    }

    private var saveStateColor: Color {
        switch vm.journalSaveState {
        case .failed:
            return .red
        default:
            return .secondary
        }
    }
}

private struct SessionJournalSectionCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let content: Content

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSectionTitle(eyebrow: eyebrow, title: title, subtitle: subtitle)
                content
            }
        }
    }
}

private struct JournalTextBlock: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct JournalMetricStrip: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { item in
                    Button("\(item)") { value = item }
                        .buttonStyle(.bordered)
                        .tint(value == item ? EvaluationDesign.accent : .gray)
                }
            }
        }
    }
}

private struct JournalQuickChips: View {
    let title: String
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        if selected.contains(option) {
                            selected.removeAll { $0 == option }
                        } else {
                            selected.append(option)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected.contains(option) ? EvaluationDesign.danger : .gray)
                }
            }
        }
    }
}

struct PlannerInstrumentCompactPicker: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var expandedGroupTitles: Set<String> = []

    private var summaryText: String {
        let availableIds = Set(vm.composerAvailableInstruments.map(\.id))
        let count = vm.composerDraft.selectedInstrumentIds.intersection(availableIds).count
        if count == 1 { return "1 seleccionado" }
        return "\(count) seleccionados"
    }

    private var rubricCount: Int {
        vm.composerAvailableInstruments.filter { $0.kind == .rubric }.count
    }

    private var evaluationCount: Int {
        vm.composerAvailableInstruments.filter { $0.kind != .rubric }.count
    }

    private var recommendedCount: Int {
        vm.composerAvailableInstruments.filter(\.isRecommendedForCurrentSA).count
    }

    private var groupedInstruments: [PlannerInstrumentCompactGroup] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = vm.composerAvailableInstruments.filter { instrument in
            guard !trimmedSearch.isEmpty else { return true }
            let haystack = [
                safeDisplayText(instrument.title, fallback: "Instrumento"),
                safeDisplayText(instrument.subtitle, fallback: instrument.kind == .rubric ? "Rúbrica" : "Evaluación"),
                safeDisplayText(instrument.groupTitle, fallback: "Sin situación asignada"),
                instrument.kind == .rubric ? "Rúbrica" : "Evaluación"
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(trimmedSearch)
        }

        var groups: [PlannerInstrumentCompactGroup] = []
        let recommended = filtered
            .filter(\.isRecommendedForCurrentSA)
            .sorted(by: instrumentSort)
        if !recommended.isEmpty {
            groups.append(PlannerInstrumentCompactGroup(title: "Recomendados para esta SA", items: recommended))
        }

        let remaining = filtered.filter { !$0.isRecommendedForCurrentSA }
        let grouped = Dictionary(grouping: remaining) { instrument in
            safeDisplayText(instrument.groupTitle, fallback: "Sin situación asignada")
        }
        let sortedTitles = grouped.keys.sorted { lhs, rhs in
            if lhs == "Sin situación asignada" { return false }
            if rhs == "Sin situación asignada" { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        groups.append(contentsOf: sortedTitles.map { title in
            PlannerInstrumentCompactGroup(title: title, items: (grouped[title] ?? []).sorted(by: instrumentSort))
        })
        return groups
    }

    private var recommendedGroupTitles: Set<String> {
        Set(groupedInstruments.filter { group in
            group.items.contains(where: \.isRecommendedForCurrentSA)
        }.map(\.title))
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(uiFeatureFlags.interactionAnimation) {
                    isExpanded.toggle()
                }
                AppleInteractionFeedback.play(.lightImpact)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(EvaluationDesign.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Instrumentos enlazados")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(summaryText) · Ver instrumentos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Buscar rúbrica o evaluación", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    if groupedInstruments.isEmpty {
                        Text("No hay instrumentos que coincidan con la búsqueda.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 8) {
                            EvaluationChip(label: "\(recommendedCount) criterios SA", systemImage: "scope", active: recommendedCount > 0, tint: EvaluationDesign.accent)
                            EvaluationChip(label: "\(rubricCount) rúbricas", systemImage: "checklist", active: rubricCount > 0, tint: EvaluationDesign.success)
                            EvaluationChip(label: "\(evaluationCount) evaluaciones", systemImage: "chart.bar.doc.horizontal", active: evaluationCount > 0, tint: EvaluationDesign.danger)
                        }

                        HStack(spacing: 16) {
                            Button("Expandir recomendadas") {
                                withAnimation(uiFeatureFlags.interactionAnimation) {
                                    expandedGroupTitles = recommendedGroupTitles
                                }
                                AppleInteractionFeedback.play(.lightImpact)
                            }
                            .buttonStyle(.borderless)

                            Button("Contraer todo") {
                                withAnimation(uiFeatureFlags.interactionAnimation) {
                                    expandedGroupTitles.removeAll()
                                }
                            }
                            .buttonStyle(.borderless)

                            Spacer()
                        }
                        .font(.caption.weight(.semibold))

                        ForEach(groupedInstruments) { group in
                            PlannerInstrumentDisclosureSection(
                                title: safeDisplayText(group.title, fallback: "Sin situación asignada"),
                                items: group.items,
                                isExpanded: Binding(
                                    get: {
                                        !trimmedSearchText.isEmpty || expandedGroupTitles.contains(group.title)
                                    },
                                    set: { newValue in
                                        if newValue {
                                            expandedGroupTitles.insert(group.title)
                                        } else {
                                            expandedGroupTitles.remove(group.title)
                                        }
                                    }
                                ),
                                selectedIds: vm.composerDraft.selectedInstrumentIds,
                                toggle: { instrument in
                                    vm.toggleComposerInstrument(instrument.id)
                                    AppleInteractionFeedback.play(.selection)
                                }
                            )
                        }
                    }
                }
                .padding(16)
                .plannerGlassPanel(.content, cornerRadius: 14)
                .transition(uiFeatureFlags.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .task {
            if expandedGroupTitles.isEmpty {
                expandedGroupTitles = recommendedGroupTitles
            }
        }
        .appOnChange(of: vm.composerAvailableInstruments) { _ in
            if expandedGroupTitles.isEmpty {
                expandedGroupTitles = recommendedGroupTitles
            }
        }
    }

    private func instrumentSort(_ lhs: PlannerAssessmentInstrument, _ rhs: PlannerAssessmentInstrument) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .rubric }
        return safeDisplayText(lhs.title, fallback: "Instrumento")
            .localizedCaseInsensitiveCompare(safeDisplayText(rhs.title, fallback: "Instrumento")) == .orderedAscending
    }

    private func safeDisplayText(_ value: String, fallback: String) -> String {
        plannerSafeDisplayText(value, fallback: fallback)
    }
}

private struct PlannerInstrumentCompactGroup: Identifiable {
    let title: String
    let items: [PlannerAssessmentInstrument]

    var id: String { title }
}

private struct PlannerInstrumentDisclosureSection: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    let title: String
    let items: [PlannerAssessmentInstrument]
    @Binding var isExpanded: Bool
    let selectedIds: Set<String>
    let toggle: (PlannerAssessmentInstrument) -> Void

    private var selectedCount: Int {
        items.filter { selectedIds.contains($0.id) }.count
    }

    private var recommendedCount: Int {
        items.filter(\.isRecommendedForCurrentSA).count
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(uiFeatureFlags.interactionAnimation) {
                    isExpanded.toggle()
                }
                AppleInteractionFeedback.play(.lightImpact)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plannerSafeDisplayText(title, fallback: "Sin situación asignada"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .textCase(.uppercase)
                            .lineLimit(1)

                        Text(sectionSubtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedCount > 0 {
                        Text("\(selectedCount) seleccionados")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(EvaluationDesign.accent.opacity(0.12), in: Capsule())
                    }

                    Text("\(items.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    isExpanded ? EvaluationDesign.surfaceSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { instrument in
                        PlannerInstrumentCompactRow(
                            instrument: instrument,
                            isSelected: selectedIds.contains(instrument.id),
                            toggle: { toggle(instrument) }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .transition(uiFeatureFlags.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .plannerGlassPanel(.control, cornerRadius: 12)
        .shadow(color: EvaluationDesign.shadow, radius: 12, x: 0, y: 4)
    }

    private var sectionSubtitle: String {
        if selectedCount > 0 {
            return "\(selectedCount) de \(items.count) seleccionados"
        }
        if recommendedCount > 0 {
            return "\(recommendedCount) recomendados para esta SA"
        }
        return "\(items.count) instrumentos"
    }
}

private struct PlannerInstrumentCompactRow: View {
    let instrument: PlannerAssessmentInstrument
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? EvaluationDesign.accent : .secondary)
                    .font(.callout.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(safeTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if instrument.isRecommendedForCurrentSA {
                            Text("SA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EvaluationDesign.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EvaluationDesign.accent.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(safeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(instrument.kind == .rubric ? "Rúbrica" : "Evaluación")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? EvaluationDesign.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var safeTitle: String {
        plannerSafeDisplayText(instrument.title, fallback: "Instrumento")
    }

    private var safeSubtitle: String {
        plannerSafeDisplayText(instrument.subtitle, fallback: instrument.kind == .rubric ? "Rúbrica" : "Evaluación")
    }
}

private func plannerSafeDisplayText(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let upper = trimmed.uppercased()

    if trimmed.isEmpty ||
        upper.contains("EVALUATION(") ||
        upper.contains("CLASSID=") ||
        upper.contains("RUBRICID=") ||
        upper.contains("TRACE=") ||
        upper.contains("AUDITTRACE") ||
        upper.contains("UPDATEDAT=") ||
        upper.contains("CREATEDAT=") {
        return fallback
    }

    return trimmed
}


private extension SessionJournalMediaType {
    var title: String {
        switch self {
        case .photo: return "Foto"
        case .audio: return "Audio"
        case .transcript: return "Dictado"
        default: return "Media"
        }
    }
}

private extension SessionJournalLinkType {
    var title: String {
        switch self {
        case .notebook: return "Cuaderno"
        case .attendance: return "Asistencia"
        case .incident: return "Incidencia"
        case .family: return "Familias"
        default: return "Enlace"
        }
    }
}
