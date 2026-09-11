import Foundation
import SwiftUI
import CryptoKit
import MiGestorKit

extension KmpBridge {
    func buildDashboardAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let snapshot = try await container.getOperationalDashboardSnapshot.invoke(
            mode: .office,
            filters: DashboardFilters(classId: classId.map { KotlinLong(value: $0) }, severity: nil, priority: nil, sessionStatus: nil)
        )
        let selectedSummary = classId.flatMap { id in snapshot.groupSummaries.first(where: { $0.classId == id }) }
        return ScreenAIContext(
            kind: .dashboard,
            title: "Dashboard docente",
            subtitle: selectedSummary?.groupName ?? "Visión operativa del día",
            classId: classId,
            className: selectedSummary?.groupName,
            studentId: nil,
            studentName: nil,
            summary: "Resumen operativo con alertas, agenda y grupos que conviene revisar.",
            metrics: [
                ReportMetric(title: "Hoy", value: "\(snapshot.todayCount)", systemImage: "calendar"),
                ReportMetric(title: "Alertas", value: "\(snapshot.alertsCount)", systemImage: "exclamationmark.bubble.fill"),
                ReportMetric(title: "Pendientes", value: "\(snapshot.pendingCount)", systemImage: "clock.badge.exclamationmark"),
                ReportMetric(title: "Grupos", value: "\(snapshot.groupSummaries.count)", systemImage: "rectangle.3.group")
            ],
            factLines: compactSuggestions(
                "Sesiones previstas hoy: \(snapshot.todayCount).",
                "Alertas visibles: \(snapshot.alertsCount).",
                "Pendientes operativos: \(snapshot.pendingCount).",
                snapshot.nextSessionLabel == "Sin próxima sesión" ? nil : "Próxima sesión: \(snapshot.nextSessionLabel).",
                selectedSummary.map { "Grupo destacado: \($0.groupName) con asistencia \($0.attendancePct)% y media \(IosFormatting.decimal(from: $0.averageScore))." }
            ),
            supportNotes: compactSuggestions(
                snapshot.alerts.first.map { "\($0.title): \($0.detail)" },
                snapshot.agendaItems.first.map { "\($0.title) · \($0.subtitle)" }
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .dailyBriefing, title: "Briefing diario", subtitle: "Qué atender hoy y por qué", systemImage: "sun.max.fill", promptHint: "Prioriza el arranque del día con hechos y acciones docentes."),
                ContextualAIAction(actionId: .operationalSummary, title: "Resumen operativo", subtitle: "Prioriza lo importante del día", systemImage: "bolt.badge.clock.fill", promptHint: "Resume el estado operativo y lo urgente."),
                ContextualAIAction(actionId: .prioritizedAlerts, title: "Alertas priorizadas", subtitle: "Ordena incidencias y seguimiento", systemImage: "exclamationmark.triangle.fill", promptHint: "Ordena alertas y explica por qué conviene revisarlas."),
                ContextualAIAction(actionId: .weeklyDigest, title: "Digest semanal", subtitle: "Texto breve para seguimiento docente", systemImage: "doc.text.fill", promptHint: "Crea un digest semanal breve y accionable.")
            ],
            hasEnoughData: snapshot.todayCount > 0 || snapshot.alertsCount > 0 || !snapshot.groupSummaries.isEmpty,
            dataQualityNote: snapshot.groupSummaries.isEmpty ? "No hay resúmenes de grupo cargados todavía en el dashboard." : nil
        )
    }

    func buildCoursesAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let classes = try await container.classesRepository.listClasses()
        let selectedClass = classId.flatMap { id in classes.first(where: { $0.id == id }) }
        let summary: CourseInspectorSnapshot? = if let selectedClass {
            try? await loadCourseSummary(classId: selectedClass.id)
        } else {
            nil
        }
        return ScreenAIContext(
            kind: .courses,
            title: "Cursos",
            subtitle: selectedClass?.name ?? "Panorámica de grupos",
            classId: selectedClass?.id,
            className: selectedClass?.name,
            studentId: nil,
            studentName: nil,
            summary: selectedClass == nil ? "Contexto docente del conjunto de grupos." : "Resumen rápido del grupo activo para decidir próximos pasos.",
            metrics: [
                ReportMetric(title: "Grupos", value: "\(classes.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Curso", value: selectedClass.map { courseLabel(for: $0) } ?? "General", systemImage: "graduationcap.fill"),
                ReportMetric(title: "Alumnado", value: summary.map { "\($0.studentCount)" } ?? "--", systemImage: "person.3.fill"),
                ReportMetric(title: "Asistencia", value: summary.map { "\($0.attendanceRate)%" } ?? "--", systemImage: "checklist.checked")
            ],
            factLines: compactSuggestions(
                "Clases registradas: \(classes.count).",
                selectedClass.map { "Grupo activo: \($0.name)." },
                summary.map { "Evaluaciones activas: \($0.evaluationCount)." },
                summary.map { "Incidencias registradas: \($0.incidentCount)." }
            ),
            supportNotes: compactSuggestions(
                summary?.activeEvaluationNames.first.map { "Instrumento destacado: \($0)" }
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .classSnapshot, title: "Foto del grupo", subtitle: "Resumen del grupo activo", systemImage: "rectangle.3.group.bubble.left.fill", promptHint: "Resume lo importante del grupo activo."),
                ContextualAIAction(actionId: .observationProposal, title: "Observaciones", subtitle: "Propuesta breve de observación docente", systemImage: "note.text.badge.plus", promptHint: "Sugiere observaciones breves y prudentes para este grupo.")
            ],
            hasEnoughData: !classes.isEmpty,
            dataQualityNote: selectedClass == nil ? "No hay grupo seleccionado; la salida será general." : nil
        )
    }

    func buildStudentsAIContext(classId: Int64?, studentId: Int64?) async throws -> ScreenAIContext {
        if let studentId {
            let profile = try await loadStudentProfile(studentId: studentId, classId: classId)
            return ScreenAIContext(
                kind: .students,
                title: "Ficha del alumno",
                subtitle: profile.student.fullName,
                classId: classId,
                className: profile.schoolClass?.name,
                studentId: studentId,
                studentName: profile.student.fullName,
                summary: "Síntesis individual para seguimiento, tutoría o comunicación con familia.",
                metrics: [
                    ReportMetric(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum"),
                    ReportMetric(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill"),
                    ReportMetric(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                ],
                factLines: compactSuggestions(
                    "Alumno: \(profile.student.fullName).",
                    "Asistencia estimada: \(profile.attendanceRate)%.",
                    profile.averageScore > 0 ? "Media registrada: \(IosFormatting.decimal(from: profile.averageScore))." : "Sin media consolidada todavía.",
                    "Seguimientos activos: \(profile.followUpCount).",
                    profile.latestAttendanceStatus.map { "Último estado de asistencia: \($0)." }
                ),
                supportNotes: compactSuggestions(
                    profile.adaptationsSummary,
                    profile.familyCommunicationSummary,
                    profile.timeline.first.map { "\($0.title) · \($0.subtitle)" }
                ),
                suggestedActions: [
                    ContextualAIAction(actionId: .studentFollowUp, title: "Resumen de seguimiento", subtitle: "Lectura docente breve", systemImage: "person.text.rectangle.fill", promptHint: "Resume el seguimiento del alumno de forma accionable."),
                    ContextualAIAction(actionId: .studentRiskRadar, title: "Radar de riesgo", subtitle: "Clasificación prudente y explicable", systemImage: "shield.lefthalf.filled.badge.exclamationmark", promptHint: "Explica el nivel de atención del alumno con hechos verificables."),
                    ContextualAIAction(actionId: .familyComment, title: "Comentario para familia", subtitle: "Versión clara y respetuosa", systemImage: "person.2.badge.gearshape.fill", promptHint: "Redacta un comentario claro para familia."),
                    ContextualAIAction(actionId: .tutoringDraft, title: "Borrador de tutoría", subtitle: "Texto base con siguiente acción", systemImage: "person.crop.rectangle.stack.fill", promptHint: "Prepara un borrador prudente para tutoría o seguimiento."),
                    ContextualAIAction(actionId: .observationProposal, title: "Propuesta de observación", subtitle: "Texto corto editable", systemImage: "text.badge.plus", promptHint: "Genera una observación breve y prudente.")
                ],
                hasEnoughData: profile.instrumentsCount > 0 || profile.incidentCount > 0 || profile.journalNoteCount > 0,
                dataQualityNote: profile.instrumentsCount == 0 ? "Hay poca evidencia evaluativa registrada para este alumno." : nil
            )
        }

        return try await buildCoursesAIContext(classId: classId).copy(kind: .students, title: "Alumnado", summary: "Selecciona un alumno para un contexto más preciso.")
    }

    func buildAttendanceAIContext(classId: Int64?) async throws -> ScreenAIContext {
        guard let classId else {
            return ScreenAIContext(
                kind: .attendance,
                title: "Asistencia",
                subtitle: "Sin clase activa",
                classId: nil,
                className: nil,
                studentId: nil,
                studentName: nil,
                summary: "Selecciona una clase para analizar patrones de asistencia.",
                metrics: [],
                factLines: ["No hay grupo seleccionado."],
                supportNotes: [],
                suggestedActions: [],
                hasEnoughData: false,
                dataQualityNote: "La asistencia necesita un grupo activo."
            )
        }
        let summary = try await loadCourseSummary(classId: classId)
        let history = try await attendanceHistory(for: classId, days: 21)
        let absent = history.filter { normalizedAnalyticsText($0.status).contains("aus") }.count
        let late = history.filter { normalizedAnalyticsText($0.status).contains("tard") || normalizedAnalyticsText($0.status).contains("retr") }.count
        return ScreenAIContext(
            kind: .attendance,
            title: "Asistencia",
            subtitle: summary.schoolClass.name,
            classId: classId,
            className: summary.schoolClass.name,
            studentId: nil,
            studentName: nil,
            summary: "Lectura de asistencia reciente con foco en ausencias, retrasos y seguimiento.",
            metrics: [
                ReportMetric(title: "Asistencia", value: "\(summary.attendanceRate)%", systemImage: "checklist.checked"),
                ReportMetric(title: "Ausencias", value: "\(absent)", systemImage: "xmark.circle.fill"),
                ReportMetric(title: "Retrasos", value: "\(late)", systemImage: "clock.badge.exclamationmark"),
                ReportMetric(title: "Registros", value: "\(history.count)", systemImage: "calendar")
            ],
            factLines: compactSuggestions(
                "Grupo: \(summary.schoolClass.name).",
                "Asistencia reciente estimada: \(summary.attendanceRate)%.",
                "Ausencias en el periodo: \(absent).",
                "Retrasos en el periodo: \(late)."
            ),
            supportNotes: compactSuggestions(
                late > 0 ? "Hay retrasos suficientes como para revisar patrones horarios." : nil
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .attendancePatterns, title: "Patrones de asistencia", subtitle: "Detecta señales y brechas", systemImage: "waveform.path.ecg", promptHint: "Explica los patrones recientes de asistencia."),
                ContextualAIAction(actionId: .followUpList, title: "Lista de seguimiento", subtitle: "Quién conviene revisar primero", systemImage: "list.bullet.clipboard.fill", promptHint: "Prioriza seguimiento por asistencia e incidencias.")
            ],
            hasEnoughData: !history.isEmpty,
            dataQualityNote: history.isEmpty ? "Todavía no hay suficientes registros de asistencia." : nil
        )
    }

    func buildDiaryAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        let sessions = try await diarySessions(weekNumber: week, year: year, classId: classId)
        let withIncidents = sessions.filter(\.hasIncidents).count
        let className = classId.flatMap { id in classes.first(where: { $0.id == id })?.name }
        return ScreenAIContext(
            kind: .diary,
            title: "Diario de aula",
            subtitle: className ?? "Semana actual",
            classId: classId,
            className: className,
            studentId: nil,
            studentName: nil,
            summary: "Resumen semanal del diario con incidencias, trazabilidad y próximos pasos.",
            metrics: [
                ReportMetric(title: "Sesiones", value: "\(sessions.count)", systemImage: "doc.text.fill"),
                ReportMetric(title: "Con incidencias", value: "\(withIncidents)", systemImage: "exclamationmark.bubble.fill")
            ],
            factLines: compactSuggestions(
                "Sesiones revisadas esta semana: \(sessions.count).",
                "Sesiones con incidencias: \(withIncidents).",
                sessions.first.map { "Última sesión: \(fallbackString($0.session.teachingUnitName, fallback: "Sin unidad"))." }
            ),
            supportNotes: compactSuggestions(
                sessions.first?.journalSummary?.incidentTags.isEmpty == false ? "Etiquetas recientes: \(sessions.first?.journalSummary?.incidentTags.joined(separator: ", ") ?? "")" : nil
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .diarySummary, title: "Síntesis semanal", subtitle: "Resumen docente breve", systemImage: "doc.plaintext.fill", promptHint: "Resume la semana lectiva con foco en lo relevante."),
                ContextualAIAction(actionId: .nextSteps, title: "Próximos pasos", subtitle: "Acciones sugeridas para la siguiente sesión", systemImage: "arrowshape.right.fill", promptHint: "Propón próximos pasos realistas y prudentes."),
                ContextualAIAction(actionId: .sessionClosure, title: "Cierre de sesión", subtitle: "Qué pasó y qué ajustar después", systemImage: "flag.checkered.2.crossed", promptHint: "Cierra la sesión con hechos, aprendizaje y siguiente paso.")
            ],
            hasEnoughData: !sessions.isEmpty,
            dataQualityNote: sessions.isEmpty ? "No hay sesiones de diario registradas esta semana." : nil
        )
    }

    func buildEvaluationAIContext(classId: Int64?) async throws -> ScreenAIContext {
        guard let classId else {
            return ScreenAIContext(kind: .evaluation, title: "Evaluación", subtitle: "Sin clase activa", classId: nil, className: nil, studentId: nil, studentName: nil, summary: "Selecciona una clase para leer instrumentos y progreso.", metrics: [], factLines: ["No hay clase activa."], supportNotes: [], suggestedActions: [], hasEnoughData: false, dataQualityNote: "La evaluación necesita un grupo activo.")
        }
        let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId })
        let evaluations = try await evaluations(for: classId)
        let values = try await container.gradesRepository.listGradesForClass(classId: classId).compactMap { $0.value?.doubleValue }
        let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
        let rubrics = evaluations.filter { $0.rubricId != nil }.count
        return ScreenAIContext(
            kind: .evaluation,
            title: "Evaluación",
            subtitle: schoolClass?.name ?? "Grupo activo",
            classId: classId,
            className: schoolClass?.name,
            studentId: nil,
            studentName: nil,
            summary: "Digest breve de instrumentos, rúbricas y progreso evaluativo del grupo.",
            metrics: [
                ReportMetric(title: "Instrumentos", value: "\(evaluations.count)", systemImage: "chart.bar.doc.horizontal"),
                ReportMetric(title: "Rúbricas", value: "\(rubrics)", systemImage: "checklist"),
                ReportMetric(title: "Notas", value: "\(values.count)", systemImage: "number"),
                ReportMetric(title: "Media", value: IosFormatting.decimal(from: average), systemImage: "sum")
            ],
            factLines: compactSuggestions(
                "Instrumentos activos: \(evaluations.count).",
                "Rúbricas vinculadas: \(rubrics).",
                values.isEmpty ? "Todavía no hay calificaciones registradas." : "Media agregada: \(IosFormatting.decimal(from: average))."
            ),
            supportNotes: evaluations.prefix(4).map { "\($0.name) · peso \(IosFormatting.decimal(from: $0.weight))" },
            suggestedActions: [
                ContextualAIAction(actionId: .evaluationDigest, title: "Digest de evaluación", subtitle: "Lectura narrativa de los instrumentos", systemImage: "chart.bar.doc.horizontal.fill", promptHint: "Resume instrumentos, pesos y progreso."),
                ContextualAIAction(actionId: .progressReadout, title: "Lectura de progreso", subtitle: "Explica el avance del grupo", systemImage: "chart.line.uptrend.xyaxis", promptHint: "Explica el estado de progreso del grupo con prudencia."),
                ContextualAIAction(actionId: .groupInsight, title: "Inspector analítico", subtitle: "Patrones del grupo apoyados en evidencia", systemImage: "chart.xyaxis.line", promptHint: "Resume patrones del grupo a partir de paneles analíticos y hechos verificables.")
            ],
            hasEnoughData: !evaluations.isEmpty,
            dataQualityNote: values.isEmpty ? "Hay estructura evaluativa pero faltan calificaciones para una lectura más sólida." : nil
        )
    }

    func buildReportsAIContext(classId: Int64?, studentId: Int64?) async throws -> ScreenAIContext {
        guard let classId else {
            return ScreenAIContext(kind: .reports, title: "Informes", subtitle: "Sin clase activa", classId: nil, className: nil, studentId: nil, studentName: nil, summary: "Selecciona una clase para generar apoyo contextual al informe.", metrics: [], factLines: ["No hay clase activa."], supportNotes: [], suggestedActions: [], hasEnoughData: false, dataQualityNote: "Los informes necesitan un grupo activo.")
        }
        let context = try await buildReportGenerationContext(
            classId: classId,
            studentId: studentId,
            kind: studentId == nil ? .groupOverview : .studentSummary,
            termLabel: nil
        )
        return ScreenAIContext(
            kind: .reports,
            title: "Informes",
            subtitle: context.studentName ?? context.className,
            classId: classId,
            className: context.className,
            studentId: studentId,
            studentName: context.studentName,
            summary: context.summary,
            metrics: context.metrics,
            factLines: context.factLines,
            supportNotes: context.supportNotes,
            suggestedActions: [
                ContextualAIAction(actionId: .reportBridge, title: "Puente a informe", subtitle: "Preparar texto base para informe", systemImage: "doc.richtext.fill", promptHint: "Resume este contexto con formato listo para informe."),
                ContextualAIAction(actionId: .familyComment, title: "Versión para familia", subtitle: "Lenguaje más claro y cercano", systemImage: "person.2.badge.gearshape.fill", promptHint: "Reescribe el resumen con lenguaje para familia."),
                ContextualAIAction(actionId: .tutoringDraft, title: "Borrador de tutoría", subtitle: "Modo interno, tutoría o familia", systemImage: "text.document.fill", promptHint: "Prepara un borrador prudente con siguiente acción sugerida.")
            ],
            hasEnoughData: context.hasEnoughData,
            dataQualityNote: context.dataQualityNote
        )
    }

    func buildPEAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        let sessions = try await loadPESessions(weekNumber: week, year: year, classId: classId)
        let unequippedCount = sessions.reduce(0) { $0 + tokenCount(in: $1.unequippedStudentsText) }
        let injuriesCount = sessions.filter { !$0.injuriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let className = classId.flatMap { id in classes.first(where: { $0.id == id })?.name }
        return ScreenAIContext(
            kind: .pe,
            title: "Educación Física",
            subtitle: className ?? "Operativa EF",
            classId: classId,
            className: className,
            studentId: nil,
            studentName: nil,
            summary: "Resumen de operativa EF con equipación, incidencias físicas y clima de sesión.",
            metrics: [
                ReportMetric(title: "Sesiones", value: "\(sessions.count)", systemImage: "figure.run"),
                ReportMetric(title: "Sin equipación", value: "\(unequippedCount)", systemImage: "figure.run.square.stack"),
                ReportMetric(title: "Lesiones", value: "\(injuriesCount)", systemImage: "cross.case.fill")
            ],
            factLines: compactSuggestions(
                "Sesiones EF revisadas: \(sessions.count).",
                "Registros de alumnado sin equipación: \(unequippedCount).",
                "Sesiones con lesiones registradas: \(injuriesCount)."
            ),
            supportNotes: compactSuggestions(
                sessions.first.map { "Última sesión: \(fallbackString($0.session.teachingUnitName, fallback: "Sin unidad"))." },
                sessions.first.map { fallbackString($0.physicalIncidentsText, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 }
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .peOperationalSummary, title: "Resumen EF", subtitle: "Síntesis operativa de la semana", systemImage: "figure.run.circle.fill", promptHint: "Resume la operativa EF de la semana."),
                ContextualAIAction(actionId: .peEquipmentSummary, title: "Equipación", subtitle: "Lectura breve de incidencias de material y ropa", systemImage: "figure.run.square.stack.fill", promptHint: "Explica las señales sobre equipación y seguimiento.")
            ],
            hasEnoughData: !sessions.isEmpty,
            dataQualityNote: sessions.isEmpty ? "No hay sesiones EF registradas esta semana." : nil
        )
    }

    func buildNotebookAIContext(classId: Int64?) -> ScreenAIContext {
        guard let data = notebookState as? NotebookUiStateData else {
            return ScreenAIContext(kind: .notebook, title: "Cuaderno", subtitle: "Sin datos", classId: classId, className: nil, studentId: nil, studentName: nil, summary: "Selecciona una clase para trabajar con el cuaderno.", metrics: [], factLines: ["No hay datos del cuaderno cargados todavía."], supportNotes: [], suggestedActions: [], hasEnoughData: false, dataQualityNote: "El cuaderno necesita estado cargado.")
        }
        let className = classId.flatMap { id in classes.first(where: { $0.id == id })?.name }
        let rows = data.sheet.rows
        let averages = rows.compactMap { $0.weightedAverage?.doubleValue }
        let avg = averages.isEmpty ? 0.0 : averages.reduce(0, +) / Double(averages.count)
        let commentColumns = data.sheet.columns.filter { isNotebookAICommentColumn($0) }
        return ScreenAIContext(
            kind: .notebook,
            title: "Cuaderno",
            subtitle: className ?? "Grupo activo",
            classId: classId,
            className: className,
            studentId: nil,
            studentName: nil,
            summary: "Lectura del cuaderno con foco en medias, señales de seguimiento y comentarios IA por alumno.",
            metrics: [
                ReportMetric(title: "Alumnado", value: "\(rows.count)", systemImage: "person.3.fill"),
                ReportMetric(title: "Columnas", value: "\(data.sheet.columns.count)", systemImage: "tablecells"),
                ReportMetric(title: "Media grupo", value: IosFormatting.decimal(from: avg), systemImage: "sum"),
                ReportMetric(title: "Comentarios IA", value: "\(commentColumns.count)", systemImage: "apple.intelligence")
            ],
            factLines: compactSuggestions(
                "Filas del cuaderno: \(rows.count).",
                "Columnas visibles/configuradas: \(data.sheet.columns.count).",
                "Media aproximada del grupo: \(IosFormatting.decimal(from: avg)).",
                commentColumns.isEmpty ? "Todavía no hay columnas de comentario IA." : "Columnas de comentario IA detectadas: \(commentColumns.map(\.title).joined(separator: ", "))."
            ),
            supportNotes: [],
            suggestedActions: [
                ContextualAIAction(actionId: .notebookGroupSummary, title: "Resumen del cuaderno", subtitle: "Lectura global del grupo", systemImage: "tablecells.badge.ellipsis", promptHint: "Resume el estado general del cuaderno del grupo."),
                ContextualAIAction(actionId: .notebookStudentComment, title: "Comentario por alumno", subtitle: "Texto breve editable", systemImage: "person.text.rectangle.fill", promptHint: "Genera comentario breve por alumno usando columnas visibles."),
                ContextualAIAction(actionId: .observationProposal, title: "Observaciones", subtitle: "Propón observaciones accionables", systemImage: "note.text.badge.plus", promptHint: "Sugiere observaciones breves para el grupo.")
            ],
            hasEnoughData: !rows.isEmpty && !data.sheet.columns.isEmpty,
            dataQualityNote: rows.isEmpty ? "El cuaderno no tiene alumnado o filas visibles." : nil
        )
    }

    func getAITrendsAndMetrics(classId: Int64, studentId: Int64?) async throws -> AITrendsSnapshot {
        let kotlinSnapshot = try await container.getAITrendsAndMetrics.invoke(
            classId: classId,
            studentId: studentId.map { KotlinLong(value: $0) }
        )
        return AITrendsSnapshot(
            trendDirection: kotlinSnapshot.trendDirection,
            averageGradeDelta: kotlinSnapshot.averageGradeDelta,
            attendanceCorrelationNote: kotlinSnapshot.attendanceCorrelationNote,
            behaviorIncidentSummary: kotlinSnapshot.behaviorIncidentSummary,
            curriculumCoveragePct: kotlinSnapshot.curriculumCoveragePct,
            missingCompetencyLabels: kotlinSnapshot.missingCompetencyLabels,
            recentGrades: kotlinSnapshot.recentGrades.map { $0.doubleValue },
            attendanceRate: kotlinSnapshot.attendanceRate
        )
    }

    func generateNotebookAICommentContexts(
        includedColumnIds: [String],
        studentIds: [Int64]? = nil
    ) async -> [NotebookAICommentContext] {
        guard let data = notebookState as? NotebookUiStateData,
              let classId = notebookViewModel.currentClassId?.int64Value,
              let schoolClass = classes.first(where: { $0.id == classId })
        else { return [] }

        let selectedColumns = data.sheet.columns.filter { includedColumnIds.contains($0.id) }
        let columnCategoryNames = Dictionary(
            data.sheet.columnCategories.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let filteredRows = data.sheet.rows.filter { row in
            guard let studentIds else { return true }
            return studentIds.contains(row.student.id)
        }

        var contexts: [NotebookAICommentContext] = []
        for row in filteredRows {
            let insight = data.sheet.insights.first(where: { $0.studentId == row.student.id })
            let values = selectedColumns.compactMap { column -> NotebookAIColumnValue? in
                let value = notebookDisplayValue(for: row, column: column)
                guard !value.isEmpty else { return nil }
                return NotebookAIColumnValue(
                    title: column.title,
                    value: value,
                    categoryLabel: column.categoryId.flatMap { columnCategoryNames[$0] } ?? notebookCategoryLabel(column.categoryKind)
                )
            }
            let existingCommentColumn = data.sheet.columns.first(where: isNotebookAICommentColumn)
            let existingComment = existingCommentColumn.map { cellText(studentId: row.student.id, columnId: $0.id) }.flatMap { $0.nilIfBlank }
            let averageValue = row.weightedAverage?.doubleValue
            let averageText = averageValue.map { IosFormatting.decimal(from: $0) } ?? "Sin media"
            let trends = try? await getAITrendsAndMetrics(classId: classId, studentId: row.student.id)
            
            contexts.append(
                NotebookAICommentContext(
                    classId: classId,
                    className: schoolClass.name,
                    studentId: row.student.id,
                    studentName: row.student.fullName,
                    averageScore: averageValue,
                    attendanceStatus: insight?.latestAttendanceStatus,
                    followUpCount: Int(insight?.followUpCount ?? 0),
                    incidentCount: Int(insight?.incidentCount ?? 0),
                    evidenceCount: Int(insight?.evidenceCount ?? 0),
                    competencyLabels: insight?.linkedCompetencyLabels ?? [],
                    relevantValues: values,
                    existingComment: existingComment,
                    summary: "Alumno \(row.student.fullName) con media \(averageText), \(values.count) evidencias de cuaderno y seguimiento complementario.",
                    hasEnoughData: averageValue != nil || !values.isEmpty || Int(insight?.incidentCount ?? 0) > 0 || Int(insight?.evidenceCount ?? 0) > 0,
                    dataQualityNote: values.isEmpty ? "Hay pocas columnas con dato visible para este alumno." : nil,
                    trends: trends
                )
            )
        }
        return contexts
    }

    func createNotebookAICommentColumn(
        name: String,
        categoryKind: NotebookColumnCategoryKind = .followUp
    ) -> String? {
        guard let classId = notebookViewModel.currentClassId?.int64Value else { return nil }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let columnId = "COL_AI_\(nowMillis)"
        let nowMs = KotlinLong(value: nowMillis)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMillis)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let column = NotebookColumnDefinition(
            id: columnId,
            title: normalized,
            type: .text,
            categoryKind: categoryKind,
            instrumentKind: .privateComment,
            inputKind: .text,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: 0,
            dateEpochMs: nowMs,
            unitOrSituation: "Comentario IA",
            competencyCriteriaIds: [],
            scaleKind: .custom,
            tabIds: selectedNotebookTabId.map { [$0] } ?? [],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "3D7DFF",
            iconName: "apple.intelligence",
            order: -1,
            widthDp: 220,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: false,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        saveColumn(column: column)
        return columnId
    }

    func saveNotebookAIComment(studentId: Int64, columnId: String, text: String) {
        guard let data = notebookState as? NotebookUiStateData,
              let column = data.sheet.columns.first(where: { $0.id == columnId }) else { return }
        saveColumnGrade(studentId: studentId, column: column, value: text)
    }

    func createNotebookAICommentColumnForClass(
        classId: Int64,
        name: String,
        categoryKind: NotebookColumnCategoryKind = .followUp
    ) async throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NSError(domain: "KmpBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "El nombre de la columna no puede estar vacío."])
        }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let columnId = "COL_AI_\(nowMillis)"
        let nowMs = KotlinLong(value: nowMillis)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMillis)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let tabIds = selectedNotebookTabId.map { [$0] } ?? tabs.first.map { [$0.id] } ?? []
        let column = NotebookColumnDefinition(
            id: columnId,
            title: normalized,
            type: .text,
            categoryKind: categoryKind,
            instrumentKind: .privateComment,
            inputKind: .text,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: 0,
            dateEpochMs: nowMs,
            unitOrSituation: "Comentario IA",
            competencyCriteriaIds: [],
            scaleKind: .custom,
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "3D7DFF",
            iconName: "apple.intelligence",
            order: -1,
            widthDp: 260,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: false,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        return columnId
    }

    func saveNotebookAICommentDirect(
        classId: Int64,
        studentId: Int64,
        columnId: String,
        text: String
    ) async throws {
        try await container.notebookRepository.saveCell(
            classId: classId,
            studentId: studentId,
            columnId: columnId,
            textValue: text,
            boolValue: nil,
            iconValue: nil,
            ordinalValue: nil,
            note: nil,
            colorHex: nil,
            attachmentUris: [],
            authorUserId: nil,
            associatedGroupId: nil
        )
    }

    func notebookTextCell(classId: Int64, studentId: Int64, columnId: String) async throws -> String {
        let cells = try await container.notebookCellsRepository.listClassCells(classId: classId)
        return cells.first { $0.studentId == studentId && $0.columnId == columnId }?.textValue ?? ""
    }

    func recordAIAuditEvent(
        service: String,
        useCase: String,
        reportKind: String? = nil,
        classId: Int64? = nil,
        studentId: Int64? = nil,
        availability: String,
        modelAvailable: Bool,
        success: Bool,
        durationMs: Int64,
        errorKind: String? = nil,
        errorMessage: String? = nil
    ) async {
        let createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        let studentHash = studentId.map { anonymizedStudentHash($0) }
        let event = AIAuditEvent(
            id: 0,
            createdAtEpochMs: createdAt,
            service: service,
            useCase: useCase,
            reportKind: reportKind,
            classId: classId.map { KotlinLong(value: $0) },
            studentHash: studentHash,
            availability: availability,
            modelAvailable: modelAvailable,
            success: success,
            durationMs: durationMs,
            errorKind: errorKind,
            errorMessage: errorMessage
        )
        try? await container.aiAuditRepository.recordEvent(event: event)
    }

    func aiAuditTotalsByUseCase() async throws -> [AIAuditUseCaseTotal] {
        try await container.aiAuditRepository.totalsByUseCase()
    }

    func recentAIAuditFailures(limit: Int64 = 20) async throws -> [AIAuditEvent] {
        try await container.aiAuditRepository.recentFailures(limit: limit)
    }

    private func anonymizedStudentHash(_ studentId: Int64) -> String {
        let payload = "\(localDeviceId)|\(studentId)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func isNotebookAICommentColumn(_ column: NotebookColumnDefinition) -> Bool {
        column.type == .text &&
        column.instrumentKind == .privateComment &&
        column.inputKind == .text &&
        !column.countsTowardAverage &&
        column.iconName == "apple.intelligence"
    }

    func buildPrebuiltAnalyticsCharts(
        classId: Int64,
        timeRange: AnalyticsTimeRange = .last30Days
    ) async throws -> [ChartFacts] {
        let attendanceTrend = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .attendanceTrend,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Evolución reciente de asistencia del grupo."
            )
        )
        let attendanceComparison = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .attendanceComparison,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Comparativa de asistencia entre grupos del mismo curso."
            )
        )
        let incidentHeatmap = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .incidentHeatmap,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Patrones de incidencias por día de la semana."
            )
        )
        let uniformComparison = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .uniformComparison,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Comparativa de faltas de equipación entre grupos."
            )
        )
        let averagesRanking = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .groupAveragesRanking,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Ranking de medias entre grupos del mismo curso."
            )
        )
        let sameCourseComparison = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .sameCourseComparison,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Comparativa global del mismo curso."
            )
        )
        return [
            attendanceTrend,
            attendanceComparison,
            incidentHeatmap,
            uniformComparison,
            averagesRanking,
            sameCourseComparison,
        ]
    }

    func resolveAnalyticsRequest(
        classId: Int64,
        prompt: String,
        timeRange: AnalyticsTimeRange = .last30Days,
        selectedClassIds: [Int64] = []
    ) async throws -> AnalyticsRequest {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }

        let allClasses = try await container.classesRepository.listClasses()
        let relatedClasses = relatedClasses(for: schoolClass, allClasses: allClasses)
        let normalizedPrompt = normalizedAnalyticsText(prompt)
        let resolvedChartKind: ChartKind

        if normalizedPrompt.contains("equip") || normalizedPrompt.contains("uniform") {
            resolvedChartKind = .uniformComparison
        } else if normalizedPrompt.contains("inciden") || normalizedPrompt.contains("conviven") || normalizedPrompt.contains("alerta") {
            resolvedChartKind = .incidentHeatmap
        } else if normalizedPrompt.contains("media") || normalizedPrompt.contains("nota") || normalizedPrompt.contains("promedio") || normalizedPrompt.contains("rendimiento") {
            resolvedChartKind = normalizedPrompt.contains("compar") ? .sameCourseComparison : .groupAveragesRanking
        } else if normalizedPrompt.contains("compar") || normalizedPrompt.contains("grupo") || normalizedPrompt.contains("curso") {
            resolvedChartKind = .attendanceComparison
        } else {
            resolvedChartKind = .attendanceTrend
        }

        let requestedIds = Array(Set(selectedClassIds + relatedClasses
            .filter { candidate in
                let normalizedName = normalizedAnalyticsText(candidate.name)
                return normalizedPrompt.contains(normalizedName)
            }
            .map(\.id)
        )).sorted()
        let finalIds = requestedIds.isEmpty ? [classId] : requestedIds
        let finalNames = relatedClasses
            .filter { finalIds.contains($0.id) }
            .map(\.name)

        return AnalyticsRequest(
            chartKind: resolvedChartKind,
            timeRange: timeRange,
            selectedClassIds: finalIds,
            selectedClassNames: finalNames,
            prompt: prompt.nilIfBlank,
            querySummary: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func buildChartFacts(
        classId: Int64,
        request: AnalyticsRequest
    ) async throws -> ChartFacts {
        guard let primaryClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }

        let allClasses = try await container.classesRepository.listClasses()
        let relatedClasses = relatedClasses(for: primaryClass, allClasses: allClasses)
        let comparisonClasses = relatedClasses.filter { schoolClass in
            request.selectedClassIds.isEmpty || request.selectedClassIds.contains(schoolClass.id)
        }

        switch request.chartKind {
        case .attendanceTrend:
            return try await buildAttendanceTrendFacts(for: primaryClass, timeRange: request.timeRange, prompt: request.prompt)
        case .attendanceComparison:
            return try await buildAttendanceComparisonFacts(for: primaryClass, comparisonClasses: comparisonClasses, timeRange: request.timeRange, prompt: request.prompt)
        case .incidentHeatmap:
            return try await buildIncidentHeatmapFacts(for: primaryClass, timeRange: request.timeRange, prompt: request.prompt)
        case .uniformComparison:
            return try await buildUniformComparisonFacts(for: primaryClass, comparisonClasses: comparisonClasses, timeRange: request.timeRange, prompt: request.prompt)
        case .groupAveragesRanking:
            return try await buildGroupAveragesRankingFacts(for: primaryClass, comparisonClasses: comparisonClasses, prompt: request.prompt)
        case .sameCourseComparison:
            return try await buildSameCourseComparisonFacts(for: primaryClass, comparisonClasses: comparisonClasses, prompt: request.prompt)
        }
    }

    private func buildAttendanceTrendFacts(
        for schoolClass: SchoolClass,
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let history = try await attendanceHistory(for: schoolClass.id, days: timeRange.dayCount)
        let grouped = Dictionary(grouping: history) { record in
            Calendar.current.startOfDay(for: record.date)
        }
        let dates = grouped.keys.sorted()
        let points = dates.map { day -> ChartPoint in
            let records = grouped[day, default: []]
            let present = records.filter { isPresentStatus($0.status) }.count
            let rate = records.isEmpty ? 0.0 : (Double(present) / Double(records.count)) * 100.0
            return ChartPoint(
                label: shortDateLabel(day),
                value: rate,
                note: records.isEmpty ? "Sin marcaje" : "\(present)/\(records.count) presentes"
            )
        }
        let average = points.isEmpty ? 0.0 : points.map(\.value).reduce(0, +) / Double(points.count)
        let lowDays = points.filter { $0.value > 0 && $0.value < 85 }.count
        let digest = lowDays > 0
            ? "La asistencia del grupo muestra \(lowDays) jornadas por debajo del umbral del 85%."
            : "La asistencia del grupo mantiene un patrón estable en el periodo analizado."
        return ChartFacts(
            chartKind: .attendanceTrend,
            title: schoolClass.name,
            subtitle: prompt ?? "Evolución diaria de la asistencia registrada.",
            chartType: ChartKind.attendanceTrend.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.attendanceTrend.groupingLabel,
            metrics: [
                ReportMetric(title: "Sesiones con registro", value: "\(points.count)", systemImage: "calendar"),
                ReportMetric(title: "Asistencia media", value: "\(Int(average.rounded()))%", systemImage: "checklist.checked"),
                ReportMetric(title: "Días frágiles", value: "\(lowDays)", systemImage: "exclamationmark.triangle.fill"),
            ],
            factLines: compactSuggestions(
                "Grupo analizado: \(schoolClass.name).",
                "Serie temporal calculada a partir de \(history.count) registros de asistencia.",
                points.last.map { "Último valor: \(Int($0.value.rounded()))% el \($0.label)." }
            ),
            highlights: compactSuggestions(
                average >= 90 ? "La asistencia media del periodo es sólida." : nil,
                points.last.map { $0.value > average ? "La última sesión mejora la media del periodo." : nil } ?? nil
            ),
            warnings: compactSuggestions(
                points.isEmpty ? "No hay datos de asistencia suficientes para dibujar una serie temporal." : nil,
                lowDays > 1 ? "Hay varias jornadas con asistencia claramente baja." : nil
            ),
            series: [
                ChartSeries(name: "Asistencia", colorToken: "blue", points: points)
            ],
            heatmapCells: [],
            hasEnoughData: !points.isEmpty,
            emptyStateMessage: "Todavía no hay marcajes suficientes para construir la evolución de asistencia.",
            teacherDigest: digest,
            insertableSummary: "Asistencia media del periodo: \(Int(average.rounded()))%."
        )
    }

    private func buildAttendanceComparisonFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let classesToCompare = comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses
        var points: [ChartPoint] = []
        for item in classesToCompare {
            let history = try await attendanceHistory(for: item.id, days: timeRange.dayCount)
            let present = history.filter { isPresentStatus($0.status) }.count
            let rate = history.isEmpty ? 0.0 : (Double(present) / Double(history.count)) * 100.0
            points.append(ChartPoint(label: item.name, value: rate, note: "\(history.count) registros"))
        }
        let sorted = points.sorted { $0.value > $1.value }
        let spread = (sorted.first?.value ?? 0) - (sorted.last?.value ?? 0)
        return ChartFacts(
            chartKind: .attendanceComparison,
            title: "Curso \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Comparativa de asistencia entre grupos equivalentes.",
            chartType: ChartKind.attendanceComparison.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.attendanceComparison.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(sorted.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Mejor tasa", value: "\(Int((sorted.first?.value ?? 0).rounded()))%", systemImage: "arrow.up.right"),
                ReportMetric(title: "Brecha", value: "\(Int(spread.rounded())) pt", systemImage: "arrow.left.and.right")
            ],
            factLines: compactSuggestions(
                "Se comparan grupos del mismo curso: \(sorted.map(\.label).joined(separator: ", ")).",
                sorted.first.map { "Mejor dato de asistencia: \($0.label) con \(Int($0.value.rounded()))%." },
                sorted.last.map { "Dato más bajo: \($0.label) con \(Int($0.value.rounded()))%." }
            ),
            highlights: compactSuggestions(
                spread < 5 ? "Las diferencias entre grupos son reducidas." : nil,
                sorted.first.map { "\($0.label) destaca en regularidad de asistencia." }
            ),
            warnings: compactSuggestions(
                sorted.count < 2 ? "Solo hay un grupo comparable en este curso." : nil,
                spread >= 10 ? "La brecha entre grupos ya merece seguimiento docente." : nil
            ),
            series: [
                ChartSeries(name: "Asistencia", colorToken: "green", points: sorted)
            ],
            heatmapCells: [],
            hasEnoughData: !sorted.isEmpty,
            emptyStateMessage: "No hay grupos comparables con datos de asistencia suficientes.",
            teacherDigest: spread >= 10
                ? "La asistencia presenta diferencias significativas entre grupos del mismo curso."
                : "La asistencia entre grupos del mismo curso se mueve en una franja relativamente estable.",
            insertableSummary: "Comparativa de asistencia entre grupos del mismo curso con una brecha de \(Int(spread.rounded())) puntos."
        )
    }

    private func buildIncidentHeatmapFacts(
        for schoolClass: SchoolClass,
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let incidents = try await incidents(for: schoolClass.id)

        // Semana escolar: empieza en lunes, y las filas son semanas naturales,
        // no ventanas móviles de 7 días contadas desde hoy. Con el reparto
        // anterior, el viernes de una semana y el lunes de la siguiente caían
        // en la misma fila, que es justo el eje que da sentido al gráfico.
        let calendar = Calendar.current

        // Lunes de la semana de `date`, calculado a mano a partir del día de la
        // semana. Deliberadamente NO se usa `dateInterval(of: .weekOfYear:)`:
        // depende de `firstWeekday` y de la configuración regional, y su rama de
        // fallo obliga a un fallback que, si se activa, convierte las filas en
        // días sueltos y deja la rejilla entera a cero sin avisar.
        func startOfWeek(for date: Date) -> Date {
            let day = calendar.startOfDay(for: date)
            // `weekday`: 1 = domingo … 7 = sábado. Lunes -> 0, domingo -> 6.
            let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
            return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
        }

        // Días en el orden lectivo L→D. `Calendar.component(.weekday)` devuelve
        // 1 = domingo … 7 = sábado; el bucle anterior iteraba 2...8, así que la
        // columna del domingo nunca podía recibir nada y el propio domingo no
        // se contaba en ninguna columna.
        let weekdayColumns: [(symbol: String, weekday: Int)] = [
            ("L", 2), ("M", 3), ("X", 4), ("J", 5), ("V", 6), ("S", 7), ("D", 1)
        ]

        let weeksBack = max(2, min(6, timeRange.dayCount / 14 + 1))
        let currentWeekStart = startOfWeek(for: Date())
        let oldestWeekStart = calendar.date(byAdding: .weekOfYear, value: -(weeksBack - 1), to: currentWeekStart) ?? currentWeekStart

        // El recorte es el inicio de la semana más antigua que se pinta, no
        // `timeRange.dayCount` días naturales: así el total y el pico describen
        // exactamente lo que se ve en la rejilla y no un periodo más ancho.
        let filtered = incidents.filter {
            Date(timeIntervalSince1970: TimeInterval($0.date.epochSeconds)) >= oldestWeekStart
        }

        let weekLabelFormatter = DateFormatter()
        weekLabelFormatter.locale = Locale(identifier: "es_ES")
        weekLabelFormatter.setLocalizedDateFormatFromTemplate("d/M")

        // De la semana más antigua a la más reciente, para que la rejilla se lea
        // de arriba abajo en orden cronológico. Las etiquetas son la fecha del
        // lunes de cada semana: `S-1`…`S-6` se leía al revés de lo que sugiere.
        var cells: [HeatmapCell] = []
        for offset in stride(from: weeksBack - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) else { continue }
            let weekLabel = weekLabelFormatter.string(from: weekStart)
            for column in weekdayColumns {
                let count = filtered.filter { incident in
                    let date = Date(timeIntervalSince1970: TimeInterval(incident.date.epochSeconds))
                    // Comparación por día, no por `Date` exacta: los cambios de
                    // hora dejan medianoches que no son iguales al segundo.
                    return calendar.isDate(startOfWeek(for: date), inSameDayAs: weekStart)
                        && calendar.component(.weekday, from: date) == column.weekday
                }.count
                cells.append(
                    HeatmapCell(
                        rowLabel: weekLabel,
                        columnLabel: column.symbol,
                        value: Double(count)
                    )
                )
            }
        }
        let total = filtered.count
        let maxCell = cells.max(by: { $0.value < $1.value })
        return ChartFacts(
            chartKind: .incidentHeatmap,
            title: schoolClass.name,
            subtitle: prompt ?? "Concentración de incidencias por semana y día lectivo.",
            chartType: ChartKind.incidentHeatmap.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.incidentHeatmap.groupingLabel,
            metrics: [
                ReportMetric(title: "Incidencias", value: "\(total)", systemImage: "exclamationmark.bubble.fill"),
                ReportMetric(title: "Pico", value: "\(Int(maxCell?.value ?? 0))", systemImage: "flame.fill"),
                ReportMetric(title: "Semanas", value: "\(weeksBack)", systemImage: "calendar.badge.clock")
            ],
            factLines: compactSuggestions(
                "Se han revisado \(total) incidencias en el periodo seleccionado.",
                maxCell.map { "Mayor concentración: semana del \($0.rowLabel), \($0.columnLabel), con \(Int($0.value)) incidencias." }
            ),
            highlights: compactSuggestions(
                total == 0 ? "No hay incidencias registradas en el periodo." : nil,
                maxCell.map { $0.value <= 1 ? "Las incidencias aparecen dispersas y sin patrón fuerte." : nil } ?? nil
            ),
            warnings: compactSuggestions(
                total >= 5 ? "Ya hay una masa crítica de incidencias como para revisar patrones de grupo." : nil
            ),
            series: [],
            heatmapCells: cells,
            hasEnoughData: !cells.isEmpty,
            emptyStateMessage: "No hay datos suficientes para construir el heatmap de incidencias.",
            teacherDigest: total == 0
                ? "No se observan incidencias recientes en el grupo."
                : "El heatmap permite localizar los días con mayor concentración de incidencias.",
            insertableSummary: total == 0
                ? "Sin incidencias registradas en el periodo analizado."
                : "Heatmap de incidencias con \(total) registros en el periodo."
        )
    }

    private func buildUniformComparisonFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let classesToCompare = comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses
        var points: [ChartPoint] = []
        for item in classesToCompare {
            let count = try await unequippedEventsCount(for: item.id, sinceDays: timeRange.dayCount)
            points.append(ChartPoint(label: item.name, value: Double(count), note: "Sesiones con alumnado sin equipación"))
        }
        let sorted = points.sorted { $0.value > $1.value }
        return ChartFacts(
            chartKind: .uniformComparison,
            title: "Operativa EF · \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Comparativa de faltas de equipación o registros equivalentes en diarios.",
            chartType: ChartKind.uniformComparison.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.uniformComparison.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(sorted.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Máximo", value: "\(Int(sorted.first?.value ?? 0))", systemImage: "arrow.up.right"),
                ReportMetric(title: "Total", value: "\(Int(sorted.map(\.value).reduce(0, +)))", systemImage: "sum")
            ],
            factLines: compactSuggestions(
                "Se han usado los diarios de sesión y el campo de alumnado sin equipación.",
                sorted.first.map { "Mayor carga operativa: \($0.label) con \(Int($0.value)) registros." }
            ),
            highlights: compactSuggestions(
                sorted.allSatisfy { $0.value == 0 } ? "No constan faltas de equipación recientes en los grupos comparados." : nil
            ),
            warnings: compactSuggestions(
                "Esta vista depende de que el diario de EF se complete con regularidad."
            ),
            series: [
                ChartSeries(name: "Sin equipación", colorToken: "orange", points: sorted)
            ],
            heatmapCells: [],
            hasEnoughData: !sorted.isEmpty,
            emptyStateMessage: "No hay grupos o diarios suficientes para comparar faltas de equipación.",
            teacherDigest: sorted.allSatisfy { $0.value == 0 }
                ? "No aparecen faltas de equipación en el periodo analizado."
                : "Las faltas de equipación se concentran en algunos grupos concretos y pueden tratarse como señal operativa.",
            insertableSummary: "Comparativa de faltas de equipación entre grupos del mismo curso."
        )
    }

    private func buildGroupAveragesRankingFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        prompt: String?
    ) async throws -> ChartFacts {
        let classesToCompare = comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses
        var points: [ChartPoint] = []
        for item in classesToCompare {
            let summary = try await loadCourseSummary(classId: item.id)
            points.append(ChartPoint(label: item.name, value: summary.averageScore, note: "Media del grupo"))
        }
        let sorted = points.sorted { $0.value > $1.value }
        let gap = (sorted.first?.value ?? 0) - (sorted.last?.value ?? 0)
        return ChartFacts(
            chartKind: .groupAveragesRanking,
            title: "Ranking · \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Ordenación de medias registradas por grupo.",
            chartType: ChartKind.groupAveragesRanking.chartTypeLabel,
            timeRange: "Curso actual",
            grouping: ChartKind.groupAveragesRanking.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(sorted.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Mejor media", value: IosFormatting.decimal(from: sorted.first?.value), systemImage: "arrow.up.right"),
                ReportMetric(title: "Brecha", value: IosFormatting.decimal(from: gap), systemImage: "arrow.left.and.right")
            ],
            factLines: compactSuggestions(
                sorted.first.map { "Media más alta: \($0.label) con \(IosFormatting.decimal(from: $0.value))." },
                sorted.last.map { "Media más baja: \($0.label) con \(IosFormatting.decimal(from: $0.value))." }
            ),
            highlights: compactSuggestions(
                gap < 1.0 ? "Las medias entre grupos son bastante homogéneas." : nil,
                sorted.first.map { "\($0.label) lidera el ranking de rendimiento registrado." }
            ),
            warnings: compactSuggestions(
                sorted.contains(where: { $0.value == 0 }) ? "Algún grupo todavía no tiene media consolidada." : nil
            ),
            series: [
                ChartSeries(name: "Media", colorToken: "purple", points: sorted)
            ],
            heatmapCells: [],
            hasEnoughData: !sorted.isEmpty,
            emptyStateMessage: "No hay datos suficientes para construir el ranking de medias.",
            teacherDigest: gap >= 1.5
                ? "Las medias entre grupos muestran una brecha relevante."
                : "Las medias entre grupos del mismo curso son relativamente cercanas.",
            insertableSummary: "Ranking de medias entre grupos del mismo curso."
        )
    }

    private func buildSameCourseComparisonFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        prompt: String?
    ) async throws -> ChartFacts {
        let snapshot = try await container.getOperationalDashboardSnapshot.invoke(
            mode: .office,
            filters: DashboardFilters(classId: nil, severity: nil, priority: nil, sessionStatus: nil)
        )
        let allowedIds = Set((comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses).map(\.id))
        let summaries = snapshot.groupSummaries.filter { allowedIds.contains($0.classId) }
        let attendancePoints = summaries.map {
            ChartPoint(label: $0.groupName, value: Double($0.attendancePct), note: "Asistencia")
        }
        let evaluationPoints = summaries.map {
            ChartPoint(label: $0.groupName, value: Double($0.evaluationCompletedPct), note: "Evaluación completada")
        }
        let averagePoints = summaries.map {
            ChartPoint(label: $0.groupName, value: $0.averageScore * 10.0, note: "Media normalizada x10")
        }
        return ChartFacts(
            chartKind: .sameCourseComparison,
            title: "Comparativa global · \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Asistencia, evaluación completada y media normalizada por grupo.",
            chartType: ChartKind.sameCourseComparison.chartTypeLabel,
            timeRange: "Curso actual",
            grouping: ChartKind.sameCourseComparison.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(summaries.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Seguimiento", value: "\(summaries.map(\.studentsInFollowUp).reduce(0, +))", systemImage: "arrow.triangle.branch"),
                ReportMetric(title: "Media curso", value: IosFormatting.decimal(from: summaries.isEmpty ? nil : summaries.map(\.averageScore).reduce(0, +) / Double(summaries.count)), systemImage: "sum")
            ],
            factLines: compactSuggestions(
                summaries.isEmpty ? "No hay resúmenes operativos de grupo disponibles." : "Se comparan \(summaries.count) grupos del mismo curso.",
                summaries.max(by: { $0.attendancePct < $1.attendancePct }).map { "Mayor asistencia: \($0.groupName) con \($0.attendancePct)%." },
                summaries.max(by: { $0.averageScore < $1.averageScore }).map { "Mejor media: \($0.groupName) con \(IosFormatting.decimal(from: $0.averageScore))." }
            ),
            highlights: compactSuggestions(
                summaries.filter { $0.studentsInFollowUp == 0 }.isEmpty ? nil : "Hay grupos sin alumnado en seguimiento activo."
            ),
            warnings: compactSuggestions(
                summaries.isEmpty ? "No hay suficientes datos agregados para una comparativa global." : nil
            ),
            series: [
                ChartSeries(name: "Asistencia %", colorToken: "green", points: attendancePoints),
                ChartSeries(name: "Evaluación %", colorToken: "blue", points: evaluationPoints),
                ChartSeries(name: "Media x10", colorToken: "purple", points: averagePoints)
            ],
            heatmapCells: [],
            hasEnoughData: !summaries.isEmpty,
            emptyStateMessage: "Faltan resúmenes de grupo para construir la comparativa global.",
            teacherDigest: summaries.isEmpty
                ? "La comparativa global necesita más datos agregados."
                : "La comparativa global permite ver de un vistazo la relación entre asistencia, avance evaluativo y media del grupo.",
            insertableSummary: "Comparativa global entre grupos del mismo curso."
        )
    }

    private func relatedClasses(for schoolClass: SchoolClass, allClasses: [SchoolClass]) -> [SchoolClass] {
        let filtered = allClasses.filter { $0.course == schoolClass.course }
        return filtered.isEmpty ? [schoolClass] : filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func unequippedEventsCount(for classId: Int64, sinceDays days: Int) async throws -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let sessions = try await container.plannerRepository.listAllSessions()
            .filter { $0.groupId == classId && date(from: $0) >= cutoff }
        var count = 0
        for session in sessions {
            guard let aggregate = try? await container.sessionJournalRepository.getJournalForSession(planningSessionId: session.id) else {
                continue
            }
            let text = aggregate.journal.unequippedStudentsText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                count += max(1, tokenCount(in: text))
            }
        }
        return count
    }

    private func tokenCount(in text: String) -> Int {
        let separators = CharacterSet(charactersIn: ",;\n")
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func isPresentStatus(_ status: String) -> Bool {
        let normalized = normalizedAnalyticsText(status)
        return normalized.contains("present")
    }

    private func normalizedAnalyticsText(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func notebookDisplayValue(for row: NotebookRow, column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric:
            if let persisted = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
                return IosFormatting.decimal(from: persisted)
            }
            if let evaluationId = column.evaluationId?.int64Value,
               let cellValue = row.cells.first(where: { $0.evaluationId == evaluationId })?.value?.doubleValue {
                return IosFormatting.decimal(from: cellValue)
            }
            return ""
        case .rubric:
            if let persisted = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
                return IosFormatting.decimal(from: persisted)
            }
            return ""
        case .check:
            if let boolValue = row.persistedCells.first(where: { $0.columnId == column.id })?.boolValue?.boolValue {
                return boolValue ? "Sí" : "No"
            }
            return ""
        case .ordinal:
            return row.persistedCells.first(where: { $0.columnId == column.id })?.ordinalValue ?? ""
        default:
            return row.persistedCells.first(where: { $0.columnId == column.id })?.textValue ?? ""
        }
    }

    private func notebookCategoryLabel(_ kind: NotebookColumnCategoryKind) -> String {
        if kind == .evaluation { return "Evaluación" }
        if kind == .followUp { return "Seguimiento" }
        if kind == .attendance { return "Asistencia" }
        if kind == .extras { return "Extras" }
        if kind == .physicalEducation { return "Educación Física" }
        return "Personalizada"
    }

    private func fallbackString(_ value: String?, fallback: String) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? fallback
    }
}
