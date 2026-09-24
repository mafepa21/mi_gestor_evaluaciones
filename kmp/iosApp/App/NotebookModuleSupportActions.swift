import SwiftUI
import PhotosUI
import MiGestorKit

extension NotebookModuleView {
    func syncInspectorDraft() {
        guard let selection = inspectorSelection,
              let data = bridge.notebookState as? NotebookUiStateData,
              let item = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }) else {
            inspectorState.resetDrafts()
            return
        }
        let persisted = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })
        inspectorNoteDraft = persisted?.annotation?.note ?? ""
        inspectorIconDraft = persisted?.annotation?.icon ?? persisted?.iconValue ?? ""
        inspectorAttachmentUris = persisted?.annotation?.attachmentUris ?? []
    }

    func refreshNotebookSignals() async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        async let attendanceResult = try? bridge.attendanceRecords(for: classId, on: Date())
        async let incidentsResult = try? bridge.incidents(for: classId)
        async let supportMeasureResult = try? bridge.activeSupportMeasureStudentIds()

        let attendance = await attendanceResult ?? []
        let incidents = await incidentsResult ?? []
        let supportMeasureStudentIds = await supportMeasureResult ?? []

        await MainActor.run {
            todayAttendanceByStudentId = Dictionary(
                attendance.map { ($0.studentId, $0.status) },
                uniquingKeysWith: { _, latest in latest }
            )
            let counts = Dictionary(grouping: incidents.compactMap { $0.studentId?.int64Value }, by: { $0 }).mapValues(\.count)
            incidentCountByStudentId = counts
            activeSupportMeasureStudentIds = supportMeasureStudentIds
        }
    }

    func attendanceStatusText(for studentId: Int64) -> String {
        todayAttendanceByStudentId[studentId] ?? "Sin pasar"
    }

    func isStudentInjured(_ student: Student) -> Bool {
        localInjuryStatuses[student.id] ?? student.isInjured
    }

    func markAttendance(for studentId: Int64, status: String) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        let canonicalStatus = NotebookAttendanceStatus.canonical(status)
        do {
            try await bridge.saveAttendance(studentId: studentId, classId: classId, on: Date(), status: canonicalStatus)
            await refreshNotebookSignals()
        } catch {
        }
    }

    @MainActor
    func toggleStudentInjuryStatus(_ student: Student) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        let previousValue = isStudentInjured(student)
        let newValue = !previousValue
        localInjuryStatuses[student.id] = newValue
        reloadNotebookRow(student.id)
        do {
            try await bridge.updateStudentInjuryStatus(
                studentId: student.id,
                isInjured: newValue,
                classId: classId
            )
            await bridge.selectStudentsClass(classId: classId)
            reloadNotebookRow(student.id)
            showToast(newValue ? "Alumno marcado con lesión" : "Lesión retirada")
        } catch {
            localInjuryStatuses[student.id] = previousValue
            reloadNotebookRow(student.id)
            showToast("No se pudo actualizar la lesión", style: .warning)
        }
    }

    func requestMarkAllVisibleStudentsPresent(data: NotebookUiStateData) {
        let visibleRows = filteredRows(data: data)
        guard !visibleRows.isEmpty else { return }
        if visibleRows.count > 5 {
            isMarkAllPresentDialogPresented = true
        } else {
            markAllVisibleStudentsPresent(data: data)
        }
    }

    func markAllVisibleStudentsPresent(data: NotebookUiStateData) {
        let visibleRows = filteredRows(data: data)
        guard !visibleRows.isEmpty,
              let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        Task {
            let drafts = visibleRows.map { row in
                KmpBridge.AttendanceDraft(
                    studentId: row.student.id,
                    classId: classId,
                    date: Date(),
                    status: NotebookAttendanceStatus.present,
                    note: "",
                    hasIncident: false,
                    followUpRequired: nil,
                    sessionId: nil
                )
            }
            do {
                try await bridge.saveAttendanceBatch(records: drafts)
                await refreshNotebookSignals()
                await MainActor.run {
                    showToast("\(visibleRows.count) alumnos marcados como presentes")
                }
            } catch {
                await MainActor.run {
                    showToast("No se pudo marcar asistencia", style: .warning)
                }
            }
        }
    }

    func requestFillColumnFromSelectedCell(data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data) else {
            showToast("Selecciona una celda para rellenar la columna", style: .warning)
            return
        }
        guard isToolbarEditableCellColumn(selected.column) else {
            showToast("Esta columna se edita desde su acción específica", style: .warning)
            return
        }
        let otherRowsCount = filteredRows(data: data).filter { $0.student.id != selected.selection.studentId }.count
        guard otherRowsCount > 0 else {
            showToast("No hay más alumnos visibles para rellenar", style: .warning)
            return
        }
        if otherRowsCount > 5 {
            isFillColumnDialogPresented = true
        } else {
            fillColumnFromSelectedCell(data: data)
        }
    }

    func fillColumnFromSelectedCell(data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        let column = selected.column
        let value = displayValue(for: selected.row, column: column)
        let targetRows = filteredRows(data: data).filter { $0.student.id != selected.selection.studentId }
        guard !targetRows.isEmpty else { return }

        var filledCount = 0
        for row in targetRows {
            let previousValue = displayValue(for: row, column: column)
            guard previousValue != value else { continue }
            recordCellUndo(
                studentId: row.student.id,
                column: column,
                previousValue: previousValue,
                previousDisplayLabel: nil
            )
            bridge.saveColumnGrade(studentId: row.student.id, column: column, value: value)
            reloadNotebookRow(row.student.id)
            filledCount += 1
        }
        showToast(filledCount > 0 ? "Rellenadas \(filledCount) celdas" : "Todas las celdas ya tenían ese valor")
    }

    func recordCellUndo(studentId: Int64, column: NotebookColumnDefinition, previousValue: String, previousDisplayLabel: String?) {
        undoStack.append(
            NotebookCellUndoEntry(
                studentId: studentId,
                column: column,
                previousValue: previousValue,
                previousDisplayLabel: previousDisplayLabel
            )
        )
        if undoStack.count > 10 {
            undoStack.removeFirst(undoStack.count - 10)
        }
    }

    func undoLastCellChange() {
        guard let entry = undoStack.popLast() else {
            showToast("No hay cambios que deshacer", style: .warning)
            return
        }
        bridge.flushPendingColumnGradeSave(studentId: entry.studentId, columnId: entry.column.id)
        bridge.saveColumnGrade(studentId: entry.studentId, column: entry.column, value: entry.previousValue)
        reloadNotebookRow(entry.studentId)
        AppleInteractionFeedback.play(.success)
        withAnimation(uiFeatureFlags.animation(.spring(response: 0.18, dampingFraction: 0.9))) {
            inspectorSelection = NotebookInspectorSelection(studentId: entry.studentId, columnId: entry.column.id)
            focusedCellId = nil
            activeChoiceCellId = nil
        }
        let label = entry.previousDisplayLabel ?? entry.previousValue
        showToast(label.isEmpty ? "Cambio deshecho" : "Cambio deshecho: \(label)")
    }

    func createFollowUp(for student: Student) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        do {
            _ = try await bridge.createIncident(
                classId: classId,
                studentId: student.id,
                title: "Seguimiento desde plano",
                detail: "Marcado desde el plano de clase del cuaderno."
            )
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: classId,
                on: Date(),
                status: NotebookAttendanceStatus.canonical(todayAttendanceByStudentId[student.id] ?? NotebookAttendanceStatus.present),
                note: "Seguimiento abierto desde el plano.",
                hasIncident: true
            )
            await refreshNotebookSignals()
        } catch {
        }
    }

    func importSelectedAttachment(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value,
              let selection = inspectorSelection else { return }

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotebookEvidence", isDirectory: true)
            .appendingPathComponent("\(classId)", isDirectory: true)
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(selection.studentId)_\(selection.columnId)_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            await MainActor.run {
                inspectorAttachmentUris.append(url.path)
                selectedAttachmentPhoto = nil
            }
        } catch {
            await MainActor.run {
                selectedAttachmentPhoto = nil
            }
        }
    }

    func defaultSeatPositions(for rows: [NotebookTableRow]) -> [Int64: NotebookSeatPosition] {
        guard !rows.isEmpty else { return [:] }
        let columns = max(3, Int(ceil(sqrt(Double(rows.count)))))
        let horizontalStep = 0.76 / Double(max(columns - 1, 1))
        let verticalRows = Int(ceil(Double(rows.count) / Double(columns)))
        let verticalStep = 0.68 / Double(max(verticalRows - 1, 1))
        return Dictionary(uniqueKeysWithValues: rows.enumerated().map { index, item in
            let row = index / columns
            let column = index % columns
            let x = 0.12 + Double(column) * horizontalStep
            let y = 0.16 + Double(row) * verticalStep
            return (item.student.id, NotebookSeatPosition(x: x, y: y))
        })
    }

    func randomEligibleStudentId(from rows: [NotebookTableRow], data: NotebookUiStateData) -> Int64? {
        let presentRows = rows.filter { !attendanceStatusText(for: $0.student.id).localizedCaseInsensitiveContains("aus") }
        let eligibleRows = presentRows.isEmpty ? rows : presentRows
        guard !eligibleRows.isEmpty else { return nil }

        let participationColumns = data.sheet.columns.filter { $0.instrumentKind == .participation }
        guard !participationColumns.isEmpty else {
            return eligibleRows.map(\.student.id).randomElement()
        }

        // Aleatorio ponderado: prioriza a quienes tienen menos registros de participación.
        let weightedEntries = eligibleRows.map { row -> (studentId: Int64, weight: Double) in
            let recordCount = row.row.persistedCells.filter { cell in
                participationColumns.contains { $0.id == cell.columnId } &&
                    !(cell.textValue ?? cell.displayValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            return (row.student.id, 1.0 / Double(recordCount + 1))
        }

        let totalWeight = weightedEntries.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return eligibleRows.map(\.student.id).randomElement() }

        var pick = Double.random(in: 0..<totalWeight)
        for entry in weightedEntries {
            if pick < entry.weight { return entry.studentId }
            pick -= entry.weight
        }
        return weightedEntries.last?.studentId
    }

    func gradableSeatingColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        data.sheet.columns.filter { $0.type == .numeric && !$0.isLocked && $0.isVisibleInGrid }
    }

    func adjustSeatingGrade(studentId: Int64, column: NotebookColumnDefinition, delta: Double, data: NotebookUiStateData) {
        guard let row = filteredRows(data: data).first(where: { $0.student.id == studentId }) else { return }
        let currentText = displayValue(for: row, column: column)
        let current = Double(currentText.replacingOccurrences(of: ",", with: ".")) ?? 0
        var next = current + delta
        if column.inputKind == .numeric010 {
            next = min(10, max(0, next))
        }
        let rounded = (next * 100).rounded() / 100
        var formatted = String(format: "%.2f", rounded)
        while formatted.hasSuffix("0") { formatted.removeLast() }
        if formatted.hasSuffix(".") { formatted.removeLast() }

        recordCellUndo(studentId: studentId, column: column, previousValue: currentText, previousDisplayLabel: nil)
        bridge.saveColumnGrade(studentId: studentId, column: column, value: formatted)
        reloadNotebookRow(studentId)
        AppleInteractionFeedback.play(.selection)
    }

    func seatStorageKey() -> String? {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return nil }
        return "notebook.seating.\(classId).\(bridge.selectedNotebookTabId ?? "all")"
    }

    func persistSeatPositions() {
        guard let key = seatStorageKey(),
              let encoded = try? JSONEncoder().encode(seatPositions) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    func restoreSeatPositions() {
        guard let key = seatStorageKey() else {
            seatPositions = [:]
            return
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Int64: NotebookSeatPosition].self, from: data) {
            seatPositions = decoded
        } else if let data = bridge.notebookState as? NotebookUiStateData {
            seatPositions = defaultSeatPositions(for: filteredRows(data: data))
        } else {
            seatPositions = [:]
        }
    }

    func toggleVoiceGradeDictation(data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data), selected.column.type == .numeric else {
            showToast("Selecciona una celda numérica para dictar la nota", style: .warning)
            return
        }
        guard isToolbarEditableCellColumn(selected.column) else {
            showToast("Esta columna se edita desde su acción específica", style: .warning)
            return
        }
        voiceGradeDictationService.toggleListening { [self] grade in
            let previousValue = displayValue(for: selected.row, column: selected.column)
            var text = String(format: "%.2f", grade)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            recordCellUndo(studentId: selected.selection.studentId, column: selected.column, previousValue: previousValue, previousDisplayLabel: nil)
            bridge.saveColumnGrade(studentId: selected.selection.studentId, column: selected.column, value: text)
            reloadNotebookRow(selected.selection.studentId)
            showToast("Nota dictada: \(text)")
        }
    }

}

