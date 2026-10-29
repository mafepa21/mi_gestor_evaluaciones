package com.migestor.shared.evaluationsession

import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.StudentSupportMeasure
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.domain.SupportMeasureType
import com.migestor.shared.repository.StudentAttendanceStats
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val CLASS_ID = 7L

/** Solo datos de prueba. */
class EvaluationSessionUseCaseTest {

    /** Repositorio en memoria con la misma semántica que el de SQLDelight. */
    private class FakeSessions : EvaluationSessionRepository {
        val sessions = mutableMapOf<String, EvaluationSession>()
        val rows = mutableMapOf<Pair<String, Long>, EvaluationSessionStudentRecord>()
        val names = mutableMapOf<Long, Pair<String, String>>()
        var lastSnapshots: List<EvaluationSessionStudentSnapshot> = emptyList()

        override suspend fun listSessions(classId: Long) =
            sessions.values.filter { it.classId == classId }
                .sortedWith(compareBy<EvaluationSession> { it.isClosed }.thenByDescending { it.dateIso })

        override suspend fun getSession(id: String) = sessions[id]

        override suspend fun insertSession(session: EvaluationSession) {
            if (sessions.values.any { it.classId == session.classId && it.kind == session.kind }) {
                throw EvaluationSessionDuplicateException(session.kind)
            }
            sessions[session.id] = session
        }

        override suspend fun updateHeader(
            id: String, label: String, plannerEvaluationPeriodId: Long?, dateIso: String,
            attendees: String, generalAgreements: String, nowEpochMs: Long,
        ) {
            val s = sessions.getValue(id)
            if (s.isClosed) throw EvaluationSessionClosedException()
            sessions[id] = s.copy(
                label = label, plannerEvaluationPeriodId = plannerEvaluationPeriodId, dateIso = dateIso,
                attendees = attendees, generalAgreements = generalAgreements, updatedAtEpochMs = nowEpochMs,
            )
        }

        override suspend fun closeSession(id: String, snapshots: List<EvaluationSessionStudentSnapshot>, nowEpochMs: Long) {
            val s = sessions.getValue(id)
            if (s.isClosed) throw EvaluationSessionClosedException()
            lastSnapshots = snapshots
            snapshots.forEach { snap ->
                val key = id to snap.studentId
                rows[key]?.let {
                    rows[key] = it.copy(
                        frozenAverage = snap.average,
                        frozenOwnFailed = snap.ownFailed,
                        frozenAbsencePercent = snap.absencePercent,
                        frozenAbsenceCount = snap.absenceCount,
                        frozenSupportLevel = snap.supportLevel,
                        frozenIncidentCount = snap.incidentCount,
                    )
                }
            }
            sessions[id] = s.copy(isClosed = true, closedAtEpochMs = nowEpochMs)
        }

        override suspend fun reopenSession(id: String, nowEpochMs: Long) {
            sessions[id] = sessions.getValue(id).copy(isClosed = false, closedAtEpochMs = null)
        }

        override suspend fun deleteSession(id: String) {
            sessions.remove(id)
            rows.keys.removeAll { it.first == id }
        }

        override suspend fun listStudents(sessionId: String) =
            rows.values.filter { it.sessionId == sessionId }.sortedBy { it.lastName }

        override suspend fun ensureStudents(sessionId: String, studentIds: List<Long>, nowEpochMs: Long): Int {
            var created = 0
            studentIds.distinct().forEach { id ->
                val key = sessionId to id
                if (key !in rows) {
                    val (first, last) = names[id] ?: ("Alumno" to "Prueba $id")
                    rows[key] = EvaluationSessionStudentRecord(sessionId, id, first, last)
                    created++
                }
            }
            return created
        }

        override suspend fun updateStudent(
            sessionId: String, studentId: Long, otherFailedCount: Int, agreement: String,
            isReviewed: Boolean, nowEpochMs: Long,
        ) {
            if (sessions.getValue(sessionId).isClosed) throw EvaluationSessionClosedException()
            val key = sessionId to studentId
            rows[key] = rows.getValue(key).copy(
                otherFailedCount = otherFailedCount, agreement = agreement, isReviewed = isReviewed,
            )
        }
    }

    private class Mundo {
        var roster = mutableListOf(1L, 2L, 3L)
        val averages = mutableMapOf<Long, Double?>(1L to 8.0, 2L to 4.5, 3L to null)
        val attendance = mutableMapOf(
            1L to StudentAttendanceStats(absentCount = 0, lateCount = 1, totalRecords = 20),
            2L to StudentAttendanceStats(absentCount = 5, lateCount = 0, totalRecords = 20),
        )
        val incidents = mutableListOf(
            incidente(1, 2L), incidente(2, 2L), incidente(3, null), incidente(4, 1L),
        )
        val measures = mutableMapOf(
            2L to listOf(
                medida(10, 2L, SupportMeasureLevel.III, activa = true, notas = "Diagnóstico confidencial de prueba"),
                medida(11, 2L, SupportMeasureLevel.IV, activa = true, notas = "Informe clínico de prueba"),
            ),
            3L to listOf(medida(12, 3L, SupportMeasureLevel.IV, activa = false, notas = "Retirada")),
        )

