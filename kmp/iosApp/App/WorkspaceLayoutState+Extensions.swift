import SwiftUI
import MiGestorKit

extension AppWorkspaceShell {
    var shouldShowGlobalContextualAIButton: Bool {
        switch activeModule {
        case .notebook, .teacherRadar, .planner, .situations, .rubrics, .library, .settings:
            return false
        default:
            return true
        }
    }

    func presentContextualAI() {
        guard !isLoadingContextualAI else { return }
        isLoadingContextualAI = true
        Task {
            let module = activeModule
            let resolvedClassId = selectedClassId
            let resolvedStudentId = selectedStudentId
            let context: KmpBridge.ScreenAIContext
            do {
                context = try await loadContextualAIContext(
                    for: module,
                    classId: resolvedClassId,
                    studentId: resolvedStudentId
                )
            } catch {
                context = fallbackContext(for: module, classId: resolvedClassId, studentId: resolvedStudentId, message: error.localizedDescription)
            }
            await MainActor.run {
                contextualAISheetState = ContextualAISheetState(module: module, context: context)
                isLoadingContextualAI = false
            }
        }
    }

    var shouldShowClassroomCaptureBar: Bool {
        guard selectedClassId != nil else { return false }
        switch activeModule {
        case .notebook, .teacherRadar, .attendance, .planner, .situations, .students, .diary, .evaluationHub, .rubrics, .peSessions:
            return true
        default:
            return false
        }
    }

    var classroomCaptureTitle: String {
        let session = classroomContext?.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session, !session.isEmpty {
            return "Hoy · \(activeClassLabel) · \(session)"
        }
        return "Hoy · \(activeClassLabel)"
    }

    var classroomCaptureStudents: [Student] {
        if !bridge.studentsInClass.isEmpty {
            return bridge.studentsInClass
        }
        return bridge.allStudents
    }

    func reloadClassroomContext() async {
        guard let selectedClassId else {
            await MainActor.run { classroomContext = nil }
            return
        }
        await bridge.selectStudentsClass(classId: selectedClassId)
        let snapshot = try? await bridge.classroomCaptureContext(classId: selectedClassId, on: Date())
        await MainActor.run {
            classroomContext = snapshot
            if classroomCaptureStudentId == nil {
                classroomCaptureStudentId = selectedStudentId ?? bridge.studentsInClass.first?.id
            }
        }
    }

    func openClassroomRubricCapture() async {
        guard let selectedClassId else { return }
        let opened = await bridge.launchFirstBulkRubricEvaluationForClass(classId: selectedClassId)
        if !opened {
            open(module: .evaluationHub, classId: selectedClassId, studentId: selectedStudentId)
        }
    }

    func presentClassroomCapture(_ sheet: ClassroomCaptureSheet) {
        classroomCaptureStudentId = selectedStudentId ?? classroomCaptureStudentId ?? classroomCaptureStudents.first?.id
        classroomCaptureText = ""
        classroomCaptureSheet = sheet
    }

    @ViewBuilder
    func classroomCaptureSheetView(_ sheet: ClassroomCaptureSheet) -> some View {
        ClassroomCaptureSheetView(
            kind: sheet,
            students: classroomCaptureStudents,
            selectedStudentId: $classroomCaptureStudentId,
            noteText: $classroomCaptureText,
            isSaving: isSavingClassroomCapture,
            onCancel: {
                classroomCaptureSheet = nil
            },
            onSave: {
                Task { await saveClassroomCapture(sheet) }
            }
        )
    }

