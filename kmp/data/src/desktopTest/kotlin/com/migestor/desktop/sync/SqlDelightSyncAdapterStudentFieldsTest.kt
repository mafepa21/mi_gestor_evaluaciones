package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.domain.StudentSexSource
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Regresión: el caso "student" de `applyIncomingChangesLww` no leía
 * sex/sexSource/birthDate del payload entrante y llamaba a `saveStudent` (sin
 * guard LWW, pensado para ediciones locales) con los defaults
 * UNSPECIFIED/UNKNOWN/null. Un dispositivo que solo cambiaba, por ejemplo, el
 * apellido —o incluso un cambio MÁS ANTIGUO, porque no había comparación de
 * `updated_at`— borraba sexo y fecha de nacimiento ya registrados desde otro
 * dispositivo. Ver `SqlDelightSyncAdapter.kt` (caso "student") y
 * `StudentsRepositorySqlDelight.upsertStudent`.
 */
class SqlDelightSyncAdapterStudentFieldsTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun studentPayload(
        id: Long,
        firstName: String = "Ana",
        lastName: String = "López",
        sex: StudentSex? = null,
        sexSource: StudentSexSource? = null,
        birthDate: LocalDate? = null,
    ): String = buildJsonObject {
        put("id", id)
        put("firstName", firstName)
        put("lastName", lastName)
        sex?.let { put("sex", it.name) }
        sexSource?.let { put("sexSource", it.name) }
        birthDate?.let { put("birthDate", it.toString()) }
    }.toString()

    @Test
    fun `sex, sexSource y birthDate del payload entrante se aplican`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        // updatedAtEpochMs explicito y anterior al cambio entrante (200L): si se
        // dejara en 0 (default), saveStudent usaria Clock.System.now() -un epoch
        // real, muchisimo mayor que 200- y el guard LWW del cambio entrante
        // rechazaria la escritura por "mas antigua", enmascarando lo que este test
        // quiere probar.
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López", updatedAtEpochMs = 1L)

        val ack = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "student",
                    id = studentId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "ios",
                    payload = studentPayload(
                        studentId,
                        sex = StudentSex.FEMALE,
                        sexSource = StudentSexSource.MANUAL,
                        birthDate = LocalDate(2012, 3, 15),
                    ),
                )
            )
        )

        val updated = container.studentsRepository.getStudent(studentId)
        assertEquals(StudentSex.FEMALE, updated?.sex)
        assertEquals(StudentSexSource.MANUAL, updated?.sexSource)
        assertEquals(LocalDate(2012, 3, 15), updated?.birthDate)
        assertEquals(1, ack.applied)
    }

    @Test
    fun `un cambio entrante mas antiguo no borra sexo ni fecha de nacimiento ya guardados`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        // El Mac ya tiene sexo y fecha de nacimiento registrados, en t=1000.
        val studentId = container.studentsRepository.saveStudent(
            firstName = "Ana",
            lastName = "López",
            sex = StudentSex.FEMALE,
            sexSource = StudentSexSource.MANUAL,
            birthDate = LocalDate(2012, 3, 15),
            updatedAtEpochMs = 1000L,
            deviceId = "mac",
        )

        // Llega un cambio de un iPad fechado ANTES (t=500) que solo edito el
        // apellido y nunca envio sex/sexSource/birthDate (payload sin esos campos).
        val ack = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "student",
                    id = studentId.toString(),
                    updatedAtEpochMs = 500L,
                    deviceId = "ios",
                    payload = studentPayload(studentId, lastName = "López García"),
                )
            )
        )

        val stillOriginal = container.studentsRepository.getStudent(studentId)
        assertEquals("López", stillOriginal?.lastName, "El cambio mas antiguo no debe aplicarse en absoluto (guard LWW)")
        assertEquals(StudentSex.FEMALE, stillOriginal?.sex)
        assertEquals(StudentSexSource.MANUAL, stillOriginal?.sexSource)
        assertEquals(LocalDate(2012, 3, 15), stillOriginal?.birthDate)
        // NOTA: el guard LWW vive dentro de upsertStudent (silencioso, igual que
        // upsertGrade); el "student" -> ... applied++ del nivel superior no sabe
        // si la escritura se aplico de verdad, asi que ack.applied sigue marcando
        // 1 aunque el guard haya descartado el cambio. Es un comportamiento
        // preexistente (igual para grades) y no algo que corrija este fix; lo
        // que importa aqui es el estado real de los datos, verificado arriba.
        assertEquals(1, ack.applied)
        assertEquals(0, ack.ignored)
    }
}