        val live = DefaultEvaluationSessionLiveData(
            studentIdsForClass = { roster.toList() },
            notebookAverages = { averages.toMap() },
            attendanceStats = { _, id -> attendance[id] ?: StudentAttendanceStats(0, 0, 0) },
            incidentsForClass = { incidents.toList() },
            supportMeasures = { id -> measures[id].orEmpty() },
        )

        companion object {
            fun incidente(id: Long, studentId: Long?) = Incident(
                id = id, classId = CLASS_ID, studentId = studentId, title = "Incidencia $id",
                date = Instant.fromEpochMilliseconds(0),
            )

            fun medida(id: Long, studentId: Long, level: SupportMeasureLevel, activa: Boolean, notas: String) =
                StudentSupportMeasure(
                    id = id,
                    studentId = studentId,
                    level = level,
                    measureType = if (level == SupportMeasureLevel.IV) SupportMeasureType.ACIS
                    else SupportMeasureType.APR_FORMATO_EXAMEN,
                    startDate = LocalDate(2026, 9, 15),
                    followUpNotes = notas,
                    isActive = activa,
                )
        }
    }

    private fun fixture(): Triple<EvaluationSessionUseCase, FakeSessions, Mundo> {
        val repo = FakeSessions().apply {
            names[1L] = "Ana" to "Abad"
            names[2L] = "Blas" to "Bueno"
            names[3L] = "Celia" to "Campos"
            names[4L] = "Dani" to "Diez"
        }
        val mundo = Mundo()
        var n = 0
        return Triple(EvaluationSessionUseCase(repo, mundo.live, newId = { "junta-${++n}" }), repo, mundo)
    }

    @Test
    fun crearJuntaCreaUnaFilaPorAlumnoYNombrePorDefecto() = runTest {
        val (useCase, repo, _) = fixture()
        val session = useCase.createSession(CLASS_ID, EvaluationKind.INITIAL, "2026-10-28", "  ", "  Tutora, Orientación ", null, 1)
        assertEquals("Evaluación inicial", session.label)
        assertEquals("Tutora, Orientación", session.attendees)
        assertEquals("Tutora, Orientación", repo.getSession(session.id)?.attendees)
        assertEquals(3, repo.listStudents(session.id).size)
        assertFailsWith<EvaluationSessionDuplicateException> {
            useCase.createSession(CLASS_ID, EvaluationKind.INITIAL, "2026-10-29", null, "", null, 2)
        }
        assertFailsWith<EvaluationSessionException> {
            useCase.createSession(CLASS_ID, EvaluationKind.FIRST, "28/10/2026", null, "", null, 3)
        }
    }

    @Test
    fun resumenYTotalesPorAlumno() = runTest {
        val (useCase, _, _) = fixture()
        val id = useCase.createSession(CLASS_ID, EvaluationKind.FIRST, "2026-12-18", null, "", null, 1).id
        // Ana: Media 8 y 0 otras -> 0. Blas: Media 4,5 (suspende) + 2 otras -> 3. Celia: sin Media + 2 otras -> 2.
        useCase.updateStudent(id, 2L, otherFailedCount = 2, agreement = "Refuerzo", isReviewed = true, nowEpochMs = 2)
        useCase.updateStudent(id, 3L, otherFailedCount = 2, agreement = "", isReviewed = false, nowEpochMs = 3)

        val board = useCase.loadBoard(id, 4)
        val porId = board.students.associateBy { it.studentId }
        assertEquals(0, porId.getValue(1L).totalFailed)
        assertEquals(3, porId.getValue(2L).totalFailed)
        assertEquals(true, porId.getValue(2L).ownFailed)
        assertEquals(2, porId.getValue(3L).totalFailed)
        assertNull(porId.getValue(3L).ownFailed)

        assertEquals(
            EvaluationSessionSummary(
                studentCount = 3,
                passAllCount = 1,
                oneOrTwoFailedCount = 1,
                threeOrMoreFailedCount = 1,
                passedOwnSubjectCount = 1,
                reviewedCount = 1,
            ),
            board.summary,
        )
        // Datos en vivo: faltas (nº y %), nivel más alto activo, incidencias del alumno.
        val blas = porId.getValue(2L)
        assertEquals(5, blas.absenceCount)
        assertEquals(25.0, blas.absencePercent)
        assertEquals(SupportMeasureLevel.IV, blas.supportLevel)
        assertEquals(2, blas.incidentCount)
        assertFalse(blas.isFrozen)
        // Sin registros de asistencia no hay porcentaje; medida retirada no cuenta.
        assertNull(porId.getValue(3L).absencePercent)
        assertNull(porId.getValue(3L).supportLevel)
    }