    func saveClassroomCapture(_ sheet: ClassroomCaptureSheet) async {
        guard let classId = selectedClassId,
              let studentId = classroomCaptureStudentId else { return }
        isSavingClassroomCapture = true
        defer { isSavingClassroomCapture = false }

        do {
            switch sheet {
            case .quickNote:
                try await bridge.saveQuickStudentNote(studentId: studentId, classId: classId, note: classroomCaptureText)
            case .observation:
                _ = try await bridge.createIncident(
                    classId: classId,
                    studentId: studentId,
                    title: "Observación de aula",
                    detail: classroomCaptureText.trimmingCharacters(in: .whitespacesAndNewlines),
                    severity: "low"
                )
                bridge.status = "Observación registrada."
            case .injury:
                let current = classroomCaptureStudents.first(where: { $0.id == studentId })?.isInjured ?? false
                try await bridge.updateStudentInjuryStatus(studentId: studentId, isInjured: !current, classId: classId)
                bridge.status = current ? "Lesión retirada." : "Alumno marcado con lesión."
            }
            classroomCaptureSheet = nil
            classroomCaptureText = ""
            try? await bridge.refreshStudentsDirectory()
            await reloadClassroomContext()
        } catch {
            bridge.status = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    func loadContextualAIContext(
        for module: AppWorkspaceModule,
        classId: Int64?,
        studentId: Int64?
    ) async throws -> KmpBridge.ScreenAIContext {
        switch module {
        case .dashboard:
            return try await bridge.buildDashboardAIContext(classId: classId)
        case .courses:
            return try await bridge.buildCoursesAIContext(classId: classId)
        case .students:
            return try await bridge.buildStudentsAIContext(classId: classId, studentId: studentId)
        case .teacherRadar:
            return bridge.buildNotebookAIContext(classId: classId)
        case .attendance:
            return try await bridge.buildAttendanceAIContext(classId: classId)
        case .diary, .planner:
            return try await bridge.buildDiaryAIContext(classId: classId)
        case .evaluationHub:
            return try await bridge.buildEvaluationAIContext(classId: classId)
        case .reports:
            return try await bridge.buildReportsAIContext(classId: classId, studentId: studentId)
        case .peSessions, .peTests, .peRubrics, .peIncidents, .peMaterial, .peTournaments:
            return try await bridge.buildPEAIContext(classId: classId)
        case .notebook:
            return bridge.buildNotebookAIContext(classId: classId)
        case .situations, .rubrics, .library, .meetings, .settings, .backups:
            return fallbackContext(for: module, classId: classId, studentId: studentId, message: "Esta pantalla todavía no ofrece acciones IA contextuales.")
        }
    }

    func fallbackContext(
        for module: AppWorkspaceModule,
        classId: Int64?,
        studentId: Int64?,
        message: String
    ) -> KmpBridge.ScreenAIContext {
        KmpBridge.ScreenAIContext(
            kind: module == .reports ? .reports : module.section == .domainModules ? .pe : .courses,
            title: module.title,
            subtitle: module.subtitle,
            classId: classId,
            className: bridge.classes.first(where: { $0.id == classId })?.name,
            studentId: studentId,
            studentName: bridge.allStudents.first(where: { $0.id == studentId }).map { "\($0.firstName) \($0.lastName)" },
            summary: message,
            metrics: [],
            factLines: [message],
            supportNotes: [],
            suggestedActions: [],
            hasEnoughData: false,
            dataQualityNote: message
        )
    }

    var primaryActionLabel: String {
        switch activeModule {
        case .courses: return "Nueva clase"
        case .students: return "Nuevo alumno"
        case .planner: return "Nueva sesión"
        case .situations: return "Importar DOCX"
        case .diary: return "Ver planner"
        case .evaluationHub: return "Nueva evaluación"
        case .rubrics, .peRubrics: return "Nueva rúbrica"
        case .peSessions: return "Nueva sesión EF"
        case .peTests: return "Nueva prueba"
        case .peIncidents: return "Nueva incidencia"
        case .peMaterial: return "Nuevo material"
        case .peTournaments: return "Nuevo torneo"
        default: return "Crear"
        }
    }

    var statusLineText: String {
        let rawStatus = bridge.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawStatus.isEmpty, rawStatus != "Inicializando...", rawStatus != "La acción principal de este módulo se gestiona dentro de la vista." {
            return rawStatus
        }
        switch activeModule {
        case .dashboard:
            return "Selecciona un bloque del dashboard para ver contexto operativo y acciones inmediatas."
        case .courses:
            return "Abre un grupo para lanzar cuaderno, asistencia, diario, informes o alumnado desde el mismo panel."
        case .students:
            return "La ficha del alumno centraliza seguimiento, incidencias, evaluaciones y contexto docente."
        case .teacherRadar:
            return "El Radar convierte cuaderno, evidencias y rúbricas en decisiones docentes inmediatas."
        case .notebook:
            return "El cuaderno concentra calificación, seguimiento y acciones rápidas sobre columnas y alumnado."
        case .attendance:
            return "Marca asistencia, crea incidencias y revisa el pulso del grupo sin salir del módulo."
        case .planner:
            return "Planifica la semana, ajusta sesiones y salta al diario cuando necesites cerrar una sesión."
        case .situations:
            return "Importa situaciones, revisa sus datos y crea solo las sesiones e instrumentos que necesites."
        case .diary:
            return "Cierra una sesión, deja trazabilidad docente y usa el inspector solo cuando necesites contexto secundario."
        case .meetings:
            return "Registra actas de claustros, equipos docentes y CCP, y haz seguimiento de los acuerdos con responsable y fecha."
        case .evaluationHub:
            return "Selecciona un instrumento para revisar peso, rúbrica, vínculos y acceso directo al cuaderno."
        case .rubrics:
            return "El banco de rúbricas muestra criterios, niveles, clases y evaluaciones con lectura docente."
        case .reports:
            return "Genera vistas previas y comparte informes de grupo, individuales, evaluativos u operativos."
        case .library:
            return "La biblioteca agrupa plantillas reutilizables de cuaderno, rúbricas y estructura docente."
        case .peSessions:
            return "Crea sesiones EF, activa el trabajo en pista y registra material, intensidad e incidencias."
        case .peTests:
            return "Crea pruebas físicas, aplica baremos, registra marcas y compara históricos del grupo."
        case .peRubrics:
            return "Usa plantillas EF de observación, seguridad y ejecución sin salir del banco de rúbricas."
        case .peIncidents:
            return "Registra lesiones, seguridad, conducta, equipación y seguimiento individual desde EF."
        case .peMaterial:
            return "Gestiona preparación, uso y estado del material vinculado a sesiones EF."
        case .peTournaments:
            return "Organiza torneos completos con plantillas, equipos, calendario y clasificación."
        case .settings:
            return "Configura agenda docente, calendario lectivo, sincronización y preferencias globales del workspace."
        case .backups:
            return "Protege y restaura tu base de datos de evaluaciones y evidencias con copias verificables."
        }
    }

    var activeClassLabel: String {
        guard let selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == selectedClassId })
        else { return "Clase global" }
        return schoolClass.name
    }

