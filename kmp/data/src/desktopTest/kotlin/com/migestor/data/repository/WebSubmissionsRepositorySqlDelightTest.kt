package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.repository.WebFormInstance
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WebSubmissionsRepositorySqlDelightTest {
    @Test
    fun `batch actions preserve form history and update archive independently`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val database = AppDatabase(driver)
        val repository = WebSubmissionsRepositorySqlDelight(database)

        repository.saveFormInstance(form("form_1"))
        repository.saveFormInstance(form("form_2"))

        repository.archiveFormInstances(listOf("form_1", "form_2"), updatedAtEpochMs = 20)
        assertTrue(repository.getFormInstance("form_1")!!.archived)
        assertTrue(repository.getFormInstance("form_2")!!.archived)

        repository.restoreArchivedFormInstances(listOf("form_1"), updatedAtEpochMs = 30)
        assertFalse(repository.getFormInstance("form_1")!!.archived)
        assertTrue(repository.getFormInstance("form_2")!!.archived)

        repository.revokeFormInstances(listOf("form_1", "form_2"), updatedAtEpochMs = 40)
        val instances = repository.listAllFormInstances().associateBy { it.formInstanceId }
        assertEquals(setOf("form_1", "form_2"), instances.keys)
        assertTrue(instances.getValue("form_1").revoked)
        assertTrue(instances.getValue("form_2").revoked)
        assertFalse(instances.getValue("form_1").archived)
        assertTrue(instances.getValue("form_2").archived)
    }

    private fun form(id: String) = WebFormInstance(
        formInstanceId = id,
        classId = 1,
        columnId = "column_1",
        templateId = null,
        title = id,
        recipientPublicKey = "x25519:test",
        privateKeyRef = "keychain:$id",
        publisherPublicKey = "ed25519:test",
        expiresAtEpochMs = 1_000,
        revoked = false,
        archived = false,
        manifestJson = "{}",
        createdAtEpochMs = 1,
        updatedAtEpochMs = 1,
    )
}