    @Test
    fun cerrarCongelaYLaCerradaUsaLosCongelados() = runTest {
        val (useCase, repo, mundo) = fixture()
        val id = useCase.createSession(CLASS_ID, EvaluationKind.SECOND, "2027-03-20", null, "", null, 1).id
        useCase.updateStudent(id, 1L, 1, "", false, 2)

        val cerrada = useCase.closeSession(id, 10)
        assertTrue(cerrada.session.isClosed)
        assertTrue(cerrada.students.all { it.isFrozen })
        assertEquals(3, repo.lastSnapshots.size)

        // Cambian los datos en vivo: la junta cerrada no se mueve.
        mundo.averages[1L] = 3.0
        mundo.attendance[2L] = StudentAttendanceStats(absentCount = 9, lateCount = 0, totalRecords = 20)
        mundo.measures.remove(2L)
        val leida = useCase.loadBoard(id, 11)
        val porId = leida.students.associateBy { it.studentId }
        assertEquals(8.0, porId.getValue(1L).average)
        assertEquals(1, porId.getValue(1L).totalFailed)
        assertEquals(5, porId.getValue(2L).absenceCount)
        assertEquals(SupportMeasureLevel.IV, porId.getValue(2L).supportLevel)

        // Cerrada no se edita, ni se vuelve a cerrar.
        assertFailsWith<EvaluationSessionClosedException> { useCase.updateStudent(id, 1L, 0, "", true, 12) }
        assertFailsWith<EvaluationSessionClosedException> {
            useCase.updateHeader(id, "x", "2027-03-21", "", "", null, 12)
        }
        assertFailsWith<EvaluationSessionClosedException> { useCase.closeSession(id, 12) }

        // Reabrir vuelve a lo vivo; cerrar de nuevo sobrescribe lo congelado.
        val reabierta = useCase.reopenSession(id, 13)
        assertFalse(reabierta.session.isClosed)
        assertEquals(3.0, reabierta.students.first { it.studentId == 1L }.average)
        useCase.closeSession(id, 14)
        assertEquals(3.0, useCase.loadBoard(id, 15).students.first { it.studentId == 1L }.average)
    }

    @Test
    fun alumnoNuevoEnElGrupoSeAnadeAlAbrirLaJuntaAbierta() = runTest {
        val (useCase, _, mundo) = fixture()
        val id = useCase.createSession(CLASS_ID, EvaluationKind.THIRD, "2027-06-20", null, "", null, 1).id
        mundo.roster.add(4L)
        val board = useCase.loadBoard(id, 2)
        assertEquals(listOf(1L, 2L, 3L, 4L), board.students.map { it.studentId }.sorted())

        // En una cerrada no se añade nadie.
        useCase.closeSession(id, 3)
        mundo.roster.add(5L)
        assertEquals(4, useCase.loadBoard(id, 4).students.size)
    }

    @Test
    fun otrasSuspensasEntre0y15() = runTest {
        val (useCase, repo, _) = fixture()
        val id = useCase.createSession(CLASS_ID, EvaluationKind.FINAL, "2027-06-25", null, "", null, 1).id
        useCase.updateStudent(id, 1L, 0, "", false, 2)
        useCase.updateStudent(id, 1L, 15, "", false, 3)
        assertEquals(15, repo.listStudents(id).first { it.studentId == 1L }.otherFailedCount)
        assertFailsWith<EvaluationSessionException> { useCase.updateStudent(id, 1L, -1, "", false, 4) }
        assertFailsWith<EvaluationSessionException> { useCase.updateStudent(id, 1L, 16, "", false, 5) }
        assertEquals(15, repo.listStudents(id).first { it.studentId == 1L }.otherFailedCount)
    }

    @Test
    fun sinDatosClinicosNiEnVivoNiCongelados() = runTest {
        val (useCase, repo, _) = fixture()
        val id = useCase.createSession(CLASS_ID, EvaluationKind.FIRST, "2026-12-18", null, "", null, 1).id
        val board = useCase.closeSession(id, 2)
        val volcado = board.toString() + repo.lastSnapshots.toString() + repo.rows.values.toString()
        listOf("confidencial", "clínico", "Retirada", "ACIS", "APR_FORMATO_EXAMEN").forEach { prohibido ->
            assertFalse(prohibido in volcado, "la junta no puede contener «$prohibido»")
        }
        assertEquals(SupportMeasureLevel.IV, board.students.first { it.studentId == 2L }.supportLevel)
    }

    @Test
    fun borrarJuntaQuitaSusFilas() = runTest {
        val (useCase, repo, _) = fixture()
        val id = useCase.createSession(CLASS_ID, EvaluationKind.FIRST, "2026-12-18", null, "", null, 1).id
        useCase.deleteSession(id)
        assertTrue(useCase.listSessions(CLASS_ID).isEmpty())
        assertTrue(repo.rows.isEmpty())
        assertFailsWith<EvaluationSessionNotFoundException> { useCase.loadBoard(id, 2) }
    }

    @Test
    fun idAleatorioConFormatoUuid() {
        val id = randomEvaluationSessionId(Random(42))
        assertTrue(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(id), id)
    }
}
