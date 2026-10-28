import Foundation
import SwiftUI
import MiGestorKit

/// Estado de la pantalla «Juntas». Guarda solo lo que la pantalla necesita:
/// la lista de juntas del grupo y la junta abierta.
///
/// Las ediciones (otras suspensas, acuerdo, revisado, cabecera) se aplican al
/// momento en local (el resumen se recalcula con `JuntaRules`) y se guardan en
/// KMP con una espera corta. Al guardar, el tablero que devuelve KMP manda:
/// se reconcilia salvo que el docente haya vuelto a editar mientras tanto.
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
    static let saveErrorMessage = "No se pudo guardar el último cambio. Se volverá a intentar con la siguiente edición."

    @Published private(set) var sessions: [JuntaSessionUI] = []
    @Published private(set) var listPhase: Phase = .idle
    @Published private(set) var board: JuntaBoardUI?
    @Published private(set) var boardPhase: Phase = .idle
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let bridge: KmpBridge
    private let gate = InclusionLoadGate()
    private var classId: Int64?
    private var openSessionId: String?
    private var dirtyStudents = Set<Int64>()
    private var headerDirty = false
    private var saveTask: Task<Void, Never>?
    private var isFlushing = false

    init(bridge: KmpBridge) {
        self.bridge = bridge
    }

    var hasPendingChanges: Bool { !dirtyStudents.isEmpty || headerDirty || isFlushing }

    // MARK: Carga

    func loadList(classId: Int64?) async {
        await flushNow()
        if self.classId != classId {
            sessions = []
            board = nil
            boardPhase = .idle
            openSessionId = nil
        }
        self.classId = classId
        guard let classId else {
            listPhase = .idle
            return
        }
        listPhase = .loading
        do {
            guard let loaded = try await bridge.evaluationSessionList(classId: classId, gate: gate) else { return }
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
        boardPhase = .loading
        do {
            guard let loaded = try await bridge.loadEvaluationBoard(sessionId: sessionId, classId: classId, gate: gate) else { return }
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
        await settle()
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
        guard var current = board, !current.session.isClosed else { return }
        change(&current.session)
        board = current
        headerDirty = true
        scheduleSave()
    }

    private func edit(_ studentId: Int64, _ change: (inout JuntaStudentRowUI) -> Void) {
        guard var current = board, !current.session.isClosed,
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
    func flushNow() async {
        saveTask?.cancel()
        saveTask = nil
        await performFlush()
    }

    /// Espera a que no quede nada por guardar (para cerrar la junta con todo escrito).
    private func settle() async {
        for _ in 0..<40 {
            await flushNow()
            if !hasPendingChanges { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func performFlush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !dirtyStudents.isEmpty || headerDirty {
            guard let current = board, !current.session.isClosed else {
                dirtyStudents.removeAll()
                headerDirty = false
                return
            }
            let students = dirtyStudents
            let saveHeader = headerDirty
            dirtyStudents.removeAll()
            headerDirty = false
            do {
                if saveHeader { try await bridge.saveEvaluationHeader(current.session) }
                for id in students {
                    // Se vuelve a leer la fila: puede haber cambiado mientras se guardaba la anterior.
                    guard let row = board?.students.first(where: { $0.studentId == id }) else { continue }
                    try await bridge.saveEvaluationStudent(sessionId: current.session.id, row: row)
                }
            } catch {
                dirtyStudents.formUnion(students)
                if saveHeader { headerDirty = true }
                errorMessage = Self.saveErrorMessage
                return
            }
        }
        await reconcile()
    }

    /// Sustituye lo local por el tablero de KMP, salvo que haya ediciones nuevas.
    private func reconcile() async {
        guard let classId, let sessionId = openSessionId else { return }
        guard let fresh = try? await bridge.loadEvaluationBoard(sessionId: sessionId, classId: classId, gate: gate) else { return }
        guard dirtyStudents.isEmpty, !headerDirty, openSessionId == sessionId else { return }
        board = fresh
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