enum NotebookVoiceGradeParser {
    private static let wordValues: [String: Double] = [
        "cero": 0, "uno": 1, "una": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4,
        "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10
    ]

    /// Interpreta una frase dictada ("seis y medio", "siete coma cinco", "8") como nota 0-10.
    static func parseGrade(from rawText: String) -> Double? {
        let text = rawText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let numeric = firstNumericToken(in: text) {
            return clampGrade(numeric)
        }

        let words = text
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map(String.init)

        guard let firstWord = words.first, let base = wordValues[firstWord] else { return nil }

        if words.contains("medio") || words.contains("media") {
            return clampGrade(base + 0.5)
        }
        if let decimalIndex = words.firstIndex(where: { $0 == "coma" || $0 == "con" }),
           decimalIndex + 1 < words.count,
           let decimalDigit = wordValues[words[decimalIndex + 1]] {
            return clampGrade(base + decimalDigit / 10)
        }
        return clampGrade(base)
    }

    private static func firstNumericToken(in text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(normalized[range])
    }

    private static func clampGrade(_ value: Double) -> Double {
        min(10, max(0, value))
    }
}

#if canImport(UIKit)
import Speech
import AVFoundation

@MainActor
final class NotebookVoiceGradeDictationService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var lastTranscript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var autoStopTask: Task<Void, Never>?

    func toggleListening(onResult: @escaping (Double) -> Void) {
        if isListening {
            finishListening(applying: onResult)
        } else {
            startListening(onResult: onResult)
        }
    }

    private func startListening(onResult: @escaping (Double) -> Void) {
        errorMessage = nil
        lastTranscript = ""

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }
                guard authStatus == .authorized else {
                    self.errorMessage = "Permiso de reconocimiento de voz denegado"
                    return
                }
                self.beginAudioSession(onResult: onResult)
            }
        }
    }

    private func beginAudioSession(onResult: @escaping (Double) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Reconocimiento de voz no disponible en este dispositivo"
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "No se pudo activar el micrófono"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "No se pudo iniciar el micrófono"
            recognitionRequest = nil
            return
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.lastTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishListening(applying: onResult)
                    }
                } else if error != nil {
                    self.finishListening(applying: onResult)
                }
            }
        }

        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.isListening else { return }
                self.finishListening(applying: onResult)
            }
        }
    }

    private func finishListening(applying onResult: @escaping (Double) -> Void) {
        let transcript = lastTranscript
        stopListening()
        if let grade = NotebookVoiceGradeParser.parseGrade(from: transcript) {
            onResult(grade)
        } else if !transcript.isEmpty {
            errorMessage = "No se entendió “\(transcript)” como nota"
        }
    }

    func stopListening() {
        autoStopTask?.cancel()
        autoStopTask = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}
#else
@MainActor
final class NotebookVoiceGradeDictationService: ObservableObject {
    @Published private(set) var isListening = false
    @Published var errorMessage: String?

    func toggleListening(onResult: @escaping (Double) -> Void) {
        errorMessage = "El dictado por voz solo está disponible en iPad"
    }

    func stopListening() {}
}
#endif
