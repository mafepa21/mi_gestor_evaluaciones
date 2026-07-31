package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.gradeValueFor
import com.migestor.shared.domain.NotebookInstrumentItem
import com.migestor.shared.domain.NotebookInstrumentItemType
import com.migestor.shared.domain.NotebookInstrumentResponse
import com.migestor.shared.domain.NotebookInstrumentTemplate
import com.migestor.shared.domain.NotebookInstrumentTemplateKind
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.usecase.BuildNotebookSheetUseCase
import com.migestor.shared.usecase.GetNotebookUseCase
import com.migestor.shared.usecase.NotebookSheetMemoryCache
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Cubre dos regresiones reales encontradas al depurar un reporte de usuario:
 * (1) el Cuaderno servía una hoja cacheada desactualizada tras guardar un instrumento
 *     estructurado, porque `saveResponses` no invalidaba el mismo `NotebookSheetMemoryCache`
 *     que usan los guardados de nota "normales"; (2) la Rejilla de observación (sesión ×
 *     indicador) no traducía sus respuestas 1-4 en la nota que cuenta para la media.
 */
class NotebookInstrumentsRepositorySqlDelightTest {

    @Test
    fun `saveResponses invalidates the shared notebook sheet cache`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Ana", lastName = "Lopez", email = null)
        val classId = fixture.classes.saveClass(name = "3 ESO A", course = 3, description = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "checklist_col",
                title = "Checklist",
                type = NotebookColumnType.TEXT,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            )
        )
        fixture.instruments.saveTemplate(
            template = NotebookInstrumentTemplate(
                id = "template_checklist_col",
                classId = classId,
                columnId = "checklist_col",
                title = "Checklist",
                kind = NotebookInstrumentTemplateKind.CHECKLIST,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            ),
            items = listOf(
                NotebookInstrumentItem(
                    id = "template_checklist_col_item1",
                    templateId = "template_checklist_col",
                    key = "check_1",
                    title = "Item 1",
                    type = NotebookInstrumentItemType.CHECK,
                )
            )
        )

        // Primer load: la hoja queda cacheada sin ninguna respuesta guardada todavía.
        val beforeSheet = fixture.notebook.loadNotebookSnapshot(classId)
        val beforeRow = beforeSheet.rows.single { it.student.id == studentId }
        assertNull(beforeRow.persistedCells.firstOrNull { it.columnId == "checklist_col" }?.displayValue)

        fixture.instruments.saveResponses(
            classId = classId,
            studentId = studentId,
            columnId = "checklist_col",
            responses = listOf(
                NotebookInstrumentResponse(
                    classId = classId,
                    studentId = studentId,
                    columnId = "checklist_col",
                    itemId = "template_checklist_col_item1",
                    boolValue = true,
                )
            ),
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )

        // Si la caché no se hubiera invalidado, este segundo load devolvería la misma hoja
        // servida arriba (sin la respuesta recién guardada) en vez de recalcularla.
        val afterSheet = fixture.notebook.loadNotebookSnapshot(classId)
        val afterRow = afterSheet.rows.single { it.student.id == studentId }
        assertEquals("Completo", afterRow.persistedCells.first { it.columnId == "checklist_col" }.displayValue)
    }

    @Test
    fun `saveResponses computes partial checklist progress like the real save from the sheet`() = runTest {
        // Reproduce EXACTAMENTE lo que envía KmpBridge.saveStructuredInstrumentEvaluation:
        // todos los items del modelo, incluidos los CHECK sin marcar, con boolValue = false
        // explícito (nunca null) — no solo los que el usuario tocó.
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Carlos", lastName = "Ruiz", email = null)
        val classId = fixture.classes.saveClass(name = "1 BAC B", course = 1, description = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "final_checklist_col",
                title = "Checklist final de entrega - Sesion 10",
                type = NotebookColumnType.TEXT,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            )
        )
        val itemTitles = listOf(
            "No puntua por separado", "Diagnostico inicial completo (S1)", "Plan FITT-PV validado (S2)",
            "Registros de entrenamiento presentes", "Quiz de habitos completado (S8)",
            "Coevaluacion del Coach firmada (S9)", "Autoevaluacion final completada (S10)",
        )
        fixture.instruments.saveTemplate(
            template = NotebookInstrumentTemplate(
                id = "template_final_checklist_col",
                classId = classId,
                columnId = "final_checklist_col",
                title = "Checklist final de entrega - Sesion 10",
                kind = NotebookInstrumentTemplateKind.CHECKLIST,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            ),
            items = itemTitles.mapIndexed { index, title ->
                NotebookInstrumentItem(
                    id = "template_final_checklist_col_check_${index + 1}",
                    templateId = "template_final_checklist_col",
                    key = "check_${index + 1}",
                    title = title,
                    type = NotebookInstrumentItemType.CHECK,
                )
            }
        )

        // Los 5 primeros marcados, los 2 últimos enviados igualmente con boolValue = false.
        val responses = itemTitles.indices.map { index ->
            NotebookInstrumentResponse(
                classId = classId,
                studentId = studentId,
                columnId = "final_checklist_col",
                itemId = "template_final_checklist_col_check_${index + 1}",
                boolValue = index < 5,
            )
        }
        fixture.instruments.saveResponses(
            classId = classId,
            studentId = studentId,
            columnId = "final_checklist_col",
            responses = responses,
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )

        val sheet = fixture.notebook.loadNotebookSnapshot(classId)
        val row = sheet.rows.single { it.student.id == studentId }
        assertEquals(
            "5/7",
            row.persistedCells.first { it.columnId == "final_checklist_col" }.displayValue
        )
    }

    @Test
    fun `saveResponses derives a proportional checklist score from the marked items`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Nuria", lastName = "Gil", email = null)
        val classId = fixture.classes.saveClass(name = "1 BAC C", course = 1, description = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "chkp_col",
                title = "Checklist de protocolo de RCP",
                type = NotebookColumnType.NUMERIC,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
                weight = 0.2,
            )
        )
        val titles = listOf("Comprueba consciencia", "Pide ayuda", "Abre vía aérea", "Compresiones 30:2")
        fixture.instruments.saveTemplate(
            template = NotebookInstrumentTemplate(
                id = "template_chkp_col",
                classId = classId,
                columnId = "chkp_col",
                title = "Checklist de protocolo de RCP",
                kind = NotebookInstrumentTemplateKind.CHECKLIST,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            ),
            items = titles.mapIndexed { index, title ->
                NotebookInstrumentItem(
                    id = "template_chkp_col_chkp_${index + 1}",
                    templateId = "template_chkp_col",
                    key = "chkp_${index + 1}",
                    title = title,
                    type = NotebookInstrumentItemType.CHECK,
                )
            }
        )

        // 3 de 4 ítems marcados -> 7,5 sobre 10.
        fixture.instruments.saveResponses(
            classId = classId,
            studentId = studentId,
            columnId = "chkp_col",
            responses = titles.indices.map { index ->
                NotebookInstrumentResponse(
                    classId = classId,
                    studentId = studentId,
                    columnId = "chkp_col",
                    itemId = "template_chkp_col_chkp_${index + 1}",
                    boolValue = index < 3,
                )
            },
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )

        assertEquals(7.5, fixture.grades.listGradesForStudentInClass(studentId, classId).single().value)
    }

    @Test
    fun `saveResponses does not derive a score for a plain submission checklist`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Iker", lastName = "Sanz", email = null)
        val classId = fixture.classes.saveClass(name = "1 BAC D", course = 1, description = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "entrega_col",
                title = "Checklist final de entrega",
                type = NotebookColumnType.TEXT,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            )
        )
        fixture.instruments.saveTemplate(
            template = NotebookInstrumentTemplate(
                id = "template_entrega_col",
                classId = classId,
                columnId = "entrega_col",
                title = "Checklist final de entrega",
                kind = NotebookInstrumentTemplateKind.CHECKLIST,
                inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            ),
            items = listOf(
                NotebookInstrumentItem(
                    id = "template_entrega_col_check_1",
                    templateId = "template_entrega_col",
                    key = "check_1",
                    title = "Producto final entregado",
                    type = NotebookInstrumentItemType.CHECK,
                )
            )
        )

        fixture.instruments.saveResponses(
            classId = classId,
            studentId = studentId,
            columnId = "entrega_col",
            responses = listOf(
                NotebookInstrumentResponse(
                    classId = classId,
                    studentId = studentId,
                    columnId = "entrega_col",
                    itemId = "template_entrega_col_check_1",
                    boolValue = true,
                )
            ),
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )

        assertEquals(0, fixture.grades.listGradesForStudentInClass(studentId, classId).size)
    }

    @Test
    fun `saveResponses derives an observation grid score and it counts toward the average`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Maria", lastName = "Lopez", email = null)
        val classId = fixture.classes.saveClass(name = "1 BAC A", course = 1, description = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "obs_col",
                title = "Rejilla de observacion sistematica",
                type = NotebookColumnType.NUMERIC,
                inputKind = NotebookCellInputKind.STRUCTURED_OBSERVATION,
                scaleKind = NotebookScaleKind.FOUR_LEVEL,
                weight = 0.35,
            )
        )
        fixture.instruments.saveTemplate(
            template = NotebookInstrumentTemplate(
                id = "template_obs_col",
                classId = classId,
                columnId = "obs_col",
                title = "Rejilla de observacion sistematica",
                kind = NotebookInstrumentTemplateKind.OBSERVATION,
                inputKind = NotebookCellInputKind.STRUCTURED_OBSERVATION,
            ),
            items = observationGridItems()
        )

        // S3=[3,2,2,3] -> 2.5, S7=[3,3,3,3] -> 3.0, S9=[4,3,4,4] -> 3.75.
        // La calificación almacenada conserva la media bruta 1-4 (3.0833...). Al construir la
        // hoja, FOUR_LEVEL la normaliza a 0-10 para el cálculo de la media (6.9444...).
        val responses = listOf(
            0 to listOf(3.0, 2.0, 2.0, 3.0),
            1 to listOf(3.0, 3.0, 3.0, 3.0),
            2 to listOf(4.0, 3.0, 4.0, 4.0),
        ).flatMap { (session, values) ->
            values.mapIndexed { indicator, value ->
                NotebookInstrumentResponse(
                    classId = classId,
                    studentId = studentId,
                    columnId = "obs_col",
                    itemId = "template_obs_col_obs_s${session}_i$indicator",
                    numberValue = value,
                )
            }
        }

        fixture.instruments.saveResponses(
            classId = classId,
            studentId = studentId,
            columnId = "obs_col",
            responses = responses,
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )

        val grade = fixture.grades.listGradesForStudentInClass(studentId, classId).single()
        assertEquals(3.0833333333333335, grade.value)

        val sheet = fixture.notebook.loadNotebookSnapshot(classId)
        val row = sheet.rows.single { it.student.id == studentId }
        val column = sheet.columns.single { it.id == "obs_col" }
        assertEquals(6.9444444444444455, row.gradeValueFor(column))
    }

    private fun observationGridItems(): List<NotebookInstrumentItem> {
        val indicators = listOf("Tecnica", "RPE adecuado", "Ajuste de intensidad", "Compromiso motor")
        val sessions = listOf("S3 - inicio", "S7 - mitad y reajuste", "S9 - cierre")
        return sessions.flatMapIndexed { sessionIndex, sessionLabel ->
            indicators.mapIndexed { indicatorIndex, indicatorTitle ->
                NotebookInstrumentItem(
                    id = "template_obs_col_obs_s${sessionIndex}_i$indicatorIndex",
                    templateId = "template_obs_col",
                    key = "obs_s${sessionIndex}_i$indicatorIndex",
                    title = "$sessionLabel · $indicatorTitle",
                    type = NotebookInstrumentItemType.SCALE_1_4,
                )
            }
        }
    }

    private fun createFixture(): Fixture {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val students = StudentsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)
        val evaluations = EvaluationsRepositorySqlDelight(db)
        val config = NotebookConfigRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)
        val cells = NotebookCellsRepositorySqlDelight(db)
        val sheetCache = NotebookSheetMemoryCache()
        val notebook = NotebookRepositorySqlDelight(
            db = db,
            studentsRepository = students,
            classesRepository = classes,
            evaluationsRepository = evaluations,
            notebookConfigRepository = config,
            buildNotebookSheetUseCase = BuildNotebookSheetUseCase(
                GetNotebookUseCase(classes, evaluations, grades, cells)
            ),
            gradesRepository = grades,
            notebookCellsRepository = cells,
            sheetCache = sheetCache,
        )
        val instruments = NotebookInstrumentsRepositorySqlDelight(db, grades, sheetCache)
        return Fixture(students, classes, config, grades, notebook, instruments)
    }

    private data class Fixture(
        val students: StudentsRepositorySqlDelight,
        val classes: ClassesRepositorySqlDelight,
        val config: NotebookConfigRepositorySqlDelight,
        val grades: GradesRepositorySqlDelight,
        val notebook: NotebookRepositorySqlDelight,
        val instruments: NotebookInstrumentsRepositorySqlDelight,
    )
}
