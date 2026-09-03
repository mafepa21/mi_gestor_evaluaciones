import Foundation
import MiGestorKit

/// Definición y catálogo oficial de periodos evaluativos, salidas curriculares
/// e hitos colegiales del curso escolar 2026-2027 extraídos del claustro de inicio de curso.
enum SchoolCalendarPreset2026_2027 {
    static let academicYearName = "Curso 2026-2027"
    static let startDateIso = "2026-09-01"
    static let endDateIso = "2027-06-30"

    // MARK: - Etapas de evaluación

    enum Stage: String, CaseIterable, Identifiable {
        case eso = "ESO"
        case bach1 = "1º Bachillerato"
        case bach2 = "2º Bachillerato"

        var id: String { rawValue }

        var title: String { rawValue }

        var subtitle: String {
            switch self {
            case .eso:
                return "1ª Eva: 27 nov · 2ª Eva: 5 mar · 3ª Eva: 4 jun"
            case .bach1:
                return "1ª Eva: 24 nov · 2ª Eva: 1 mar · 3ª Eva: 3 jun"
            case .bach2:
                return "1ª Eva: 20 nov · 2ª Eva: 19 feb · 3ª Eva: 4 may (PAU)"
            }
        }

        var periods: [EvaluationPeriodPreset] {
            switch self {
            case .eso:
                return [
                    EvaluationPeriodPreset(
                        name: "1ª Evaluación",
                        startDateIso: "2026-09-08",
                        endDateIso: "2026-11-27",
                        sortOrder: 1,
                        notes: "Último día evaluar: 27 nov · Notas Educamos: 29 nov · Sesión: 2-3 dic"
                    ),
                    EvaluationPeriodPreset(
                        name: "2ª Evaluación",
                        startDateIso: "2026-11-30",
                        endDateIso: "2027-03-05",
                        sortOrder: 2,
                        notes: "Último día evaluar: 5 mar · Notas Educamos: 7 mar · Sesión: 10-11 mar"
                    ),
                    EvaluationPeriodPreset(
                        name: "3ª Evaluación",
                        startDateIso: "2027-03-08",
                        endDateIso: "2027-06-04",
                        sortOrder: 3,
                        notes: "Último día evaluar: 4 jun · Notas Educamos: 6 jun · Sesión: 8-10 jun · Notas: 21 jun"
                    )
                ]
            case .bach1:
                return [
                    EvaluationPeriodPreset(
                        name: "1ª Evaluación (1º Bach)",
                        startDateIso: "2026-09-08",
                        endDateIso: "2026-11-24",
                        sortOrder: 1,
                        notes: "Parciales: 8/13/14 oct · Globales: 20/23/24 nov · Sesión: 3 dic"
                    ),
                    EvaluationPeriodPreset(
                        name: "2ª Evaluación (1º Bach)",
                        startDateIso: "2026-11-25",
                        endDateIso: "2027-03-01",
                        sortOrder: 2,
                        notes: "Parciales: 22/25/26 ene · Globales: 25/26 feb, 1 mar · Sesión: 10 mar"
                    ),
                    EvaluationPeriodPreset(
                        name: "3ª Evaluación (1º Bach)",
                        startDateIso: "2027-03-02",
                        endDateIso: "2027-06-03",
                        sortOrder: 3,
                        notes: "Parciales: 16/19/20 abr · Globales: 20/21/24 may · Sesión: 7 jun · Notas: 10 jun"
                    )
                ]
            case .bach2:
                return [
                    EvaluationPeriodPreset(
                        name: "1ª Evaluación (2º Bach)",
                        startDateIso: "2026-09-08",
                        endDateIso: "2026-11-20",
                        sortOrder: 1,
                        notes: "Parciales: 8/13/14 oct · Globales: 12/13/16/17 nov · Sesión: 25 nov"
                    ),
                    EvaluationPeriodPreset(
                        name: "2ª Evaluación (2º Bach)",
                        startDateIso: "2026-11-23",
                        endDateIso: "2027-02-19",
                        sortOrder: 2,
                        notes: "Parciales: 11/12/13 ene · Globales: 11/12/15/16 feb · Sesión: 24 feb"
                    ),
                    EvaluationPeriodPreset(
                        name: "3ª Evaluación (2º Bach)",
                        startDateIso: "2027-02-22",
                        endDateIso: "2027-05-04",
                        sortOrder: 3,
                        notes: "Globales: 29/30 abr, 3/4 may · Sesión: 6 may · Final: 17 may · Graduación: 21 may"
                    )
                ]
            }
        }
    }

