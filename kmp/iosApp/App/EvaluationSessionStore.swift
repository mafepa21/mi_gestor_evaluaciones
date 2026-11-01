import Foundation
import SwiftUI
import MiGestorKit

/// Estado de la pantalla «Juntas». Guarda solo lo que la pantalla necesita:
/// la lista de juntas del grupo y la junta abierta.
///
/// Las ediciones (otras suspensas, acuerdo, revisado, cabecera) se aplican al
/// momento en local (el resumen se recalcula con `JuntaRules`) y se guardan en
/// KMP con una espera corta. El tablero de KMP solo se vuelve a pedir al abrir,
/// cerrar y reabrir la junta: tras cada guardado automático no se recarga (la
/// carga reconstruye el Cuaderno y consulta alumno por alumno).
@MainActor
final class EvaluationSessionStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case failed
        case ready
    }

    static let saveDelay: Duration = .milliseconds(700)
    static let loadErrorMessage = "Lo que ya apuntaste está guardado. Prueba otra vez."
    static let closeBlockedMessage = "No se cerró la junta porque no se pudo guardar el último cambio. Prueba otra vez."
    static let saveErrorMessage = "No se pudo guardar el último cambio. Se volverá a intentar con la siguiente edición."

    @Published private(set) var sessions: [JuntaSessionUI] = []
    @Published private(set) var listPhase: Phase = .idle
    @Published private(set) var board: JuntaBoardUI?
    @Published private(set) var boardPhase: Phase = .idle
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let bridge: KmpBridge
    // Un gate por carga: si compartieran, abrir una junta anularía la carga de la lista y al revés.
    private let listGate = InclusionLoadGate()
    private let boardGate = InclusionLoadGate()
    private var classId: Int64?
    private var openSessionId: String?
    private var dirtyStudents = Set<Int64>()
    private var headerDirty = false
    private var saveTask: Task<Void, Never>?
    /// Guardado en curso. `flushNow()` lo espera para no devolver antes de que termine.
    private var flushTask: Task<Void, Never>?

    init(bridge: KmpBridge) {
        self.bridge = bridge
    }

    var hasPendingChanges: Bool { !dirtyStudents.isEmpty || headerDirty || flushTask != nil }

    // MARK: Carga

    func loadList(classId: Int64?) async {
        await flushNow()
        if self.classId != classId {
            sessions = []
            board = nil
            boardPhase = .idle
            openSessionId = nil
            dirtyStudents.removeAll()
            headerDirty = false
        }
        self.classId = classId
        guard let classId else {
            listPhase = .idle
            return
        }
        listPhase = .loading
        do {
            guard let loaded = try await bridge.evaluationSessionList(classId: classId, gate: listGate) else { return }
            sessions = loaded
            listPhase = .ready
        } catch {
            guard self.classId == classId else { return }
            listPhase = .failed
        }
    }

    func open(sessionId: String) async {
        guard let classId else { return }
        openSessionId = sessionId
        board = nil
        dirtyStudents.removeAll()
        headerDirty = false
        boardPhase = .loading
        do {
            guard let loaded = try await bridge.loadEvaluationBoard(sessionId: sessionId, classId: classId, gate: boardGate) else { return }
            guard openSessionId == sessionId else { return }
            board = loaded
            boardPhase = .ready
        } catch {
            guard openSessionId == sessionId, self.classId == classId else { return }
            boardPhase = .failed
        }
    }

    func retryBoard() async {
        if let id = openSessionId { await open(sessionId: id) }
    }

    /// Vuelve a la lista guardando antes lo pendiente.
    func closeBoard() async {
        await flushNow()
        openSessionId = nil
        board = nil
        boardPhase = .idle
        if let classId { await loadList(classId: classId) }
    }

    // MARK: Crear y borrar

    /// Devuelve el mensaje de error para mostrarlo en la hoja, o `nil` si salió bien.
    func create(kind: EvaluationKindUI, date: Date, attendees: String) async -> String? {
        guard let classId else { return "Elige un grupo." }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let created = try await bridge.createEvaluationSession(
                classId: classId, kind: kind, date: date, attendees: attendees
            ) else { return "No se pudo crear la junta." }
            sessions = (try? await bridge.evaluationSessionList(classId: classId, gate: nil)) ?? sessions
            await open(sessionId: created.id)
            return nil
        } catch {
            return Self.message(for: error, fallback: "No se pudo crear la junta.")
        }
    }

    func delete(sessionId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await bridge.deleteEvaluationSession(id: sessionId)
            if openSessionId == sessionId {
                openSessionId = nil
                board = nil
                boardPhase = .idle
                dirtyStudents.removeAll()
                headerDirty = false
            }
            sessions.removeAll { $0.id == sessionId }
        } catch {
            errorMessage = Self.message(for: error, fallback: "No se pudo borrar la junta.")
        }
    }

    // MARK: Cerrar y reabrir

    func closeSession() async {
        guard let id = board?.session.id else { return }
        isWorking = true
        defer { isWorking = false }
        // flushNow espera al guardado en curso. Si algo no se pudo guardar, no se cierra:
        // el acta congelaría datos viejos.
        await flushNow()
        if hasPendingChanges {
            errorMessage = Self.closeBlockedMessage
            return
        }
        do {
            board = try await bridge.closeEvaluationSession(id: id)
        } catch {
            errorMessage = Self.message(for: error, fallback: "No se pudo cerrar la junta.")
        }
    }

    func reopenSession() async {
        guard let id = board?.session.id else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            board = try await bridge.reopenEvaluationSession(id: id)
        } catch {
            errorMessage = Self.message(for: error, fallback: "No se pudo reabrir la junta.")
        }
    }

    // MARK: Ediciones (local al instante, guardado con espera)

    func setOtherFailed(studentId: Int64, to value: Int) {
        edit(studentId) { $0.otherFailedCount = min(max(value, 0), JuntaRules.maxOtherFailed) }
    }

    func setAgreement(studentId: Int64, to text: String) {
        edit(studentId) { $0.agreement = text }
    }

    func setReviewed(studentId: Int64, to value: Bool) {
        edit(studentId) { $0.isReviewed = value }
    }

    func editHeader(_ change: (inout JuntaSessionUI) -> Void) {
        guard !isWorking, var current = board, !current.session.isClosed else { return }
        change(&current.session)
        board = current
        headerDirty = true
        scheduleSave()
    }

    private func edit(_ studentId: Int64, _ change: (inout JuntaStudentRowUI) -> Void) {
        guard !isWorking, var current = board, !current.session.isClosed,
              let index = current.students.firstIndex(where: { $0.studentId == studentId }) else { return }
        change(&current.students[index])
        current.summary = JuntaRules.summary(of: current.students)
        board = current
        dirtyStudents.insert(studentId)
        scheduleSave()
    }

    // MARK: Guardado

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.performFlush()
        }
    }

    /// Guarda ya lo pendiente (al salir de la pantalla, cambiar de grupo o cerrar).
    /// Si ya hay un guardado en curso, lo espera antes de volver.
    func flushNow() async {
        saveTask?.cancel()
        saveTask = nil
        if let running = flushTask { await running.value }
        await startFlush()
    }

    private func startFlush() async {
        if let running = flushTask {
            await running.value
            return
        }
        guard !dirtyStudents.isEmpty || headerDirty else { return }
        let task = Task { [weak self] in
            await self?.runFlush()
            self?.flushTask = nil
        }
        flushTask = task
        await task.value
    }

    private func performFlush() async {
        await startFlush()
    }

    private func runFlush() async {
        while !dirtyStudents.isEmpty || headerDirty {
            guard let current = board, !current.session.isClosed else {
                dirtyStudents.removeAll()
                headerDirty = false
                return
            }
            // Foto del tablero antes de vaciar lo pendiente: el bucle lee de ella, no de `board`
            // (que puede quedar en nil si se sale de la junta mientras se guarda).
            let students = dirtyStudents
            let saveHeader = headerDirty
            let rows = current.students.filter { students.contains($0.studentId) }
            dirtyStudents.removeAll()
            headerDirty = false
            do {
                if saveHeader { try await bridge.saveEvaluationHeader(current.session) }
                for row in rows {
                    try await bridge.saveEvaluationStudent(sessionId: current.session.id, row: row)
                }
            } catch {
                dirtyStudents.formUnion(students)
                if saveHeader { headerDirty = true }
                errorMessage = Self.saveErrorMessage
                return
            }
        }
    }

    // MARK: Errores

    static func message(for error: Error, fallback: String) -> String {
        let nsError = error as NSError
        if nsError.userInfo["KotlinException"] is MiGestorKit.EvaluationSessionException {
            return nsError.localizedDescription
        }
        return fallback
    }
}
