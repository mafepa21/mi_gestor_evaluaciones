package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationSessionPlan
import com.migestor.shared.domain.LearningSituationSessionSequenceVersion
import com.migestor.shared.domain.LearningSituationStatus
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.TeacherScheduleSlot
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class GradePartialSyncTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun unaNotaNuevaNoBorraLaEvidenciaYaGuardada() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        container.gradesRepository.upsertGrade(
            classId = classId,
            studentId = studentId,
            columnId = "nota",
            evaluationId = null,
            value = 6.0,
            evidence = "foto del salto",
            evidencePath = null,
            rubricSelections = "nivel-2",
            updatedAtEpochMs = 100L,
            deviceId = "ipad",
            syncVersion = 1,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "grade",
                    id = "$classId-$studentId-nota",
                    updatedAtEpochMs = 200L,
                    deviceId = "mac",
                    payload = """{"classId":$classId,"studentId":$studentId,"columnId":"nota","value":8.5}""",
                )
            )
        )

        val grade = container.gradesRepository.listGradesForClass(classId).single()
        assertEquals(8.5, grade.value)
        assertEquals("foto del salto", grade.evidence)
        assertEquals("nivel-2", grade.rubricSelections)
    }

    @Test
    fun unaEvidenciaNuevaNoBorraLaNotaNiMueveLaPestana() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        container.gradesRepository.upsertGrade(
            classId = classId,
            studentId = studentId,
            columnId = "nota",
            evaluationId = null,
            value = 7.5,
            evidence = "foto del salto",
            evidencePath = null,
            rubricSelections = null,
            updatedAtEpochMs = 100L,
            deviceId = "ipad",
            syncVersion = 1,
        )
        container.notebookConfigRepository.saveTab(
            classId,
            NotebookTab(id = "curso", title = "Curso", order = 0),
        )
        container.notebookConfigRepository.saveTab(
            classId,
            NotebookTab(id = "trimestre", title = "Trimestre", order = 4, parentTabId = "curso"),
        )
        val groupId = container.notebookRepository.saveWorkGroup(
            classId,
            NotebookWorkGroup(
                id = 0,
                classId = classId,
                tabId = "trimestre",
                name = "Grupo A",
                order = 2,
                learningSituationId = 15,
            ),
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "grade",
                    id = "$classId-$studentId-nota",
                    updatedAtEpochMs = 200L,
                    deviceId = "mac",
                    payload = """{"classId":$classId,"studentId":$studentId,"columnId":"nota","evidence":"vídeo del partido"}""",
                ),
                SyncChange(
                    entity = "notebook_tab",
                    id = "trimestre",
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":"trimestre","classId":$classId,"title":"Primer trimestre"}""",
                ),
                SyncChange(
                    entity = "notebook_group",
                    id = groupId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$groupId,"classId":$classId,"tabId":"trimestre","name":"Grupo del patio"}""",
                ),
            )
        )

        val grade = container.gradesRepository.listGradesForClass(classId).single()
        assertEquals(7.5, grade.value)
        assertEquals("vídeo del partido", grade.evidence)
        val tab = container.notebookConfigRepository.listTabs(classId).first { it.id == "trimestre" }
        assertEquals("Primer trimestre", tab.title)
        assertEquals(4, tab.order)
        assertEquals("curso", tab.parentTabId)
        val group = container.notebookRepository.listWorkGroups(classId).single()
        assertEquals("Grupo del patio", group.name)
        assertEquals(2, group.order)
        assertEquals(15L, group.learningSituationId)
    }

    @Test
    fun unCambioDeAsistenciaNoBorraLaNotaDelDia() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val day = 1_700_000_000_000L
        container.attendanceRepository.saveAttendance(
            id = null,
            studentId = studentId,
            classId = classId,
            dateEpochMs = day,
            status = "PRESENTE",
            note = "Llegó sin equipación",
            hasIncident = true,
            followUpRequired = true,
            sessionId = null,
            updatedAtEpochMs = 100L,
            deviceId = "ipad",
            syncVersion = 1,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "attendance",
                    id = "$classId-$studentId-$day",
                    updatedAtEpochMs = 200L,
                    deviceId = "mac",
                    payload = """{"classId":$classId,"studentId":$studentId,"dateEpochMs":$day,"status":"AUSENTE"}""",
                )
            )
        )

        val mark = container.attendanceRepository.listAttendanceByDate(classId, day).single()
        assertEquals("AUSENTE", mark.status)
        assertEquals("Llegó sin equipación", mark.note)
        assertEquals(true, mark.hasIncident)
        assertEquals(true, mark.followUpRequired)
    }

    @Test
    fun unTituloNuevoNoBorraElDetalleDeLaIncidencia() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val incidentId = container.incidentsRepository.saveIncident(
            id = null,
            classId = classId,
            studentId = studentId,
            title = "Caída",
            detail = "Se torció el tobillo en el calentamiento",
            severity = "high",
            dateEpochMs = 1_700_000_000_000L,
            updatedAtEpochMs = 100L,
            deviceId = "ipad",
            syncVersion = 1,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "incident",
                    id = incidentId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "mac",
                    payload = """{"id":$incidentId,"classId":$classId,"title":"Caída en el patio","dateEpochMs":1700000000000}""",
                )
            )
        )

        val incident = container.incidentsRepository.listIncidents(classId).single()
        assertEquals("Caída en el patio", incident.title)
        assertEquals("Se torció el tobillo en el calentamiento", incident.detail)
        assertEquals("high", incident.severity)
        assertEquals(studentId, incident.studentId)
    }

    @Test
    fun unNombreNuevoNoBorraElPesoNiLaFormula() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val evaluationId = container.evaluationsRepository.saveEvaluation(
            classId = classId,
            code = "EFI1",
            name = "Resistencia",
            type = "Nota",
            weight = 2.5,
            formula = "(nota1+nota2)/2",
            description = "Prueba de curso",
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "evaluation",
                    id = evaluationId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$evaluationId,"classId":$classId,"code":"EFI1","name":"Resistencia aeróbica","type":"Nota"}""",
                )
            )
        )

        val evaluation = container.evaluationsRepository.listClassEvaluations(classId).single()
        assertEquals("Resistencia aeróbica", evaluation.name)
        assertEquals(2.5, evaluation.weight)
        assertEquals("(nota1+nota2)/2", evaluation.formula)
        assertEquals("Prueba de curso", evaluation.description)
    }

    @Test
    fun unTituloNuevoNoDespegaElEventoDeSuClase() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val eventId = container.calendarRepository.saveEvent(
            classId = classId,
            title = "Excursión",
            description = "Salida al parque fluvial",
            startEpochMs = 1_700_000_000_000L,
            endEpochMs = 1_700_003_600_000L,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "calendar_event",
                    id = eventId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$eventId,"title":"Excursión al río","startEpochMs":1700000000000,"endEpochMs":1700003600000}""",
                )
            )
        )

        val event = container.calendarRepository.listEvents(classId).single()
        assertEquals("Excursión al río", event.title)
        assertEquals("Salida al parque fluvial", event.description)
        assertEquals(classId, event.classId)
    }

    @Test
    fun unTituloNuevoNoCambiaSiLaColumnaCuentaParaLaMedia() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        container.notebookConfigRepository.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "media_col",
                title = "Examen",
                type = NotebookColumnType.CALCULATED,
                formula = "media(a,b)",
                weight = 2.0,
                countsTowardAverage = false,
                isHidden = true,
                isLocked = true,
                order = 4,
                colorHex = "#C45C26",
                iconName = "sportscourt",
                categoryId = "ef",
                dateEpochMs = 1_700_000_000_000,
                unitOrSituation = "Juegos",
            ),
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "notebook_column",
                    id = "media_col",
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":"media_col","classId":$classId,"title":"Examen final"}""",
                )
            )
        )

        val column = container.notebookConfigRepository.listColumns(classId).single()
        assertEquals("Examen final", column.title)
        assertEquals(NotebookColumnType.CALCULATED, column.type)
        assertEquals("media(a,b)", column.formula)
        assertEquals(2.0, column.weight)
        assertEquals(false, column.countsTowardAverage)
        assertEquals(true, column.isHidden)
        assertEquals(true, column.isLocked)
        assertEquals(4, column.order)
        assertEquals("#C45C26", column.colorHex)
        assertEquals("sportscourt", column.iconName)
        assertEquals("ef", column.categoryId)
        assertEquals(1_700_000_000_000, column.dateEpochMs)
        assertEquals("Juegos", column.unitOrSituation)
    }

    @Test
    fun unNombreNuevoNoBorraLasFechasDeLaUnidad() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val unitId = container.plannerRepository.upsertTeachingUnit(
            TeachingUnit(
                name = "Juegos",
                description = "Cooperar en equipo",
                colorHex = "#112233",
                groupId = classId,
                schoolClassId = classId,
                startDate = LocalDate(2026, 10, 1),
                endDate = LocalDate(2026, 10, 20),
            )
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "teaching_unit",
                    id = unitId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$unitId,"name":"Juegos de cooperación"}""",
                )
            )
        )

        val unit = container.plannerRepository.listAllTeachingUnits().single()
        assertEquals("Juegos de cooperación", unit.name)
        assertEquals("Cooperar en equipo", unit.description)
        assertEquals("#112233", unit.colorHex)
        assertEquals(LocalDate(2026, 10, 1), unit.startDate)
        assertEquals(LocalDate(2026, 10, 20), unit.endDate)
        assertEquals(classId, unit.groupId)
    }

    @Test
    fun unTituloNuevoNoVaciaLaSituacionDeAprendizaje() = runTest {
        val container = newContainer()
        val situationId = container.learningSituationsRepository.saveSituation(
            LearningSituation(
                title = "El río",
                challenge = "Cruzar sin caer",
                finalProduct = "Circuito",
                sessionCount = 6,
                payloadJson = """{"sessions":["1","2"]}""",
                status = LearningSituationStatus.DRAFT,
            )
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "learning_situation",
                    id = situationId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$situationId,"title":"El río urbano"}""",
                )
            )
        )

        val situation = container.learningSituationsRepository.getSituation(situationId)
        assertEquals("El río urbano", situation?.title)
        assertEquals("Cruzar sin caer", situation?.challenge)
        assertEquals("Circuito", situation?.finalProduct)
        assertEquals(6, situation?.sessionCount)
        assertEquals("""{"sessions":["1","2"]}""", situation?.payloadJson)
        assertEquals(LearningSituationStatus.DRAFT, situation?.status)
    }

    @Test
    fun unAvisoNuevoNoVaciaLasSesionesEscritas() = runTest {
        val container = newContainer()
        val situationId = container.learningSituationsRepository.saveSituation(
            LearningSituation(title = "El río")
        )
        val versionId = container.learningSituationsRepository.saveSessionSequenceVersion(
            LearningSituationSessionSequenceVersion(
                learningSituationId = situationId,
                versionNumber = 1,
                originalFileName = "secuencia.docx",
                sha256 = "abc123",
                sizeBytes = 40,
                payloadJson = """{"sessions":[{"title":"Cruzar"}]}""",
            )
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "learning_situation_sequence_version",
                    id = versionId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$versionId,"learningSituationId":$situationId,"sha256":"abc123","warningsJson":"[\"revisar material\"]"}""",
                )
            )
        )

        val version = container.learningSituationsRepository.listSessionSequenceVersions(situationId).single()
        assertEquals("""{"sessions":[{"title":"Cruzar"}]}""", version.payloadJson)
        assertEquals("[\"revisar material\"]", version.warningsJson)
        assertEquals(1, container.learningSituationsRepository.listSessionSequenceVersions(situationId).size)
    }

    @Test
    fun unTituloNuevoNoBorraElObjetivoDeLaSesion() = runTest {
        val container = newContainer()
        val situationId = container.learningSituationsRepository.saveSituation(LearningSituation(title = "El río"))
        val versionId = container.learningSituationsRepository.saveSessionSequenceVersion(
            LearningSituationSessionSequenceVersion(
                learningSituationId = situationId,
                versionNumber = 1,
                originalFileName = "secuencia.docx",
                sha256 = "plan123",
            )
        )
        val planId = container.learningSituationsRepository.saveSessionPlan(
            LearningSituationSessionPlan(
                learningSituationId = situationId,
                sequenceVersionId = versionId,
                sessionNumber = 1,
                title = "Cruzar",
                objective = "Pasar al otro lado sin caer",
                material = "colchonetas",
                effectiveMinutes = 45,
                developmentJson = """[{"step":"calentar"}]""",
            )
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "learning_situation_session_plan",
                    id = planId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$planId,"learningSituationId":$situationId,"sequenceVersionId":$versionId,"title":"Cruzar el río"}""",
                )
            )
        )

        val plan = container.learningSituationsRepository.getSessionPlan(planId)
        assertEquals("Cruzar el río", plan?.title)
        assertEquals("Pasar al otro lado sin caer", plan?.objective)
        assertEquals("colchonetas", plan?.material)
        assertEquals(45, plan?.effectiveMinutes)
        assertEquals("""[{"step":"calentar"}]""", plan?.developmentJson)
    }

    @Test
    fun unNombreNuevoNoMueveLaFranjaNiElTrimestre() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val schedule = container.teacherScheduleRepository.getOrCreatePrimarySchedule()
        val slotId = container.teacherScheduleRepository.saveScheduleSlot(
            TeacherScheduleSlot(
                teacherScheduleId = schedule.id,
                schoolClassId = classId,
                subjectLabel = "Educación Física",
                dayOfWeek = 3,
                startTime = "09:00",
                endTime = "10:00",
            )
        )
        val periodId = container.teacherScheduleRepository.saveEvaluationPeriod(
            com.migestor.shared.domain.PlannerEvaluationPeriod(
                teacherScheduleId = schedule.id,
                name = "Primera",
                startDateIso = "2026-09-08",
                endDateIso = "2026-12-20",
                sortOrder = 1,
            )
        )

        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")
        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "teacher_schedule_slot",
                    id = slotId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$slotId,"teacherScheduleId":${schedule.id},"subjectLabel":"EF patio"}""",
                ),
                SyncChange(
                    entity = "planner_evaluation_period",
                    id = periodId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$periodId,"teacherScheduleId":${schedule.id},"name":"Primer trimestre"}""",
                ),
            )
        )

        val slot = container.teacherScheduleRepository.listScheduleSlots(schedule.id).single()
        assertEquals("EF patio", slot.subjectLabel)
        assertEquals(3, slot.dayOfWeek)
        assertEquals("09:00", slot.startTime)
        assertEquals("10:00", slot.endTime)
        val period = container.teacherScheduleRepository.listEvaluationPeriods(schedule.id).single()
        assertEquals("Primer trimestre", period.name)
        assertEquals("2026-09-08", period.startDateIso)
        assertEquals("2026-12-20", period.endDateIso)
    }

    @Test
    fun unNombreNuevoNoDespegaLaRubricaNiBorraSusCriterios() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val rubricId = container.rubricsRepository.saveRubric(
            name = "Juego limpio",
            description = "Cómo coopera el grupo",
            classId = classId,
        )
        container.rubricsRepository.saveCriterion(
            rubricId = rubricId,
            description = "Ayuda a los compañeros",
            weight = 2.0,
            order = 1,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "rubric_bundle",
                    id = rubricId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"rubricId":$rubricId,"name":"Juego limpio y respeto"}""",
                )
            )
        )

        val detail = container.rubricsRepository.getRubricDetail(rubricId)
        assertEquals("Juego limpio y respeto", detail?.rubric?.name)
        assertEquals("Cómo coopera el grupo", detail?.rubric?.description)
        assertEquals(classId, detail?.rubric?.classId)
        assertEquals("Ayuda a los compañeros", detail?.criteria?.single()?.criterion?.description)
        assertEquals(2.0, detail?.criteria?.single()?.criterion?.weight)
    }

    @Test
    fun unNombreNuevoNoRecortaElCursoNiElEnlace() = runTest {
        val container = newContainer()
        val schedule = container.teacherScheduleRepository.getOrCreatePrimarySchedule()
        val situationId = container.learningSituationsRepository.saveSituation(LearningSituation(title = "El río"))
        container.learningSituationsRepository.saveLinkedResource(
            com.migestor.shared.domain.LearningSituationLinkedResource(
                learningSituationId = situationId,
                kind = com.migestor.shared.domain.LearningSituationResourceKind.RUBRIC,
                resourceId = "rubrica-1",
                label = "Rúbrica de cooperación",
            )
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "teacher_schedule",
                    id = schedule.id.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":${schedule.id},"name":"Agenda del patio"}""",
                ),
                SyncChange(
                    entity = "learning_situation_link",
                    id = "$situationId:rubrica-1",
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"learningSituationId":$situationId,"resourceId":"rubrica-1","kind":"RUBRIC"}""",
                ),
            )
        )

        val after = container.teacherScheduleRepository.getOrCreatePrimarySchedule()
        assertEquals("Agenda del patio", after.name)
        assertEquals(schedule.startDateIso, after.startDateIso)
        assertEquals(schedule.endDateIso, after.endDateIso)
        assertEquals(schedule.activeWeekdaysCsv, after.activeWeekdaysCsv)
        val link = container.learningSituationsRepository.listLinkedResources(situationId).single()
        assertEquals("Rúbrica de cooperación", link.label)
        assertEquals(com.migestor.shared.domain.LearningSituationResourceKind.RUBRIC, link.kind)
    }

    @Test
    fun unTituloNuevoNoBorraLaEscalaNiLaRespuesta() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(name = "1 ESO A", course = 1)
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val queries = container.database.appDatabaseQueries
        queries.upsertInstrumentTemplate(
            id = "tpl-1",
            class_id = classId,
            column_id = "obs",
            evaluation_id = 9L,
            title = "Observación",
            kind = "observation",
            input_kind = "scale",
            source = "ef",
            created_at_epoch_ms = 100L,
            updated_at_epoch_ms = 100L,
            device_id = "mac",
            sync_version = 1,
        )
        queries.upsertInstrumentItem(
            id = "item-1",
            template_id = "tpl-1",
            item_key = "coop",
            title = "Cooperación",
            item_type = "scale14",
            options_csv = "1,2,3,4",
            required = 0L,
            sort_order = 2L,
            help_text = "Mira si ayuda",
            updated_at_epoch_ms = 100L,
            device_id = "mac",
            sync_version = 1,
        )
        queries.upsertInstrumentResponse(
            class_id = classId,
            student_id = studentId,
            column_id = "obs",
            item_id = "item-1",
            value_text = "Bien",
            value_bool = 1L,
            value_number = 3.5,
            updated_at_epoch_ms = 100L,
            device_id = "mac",
            sync_version = 1,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "notebook_instrument_template",
                    id = "tpl-1",
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":"tpl-1","classId":$classId,"columnId":"obs","title":"Observación de patio"}""",
                ),
                SyncChange(
                    entity = "notebook_instrument_item",
                    id = "item-1",
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":"item-1","templateId":"tpl-1","itemKey":"coop","title":"Cooperación en el juego"}""",
                ),
                SyncChange(
                    entity = "notebook_instrument_response",
                    id = "$classId:$studentId:obs:item-1",
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"classId":$classId,"studentId":$studentId,"columnId":"obs","itemId":"item-1","valueText":"Muy bien"}""",
                ),
            )
        )

        val template = queries.selectInstrumentTemplateByColumn("obs").executeAsOne()
        assertEquals("Observación de patio", template.title)
        assertEquals("scale", template.input_kind)
        assertEquals(9L, template.evaluation_id)
        val item = queries.selectInstrumentItemsByTemplate("tpl-1").executeAsList().single()
        assertEquals("Cooperación en el juego", item.title)
        assertEquals("1,2,3,4", item.options_csv)
        assertEquals(0L, item.required)
        assertEquals(2L, item.sort_order)
        assertEquals("Mira si ayuda", item.help_text)
        val response = queries.selectInstrumentResponsesForCell(classId, studentId, "obs").executeAsList().single()
        assertEquals("Muy bien", response.value_text)
        assertEquals(1L, response.value_bool)
        assertEquals(3.5, response.value_number)
    }

    @Test
    fun unNombreNuevoNoBorraLaClaseNiElPesoDelCriterio() = runTest {
        val container = newContainer()
        val classId = container.classesRepository.saveClass(
            name = "1 ESO A",
            course = 1,
            description = "Grupo de patio",
        )
        val rubricId = container.rubricsRepository.saveRubric(name = "Juego limpio", classId = classId)
        val criterionId = container.rubricsRepository.saveCriterion(
            rubricId = rubricId,
            description = "Ayuda a los compañeros",
            weight = 2.0,
            order = 3,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "class",
                    id = classId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$classId,"name":"1 ESO Patio","course":1}""",
                ),
                SyncChange(
                    entity = "rubric_bundle",
                    id = rubricId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"rubricId":$rubricId,"name":"Juego limpio","criteria":[{"id":$criterionId,"description":"Ayuda más"}]}""",
                ),
            )
        )

        val schoolClass = container.classesRepository.listClasses().single()
        assertEquals("1 ESO Patio", schoolClass.name)
        assertEquals("Grupo de patio", schoolClass.description)
        assertEquals(1, schoolClass.course)
        val criterion = container.rubricsRepository.getRubricDetail(rubricId)?.criteria?.single()?.criterion
        assertEquals("Ayuda más", criterion?.description)
        assertEquals(2.0, criterion?.weight)
        assertEquals(3, criterion?.order)
    }

    @Test
    fun unNombreNuevoNoApagaElCursoNiBajaLosPuntos() = runTest {
        val container = newContainer()
        val start = 1_756_684_800_000L
        val end = 1_782_777_600_000L
        val yearId = container.academicYearsRepository.createAcademicYear(
            name = "2026-2027",
            startEpochMs = start,
            endEpochMs = end,
            makeActive = true,
        )
        val rubricId = container.rubricsRepository.saveRubric(name = "Juego limpio")
        val criterionId = container.rubricsRepository.saveCriterion(
            rubricId = rubricId,
            description = "Ayuda",
            weight = 1.0,
            order = 1,
        )
        val levelId = container.rubricsRepository.saveLevel(
            criterionId = criterionId,
            name = "Notable",
            points = 8,
            description = "Ayuda sin que se lo pidan",
            order = 2,
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "academic_year",
                    id = yearId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"id":$yearId,"name":"Curso 2026-2027","startEpochMs":$start,"endEpochMs":$end}""",
                ),
                SyncChange(
                    entity = "rubric_bundle",
                    id = rubricId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = """{"rubricId":$rubricId,"name":"Juego limpio","criteria":[{"id":$criterionId,"description":"Ayuda","weight":1.0,"order":1,"levels":[{"id":$levelId,"name":"Notable alto"}]}]}""",
                ),
            )
        )

        val year = container.academicYearsRepository.listAcademicYears().first { it.id == yearId }
        assertEquals("Curso 2026-2027", year.name)
        assertEquals(true, year.isActive)
        val level = container.rubricsRepository.getRubricDetail(rubricId)?.criteria?.single()?.levels?.single()
        assertEquals("Notable alto", level?.name)
        assertEquals(8, level?.points)
        assertEquals("Ayuda sin que se lo pidan", level?.description)
        assertEquals(2, level?.order)
    }
}