    struct EvaluationPeriodPreset: Identifiable {
        var id: String { name }
        let name: String
        let startDateIso: String
        let endDateIso: String
        let sortOrder: Int
        let notes: String
    }

    // MARK: - Salidas y viajes de curso

    struct TripPreset: Identifiable {
        let id: String
        let title: String
        let destination: String
        let targetGradeDescription: String
        let datesIso: [String]
        let dateRangeSummary: String
        let description: String
        let matchesCourse: (SchoolClass) -> Bool
    }

    static let allTrips: [TripPreset] = [
        TripPreset(
            id: "toledo_2eso",
            title: "Viaje a Toledo (2º ESO)",
            destination: "Toledo",
            targetGradeDescription: "2º ESO",
            datesIso: ["2027-05-10", "2027-05-11", "2027-05-12", "2027-05-13", "2027-05-14"],
            dateRangeSummary: "10 – 14 mayo 2027 (Semana 31)",
            description: "No lectivo · Salida 2º ESO: Viaje cultural a Toledo",
            matchesCourse: { matchesGrade($0, expectedLevel: 2, gradeKeywords: ["2º eso", "2 eso", "2eso", "2ºeso"]) }
        ),
        TripPreset(
            id: "pirineos_4eso",
            title: "Viaje a Pirineos (4º ESO)",
            destination: "Pirineos",
            targetGradeDescription: "4º ESO",
            datesIso: ["2027-05-10", "2027-05-11", "2027-05-12", "2027-05-13", "2027-05-14"],
            dateRangeSummary: "10 – 14 mayo 2027 (Semana 31)",
            description: "No lectivo · Salida 4º ESO: Viaje a Pirineos",
            matchesCourse: { matchesGrade($0, expectedLevel: 4, gradeKeywords: ["4º eso", "4 eso", "4eso", "4ºeso"]) }
        ),
        TripPreset(
            id: "agullent_1bach",
            title: "Convivencia Agullent (1º Bach)",
            destination: "Agullent",
            targetGradeDescription: "1º Bachillerato",
            datesIso: ["2027-03-05"],
            dateRangeSummary: "5 marzo 2027 (5-7 marzo claustro)",
            description: "No lectivo · Convivencia 1º Bach Agullent",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        TripPreset(
            id: "viaje_1bach",
            title: "Viaje 3 días 1º Bach (Roma / Granada / Tarragona)",
            destination: "Roma / Granada / Tarragona",
            targetGradeDescription: "1º Bachillerato",
            datesIso: ["2027-03-22", "2027-03-23", "2027-03-24"],
            dateRangeSummary: "22 – 24 marzo 2027 (Entre Fallas y S. Santa)",
            description: "No lectivo · Viaje cultural 1º Bachillerato",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        TripPreset(
            id: "agullent_2bach",
            title: "Convivencia Agullent (2º Bach)",
            destination: "Agullent",
            targetGradeDescription: "2º Bachillerato",
            datesIso: ["2027-03-08"],
            dateRangeSummary: "8 marzo 2027 (6-8 marzo claustro)",
            description: "No lectivo · Convivencia 2º Bach Agullent",
            matchesCourse: { matchesGrade($0, expectedLevel: 2, gradeKeywords: ["2º bach", "2 bach", "2bach", "2ºbach"]) }
        ),
        TripPreset(
            id: "estudio_pau_2bach",
            title: "Estudio autónomo PAU (2º Bach)",
            destination: "Centro / Domicilio",
            targetGradeDescription: "2º Bachillerato",
            datesIso: ["2027-05-24", "2027-05-25", "2027-05-26", "2027-05-27", "2027-05-28"],
            dateRangeSummary: "24 – 28 mayo 2027 (Previo a PAU 1-3 jun)",
            description: "No lectivo · Periodo de estudio autónomo PAU 2º Bach",
            matchesCourse: { matchesGrade($0, expectedLevel: 2, gradeKeywords: ["2º bach", "2 bach", "2bach", "2ºbach"]) }
        )
    ]

    // MARK: - Exámenes de 1º Bachillerato vinculados a sus grupos

    struct ExamPreset: Identifiable {
        let id: String
        let title: String
        let periodDescription: String
        let datesIso: [String]
        let dateRangeSummary: String
        let description: String
        let matchesCourse: (SchoolClass) -> Bool
    }

    static let all1BachExams: [ExamPreset] = [
        ExamPreset(
            id: "parciales_1eva_1bach",
            title: "Exámenes Parciales (1º Bach)",
            periodDescription: "1ª Evaluación",
            datesIso: ["2026-10-08", "2026-10-13", "2026-10-14"],
            dateRangeSummary: "8, 13, 14 octubre 2026",
            description: "No lectivo para 1º Bach · Exámenes parciales 1ª Evaluación",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "globales_1eva_1bach",
            title: "Exámenes Globales (1º Bach)",
            periodDescription: "1ª Evaluación",
            datesIso: ["2026-11-20", "2026-11-23", "2026-11-24"],
            dateRangeSummary: "20, 23, 24 noviembre 2026",
            description: "No lectivo para 1º Bach · Exámenes globales 1ª Evaluación",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "parciales_2eva_1bach",
            title: "Exámenes Parciales (1º Bach)",
            periodDescription: "2ª Evaluación",
            datesIso: ["2027-01-22", "2027-01-25", "2027-01-26"],
            dateRangeSummary: "22, 25, 26 enero 2027",
            description: "No lectivo para 1º Bach · Exámenes parciales 2ª Evaluación",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "globales_2eva_1bach",
            title: "Exámenes Globales (1º Bach)",
            periodDescription: "2ª Evaluación",
            datesIso: ["2027-02-25", "2027-02-26", "2027-03-01"],
            dateRangeSummary: "25, 26 febrero y 1 marzo 2027",
            description: "No lectivo para 1º Bach · Exámenes globales 2ª Evaluación",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "parciales_3eva_1bach",
            title: "Exámenes Parciales (1º Bach)",
            periodDescription: "3ª Evaluación",
            datesIso: ["2027-04-16", "2027-04-19", "2027-04-20"],
            dateRangeSummary: "16, 19, 20 abril 2027",
            description: "No lectivo para 1º Bach · Exámenes parciales 3ª Evaluación",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "globales_3eva_1bach",
            title: "Exámenes Globales (1º Bach)",
            periodDescription: "3ª Evaluación",
            datesIso: ["2027-05-20", "2027-05-21", "2027-05-24"],
            dateRangeSummary: "20, 21, 24 mayo 2027",
            description: "No lectivo para 1º Bach · Exámenes globales 3ª Evaluación",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "finales_ord_1bach",
            title: "Exámenes Finales Ordinarios (1º Bach)",
            periodDescription: "Convocatoria Ordinaria",
            datesIso: ["2027-06-01", "2027-06-02", "2027-06-03"],
            dateRangeSummary: "1, 2, 3 junio 2027",
            description: "No lectivo para 1º Bach · Convocatoria ordinaria final",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        ),
        ExamPreset(
            id: "extraord_1bach",
            title: "Exámenes Extraordinarios (1º Bach)",
            periodDescription: "Convocatoria Extraordinaria",
            datesIso: ["2027-06-17", "2027-06-18", "2027-06-21"],
            dateRangeSummary: "17, 18, 21 junio 2027",
            description: "No lectivo para 1º Bach · Convocatoria extraordinaria",
            matchesCourse: { matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach"]) }
        )
    ]

    // MARK: - Hitos colegiales y festivos de centro (sin classId)

    struct SchoolEventPreset: Identifiable {
        let id: String
        let title: String
        let dateIso: String
        let dateSummary: String
        let description: String
        let isNonTeaching: Bool
    }

    static let schoolWideEvents: [SchoolEventPreset] = [
        SchoolEventPreset(
            id: "convivencias_inicio",
            title: "Convivencias inicio de curso",
            dateIso: "2026-09-23",
            dateSummary: "Mié 23 sep 2026",
            description: "No lectivo ordinario · Convivencias de inicio de curso",
            isNonTeaching: true
        ),
        SchoolEventPreset(
            id: "dia_hhdc",
            title: "Día HHDC (Semana Colegial)",
            dateIso: "2026-11-18",
            dateSummary: "Mié 18 nov 2026",
            description: "Festivo colegial · Celebración Día HHDC",
            isNonTeaching: true
        ),
        SchoolEventPreset(
            id: "festival_navidad",
            title: "Festival de Navidad",
            dateIso: "2026-12-23",
            dateSummary: "Mié 23 dic 2026",
            description: "Celebración y festival de Navidad",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "dia_paz",
            title: "Día escolar de la No Violencia y la Paz",
            dateIso: "2027-01-29",
            dateSummary: "Vie 29 ene 2027",
            description: "Jornada escolar por la Paz",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "falla_crema",
            title: "Falla del colegio (Cremà)",
            dateIso: "2027-03-12",
            dateSummary: "Vie 12 mar 2027",
            description: "Falla colegial y actos de la Cremà",
            isNonTeaching: false
        )
    ]

    // MARK: - Hitos docentes e informativos (reuniones y notas)

    static let teacherMilestones: [SchoolEventPreset] = [
        SchoolEventPreset(
            id: "reunion_familias_sep",
            title: "Reunión familias inicio curso (ESO y Bach)",
            dateIso: "2026-09-16",
            dateSummary: "Mié 16 sep 2026",
            description: "Reunión presencial de inicio de curso con familias",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "reunion_familias_ene",
            title: "Reunión familias 2º trimestre (ESO)",
            dateIso: "2027-01-20",
            dateSummary: "Mié 20 ene 2027",
            description: "Reunión presencial con familias de ESO",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "notas_1eva_eso",
            title: "Límite poner notas 1ª Eva (ESO)",
            dateIso: "2026-11-29",
            dateSummary: "Dom 29 nov 2026",
            description: "Límite para introducir notas en Educamos · Sesiones 2 y 3 dic",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "notas_2eva_eso",
            title: "Límite poner notas 2ª Eva (ESO)",
            dateIso: "2027-03-07",
            dateSummary: "Dom 7 mar 2027",
            description: "Límite para introducir notas en Educamos · Sesiones 10 y 11 mar",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "graduacion_2bach",
            title: "Celebración y graduación 2º Bach",
            dateIso: "2027-05-21",
            dateSummary: "Vie 21 may 2027",
            description: "Acto de graduación de 2º de Bachillerato",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "notas_3eva_eso",
            title: "Límite poner notas 3ª Eva (ESO)",
            dateIso: "2027-06-06",
            dateSummary: "Dom 6 jun 2027",
            description: "Límite para notas en Educamos · Sesiones 8-10 jun · Entrega 21 jun",
            isNonTeaching: false
        ),
        SchoolEventPreset(
            id: "graduacion_4eso",
            title: "Graduación 4º ESO",
            dateIso: "2027-06-11",
            dateSummary: "Vie 11 jun 2027",
            description: "Acto de graduación de 4º de la ESO",
            isNonTeaching: false
        )
    ]

    // MARK: - Casación de cursos

    private static func matchesGrade(_ group: SchoolClass, expectedLevel: Int32, gradeKeywords: [String]) -> Bool {
        let normalized = group.name.lowercased()
        let isBachillerato = normalized.contains("bach")
        let isEso = normalized.contains("eso") || (!isBachillerato && (normalized.contains("1º") || normalized.contains("2º") || normalized.contains("3º") || normalized.contains("4º")))

        if gradeKeywords.contains(where: { normalized.contains($0) }) {
            return true
        }

        // Si es Bachillerato:
        if isBachillerato {
            if expectedLevel == 1 && (normalized.contains("1º") || normalized.contains("1 ") || normalized.contains("1-")) {
                return true
            }
            if expectedLevel == 2 && (normalized.contains("2º") || normalized.contains("2 ") || normalized.contains("2-")) {
                return true
            }
        } else if isEso {
            // Comparar course o dígito
            if group.course == expectedLevel {
                return true
            }
            if normalized.contains("\(expectedLevel)º") || normalized.contains("\(expectedLevel) ") {
                return true
            }
        }
        return false
    }

    /// Deduce la etapa predominante del docente a partir de sus grupos
    static func detectSuggestedStage(for groups: [SchoolClass]) -> Stage {
        var hasEso = false
        var hasBach1 = false
        var hasBach2 = false

        for group in groups {
            let name = group.name.lowercased()
            if name.contains("2º bach") || name.contains("2 bach") || name.contains("2ºbach") {
                hasBach2 = true
            } else if name.contains("1º bach") || name.contains("1 bach") || name.contains("1ºbach") || name.contains("bach") {
                hasBach1 = true
            } else {
                hasEso = true
            }
        }

        if hasEso {
            return .eso
        } else if hasBach2 && !hasBach1 {
            return .bach2
        } else if hasBach1 {
            return .bach1
        }
        return .eso
    }

    /// Resuelve qué salidas aplican a los grupos del docente
    static func resolveTripsForTeacher(groups: [SchoolClass]) -> [(trip: TripPreset, matchingClasses: [SchoolClass])] {
        var resolved: [(trip: TripPreset, matchingClasses: [SchoolClass])] = []
        for trip in allTrips {
            let matching = groups.filter { trip.matchesCourse($0) }
            if !matching.isEmpty {
                resolved.append((trip: trip, matchingClasses: matching))
            }
        }
        return resolved
    }

    // MARK: - Ejecución y persistencia segura

    struct ApplyResult {
        let evaluationPeriodsCreated: Int
        let tripEventsCreated: Int
        let schoolEventsCreated: Int
        let milestonesCreated: Int

        var totalCreated: Int {
            evaluationPeriodsCreated + tripEventsCreated + schoolEventsCreated + milestonesCreated
        }

        var summaryText: String {
            var parts: [String] = []
            if evaluationPeriodsCreated > 0 {
                parts.append("\(evaluationPeriodsCreated) periodos evaluativos")
            }
            if tripEventsCreated > 0 {
                parts.append("\(tripEventsCreated) salidas de curso")
            }
            if schoolEventsCreated > 0 {
                parts.append("\(schoolEventsCreated) eventos de centro")
            }
            if milestonesCreated > 0 {
                parts.append("\(milestonesCreated) hitos de claustro")
            }
            return parts.isEmpty ? "Calendario al día (no se requirieron cambios)" : "Se aplicaron: " + parts.joined(separator: ", ")
        }
    }

    /// Aplica el preset con verificación de duplicados e idempotencia
    static func applyPreset(
        bridge: KmpBridge,
        scheduleId: Int64,
        stage: Stage,
        applyEvaluations: Bool,
        selectedTripIds: Set<String>,
        groups: [SchoolClass],
        applySchoolEvents: Bool,
        applyMilestones: Bool
    ) async throws -> ApplyResult {
        var evalCount = 0
        var tripCount = 0
        var schoolEventCount = 0
        var milestoneCount = 0

        // 1. Periodos evaluativos
        if applyEvaluations {
            let existingPeriods = try await bridge.plannerEvaluationPeriods(scheduleId: scheduleId)
            let existingNames = Set(existingPeriods.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

            for period in stage.periods {
                let normalized = period.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !existingNames.contains(normalized) {
                    _ = try await bridge.plannerSaveEvaluationPeriod(
                        periodId: 0,
                        scheduleId: scheduleId,
                        name: period.name,
                        startDateIso: period.startDateIso,
                        endDateIso: period.endDateIso,
                        sortOrder: period.sortOrder
                    )
                    evalCount += 1
                }
            }
        }

        // 2. Salidas por curso vinculadas a sus classId correspondientes
        if !selectedTripIds.isEmpty {
            let existingEvents = (try? await bridge.plannerNonTeachingCalendarEvents(classId: nil)) ?? []
            let resolvedTrips = resolveTripsForTeacher(groups: groups)

            for item in resolvedTrips where selectedTripIds.contains(item.trip.id) {
                for group in item.matchingClasses {
                    for dateIso in item.trip.datesIso {
                        guard let (startMs, endMs) = epochRange(for: dateIso) else { continue }
                        let title = item.trip.title

                        // Comprobar si ya existe para este grupo y fecha
                        let alreadyExists = existingEvents.contains { evt in
                            evt.classId?.int64Value == group.id &&
                            isSameDay(epochMs: evt.startAt.toEpochMilliseconds(), targetDateIso: dateIso) &&
                            evt.title.localizedCaseInsensitiveContains(item.trip.destination)
                        }

                        if !alreadyExists {
                            _ = try await bridge.plannerSaveCalendarEvent(
                                id: nil,
                                classId: group.id,
                                title: "\(title) · \(group.name)",
                                description: item.trip.description,
                                startEpochMs: startMs,
                                endEpochMs: endMs
                            )
                            tripCount += 1
                        }
                    }
                }
            }
        }

        // 3. Eventos de centro y festivos (classId: nil)
        if applySchoolEvents {
            let existingEvents = (try? await bridge.plannerNonTeachingCalendarEvents(classId: nil)) ?? []

            for event in schoolWideEvents {
                guard let (startMs, endMs) = epochRange(for: event.dateIso) else { continue }
                let alreadyExists = existingEvents.contains { evt in
                    evt.classId == nil &&
                    isSameDay(epochMs: evt.startAt.toEpochMilliseconds(), targetDateIso: event.dateIso) &&
                    evt.title.localizedCaseInsensitiveContains(event.title)
                }

                if !alreadyExists {
                    _ = try await bridge.plannerSaveCalendarEvent(
                        id: nil,
                        classId: nil,
                        title: event.title,
                        description: event.description,
                        startEpochMs: startMs,
                        endEpochMs: endMs
                    )
                    schoolEventCount += 1
                }
            }
        }

        // 4. Hitos de claustro e informativos (classId: nil)
        if applyMilestones {
            let existingEvents = (try? await bridge.plannerNonTeachingCalendarEvents(classId: nil)) ?? []

            for milestone in teacherMilestones {
                guard let (startMs, endMs) = epochRange(for: milestone.dateIso) else { continue }
                let alreadyExists = existingEvents.contains { evt in
                    evt.classId == nil &&
                    isSameDay(epochMs: evt.startAt.toEpochMilliseconds(), targetDateIso: milestone.dateIso) &&
                    evt.title.localizedCaseInsensitiveContains(milestone.title)
                }

                if !alreadyExists {
                    _ = try await bridge.plannerSaveCalendarEvent(
                        id: nil,
                        classId: nil,
                        title: milestone.title,
                        description: milestone.description,
                        startEpochMs: startMs,
                        endEpochMs: endMs
                    )
                    milestoneCount += 1
                }
            }
        }

        // 5. Exámenes de 1º Bachillerato vinculados a sus grupos
        let examCount = (try? await sync1BachExams(bridge: bridge, groups: groups)) ?? 0

        return ApplyResult(
            evaluationPeriodsCreated: evalCount,
            tripEventsCreated: tripCount + examCount,
            schoolEventsCreated: schoolEventCount,
            milestonesCreated: milestoneCount
        )

    }

    /// Sincroniza e inserta de forma idempotente los exámenes de 1º Bachillerato en calendar_events
    @discardableResult
    static func sync1BachExams(bridge: KmpBridge, groups: [SchoolClass]) async throws -> Int {
        let matching1BachGroups = groups.filter {
            matchesGrade($0, expectedLevel: 1, gradeKeywords: ["1º bach", "1 bach", "1bach", "1ºbach", "1ba", "1bb"])
        }
        guard !matching1BachGroups.isEmpty else { return 0 }

        let allEvents = (try? await bridge.plannerAllCalendarEvents()) ?? []
        var created = 0

        for exam in all1BachExams {
            for group in matching1BachGroups {
                for dateIso in exam.datesIso {
                    guard let (startMs, endMs) = epochRange(for: dateIso) else { continue }
                    let alreadyExists = allEvents.contains { evt in
                        evt.classId?.int64Value == group.id &&
                        isSameDay(epochMs: evt.startAt.toEpochMilliseconds(), targetDateIso: dateIso) &&
                        (evt.title.localizedCaseInsensitiveContains("parcial") ||
                         evt.title.localizedCaseInsensitiveContains("global") ||
                         evt.title.localizedCaseInsensitiveContains("final") ||
                         evt.title.localizedCaseInsensitiveContains("extraordinari"))
                    }

                    if !alreadyExists {
                        _ = try await bridge.plannerSaveCalendarEvent(
                            id: nil,
                            classId: group.id,
                            title: "\(exam.title) · \(group.name)",
                            description: exam.description,
                            startEpochMs: startMs,
                            endEpochMs: endMs
                        )
                        created += 1
                    }
                }
            }
        }
        return created
    }

    // MARK: - Helpers de fecha


    private static func epochRange(for isoDate: String) -> (startMs: Int64, endMs: Int64)? {
        let calendar = Calendar.current
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var comp = DateComponents()
        comp.year = parts[0]
        comp.month = parts[1]
        comp.day = parts[2]
        comp.hour = 0
        comp.minute = 0
        comp.second = 0
        guard let start = calendar.date(from: comp) else { return nil }

        comp.hour = 23
        comp.minute = 59
        comp.second = 59
        guard let end = calendar.date(from: comp) else { return nil }

        return (
            startMs: Int64(start.timeIntervalSince1970 * 1000),
            endMs: Int64(end.timeIntervalSince1970 * 1000)
        )
    }

    private static func isSameDay(epochMs: Int64, targetDateIso: String) -> Bool {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
        let iso = AppDateTimeSupport.isoDateString(from: date)
        return iso == targetDateIso
    }
}