    func syncRootSplitVisibility() {
        let visibility: NavigationSplitViewVisibility = (layoutState.isSidebarVisible && !layoutState.isFocusModeEnabled) ? .all : .detailOnly
        Task { @MainActor in
            guard rootSplitVisibility != visibility else { return }
            rootSplitVisibility = visibility
        }
    }

    func open(module: AppWorkspaceModule, classId: Int64? = nil, studentId: Int64? = nil) {
        activeModule = module
        if let classId {
            updateGlobalClassContext(classId)
        }
        if let studentId {
            selectedStudentId = studentId
        }
        searchText = ""
    }

    var resolvedPlannerContext: PlannerNavigationContext {
        PlannerNavigationContext(
            week: plannerContext.week,
            year: plannerContext.year,
            groupId: plannerContext.groupId ?? selectedClassId,
            sessionId: plannerContext.sessionId
        )
    }

    func openPlanner(context: PlannerNavigationContext) {
        plannerContext = context
        open(module: .planner, classId: context.groupId)
    }

    func openDiary(context: PlannerNavigationContext) {
        plannerContext = context
        open(module: .diary, classId: context.groupId)
    }

    func updateGlobalClassContext(_ classId: Int64?) {
        selectedClassId = classId
        plannerContext.groupId = classId
        Task {
            await bridge.selectStudentsClass(classId: classId)
        }
        if let classId {
            bridge.selectClass(id: classId)
        }
    }

    func apply(searchResult: WorkspaceSearchResult) {
        switch searchResult.kind {
        case .module(let module):
            open(module: module)
        case .schoolClass(let classId):
            open(module: .courses, classId: classId)
        case .student(let studentId):
            open(module: .students, classId: selectedClassId, studentId: studentId)
        }
    }

    func triggerPrimaryAction() {
        switch activeModule {
        case .courses:
            createSheet = .course
        case .students:
            createSheet = .student
        case .teacherRadar:
            open(module: .notebook, classId: selectedClassId, studentId: selectedStudentId)
        case .evaluationHub:
            createSheet = .evaluation
        case .rubrics, .peRubrics:
            bridge.resetRubricBuilder()
            showingRubricBuilder = true
        case .planner:
            layoutState.openPlannerComposer()
        case .diary:
            openPlanner(context: resolvedPlannerContext)
        default:
            bridge.status = ""
        }
    }
}
