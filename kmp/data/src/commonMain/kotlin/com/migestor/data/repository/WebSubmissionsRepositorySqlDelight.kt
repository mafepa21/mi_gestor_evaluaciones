package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.repository.WebAliasEntry
import com.migestor.shared.repository.WebFormInstance
import com.migestor.shared.repository.WebItemMapEntry
import com.migestor.shared.repository.WebLedgerEntry
import com.migestor.shared.repository.WebSubmissionsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Tabla de correspondencias de las entregas del alumnado hechas desde la web.
 * Esquema en la migracion 39.
 *
 * Va en un fichero propio y no en `SqlDelightRepositories.kt` (2.700 lineas) para
 * que la frontera de esta feature se pueda leer de una vez.
 *
 * Las escrituras en lote (alias e items) van en una transaccion: si se publica un
 * formulario y a mitad falla algo, es mejor no tener ningun alias que tener la
 * mitad, porque un alias que falta deja a un alumno sin poder entregar.
 */
class WebSubmissionsRepositorySqlDelight(
    private val db: AppDatabase,
) : WebSubmissionsRepository {

    override suspend fun getFormInstance(formInstanceId: String): WebFormInstance? =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectWebFormInstance(formInstanceId)
                .executeAsOneOrNull()
                ?.let { fila ->
                    WebFormInstance(
                        formInstanceId = fila.form_instance_id,
                        classId = fila.class_id,
                        columnId = fila.column_id,
                        templateId = fila.template_id,
                        title = fila.title,
                        recipientPublicKey = fila.recipient_public_key,
                        privateKeyRef = fila.private_key_ref,
                        publisherPublicKey = fila.publisher_public_key,
                        expiresAtEpochMs = fila.expires_at_epoch_ms,
                        revoked = fila.revoked != 0L,
                        manifestJson = fila.manifest_json,
                        createdAtEpochMs = fila.created_at_epoch_ms,
                        updatedAtEpochMs = fila.updated_at_epoch_ms,
                    )
                }
        }

    override suspend fun listFormInstancesForClass(classId: Long): List<WebFormInstance> =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectWebFormInstancesByClass(classId).executeAsList().map { fila ->
                mapFormInstance(fila)
            }
        }

    override suspend fun listAllFormInstances(): List<WebFormInstance> =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectAllWebFormInstances().executeAsList().map(::mapFormInstance)
        }

    override suspend fun saveFormInstance(instance: WebFormInstance) =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.upsertWebFormInstance(
                form_instance_id = instance.formInstanceId,
                class_id = instance.classId,
                column_id = instance.columnId,
                template_id = instance.templateId,
                title = instance.title,
                recipient_public_key = instance.recipientPublicKey,
                private_key_ref = instance.privateKeyRef,
                publisher_public_key = instance.publisherPublicKey,
                expires_at_epoch_ms = instance.expiresAtEpochMs,
                revoked = if (instance.revoked) 1L else 0L,
                manifest_json = instance.manifestJson,
                created_at_epoch_ms = instance.createdAtEpochMs,
                updated_at_epoch_ms = instance.updatedAtEpochMs,
            )
        }

    override suspend fun revokeFormInstance(formInstanceId: String, updatedAtEpochMs: Long) =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.revokeWebFormInstance(updatedAtEpochMs, formInstanceId)
        }

    override suspend fun listAliases(formInstanceId: String): List<WebAliasEntry> =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectWebAliasesForForm(formInstanceId).executeAsList().map { fila ->
                WebAliasEntry(
                    alias = fila.alias,
                    studentId = fila.student_id,
                    createdAtEpochMs = fila.created_at_epoch_ms,
                )
            }
        }

    override suspend fun saveAliases(formInstanceId: String, entries: List<WebAliasEntry>) =
        withContext(Dispatchers.Default) {
            db.transaction {
                entries.forEach { entrada ->
                    db.appDatabaseQueries.upsertWebAlias(
                        form_instance_id = formInstanceId,
                        alias = entrada.alias,
                        student_id = entrada.studentId,
                        created_at_epoch_ms = entrada.createdAtEpochMs,
                    )
                }
            }
        }

    override suspend fun listItemMap(formInstanceId: String): List<WebItemMapEntry> =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectWebItemMapForForm(formInstanceId).executeAsList().map { fila ->
                WebItemMapEntry(
                    webItemId = fila.web_item_id,
                    itemId = fila.item_id,
                    itemType = fila.item_type,
                )
            }
        }

    override suspend fun saveItemMap(formInstanceId: String, entries: List<WebItemMapEntry>) =
        withContext(Dispatchers.Default) {
            db.transaction {
                entries.forEach { entrada ->
                    db.appDatabaseQueries.upsertWebItemMap(
                        form_instance_id = formInstanceId,
                        web_item_id = entrada.webItemId,
                        item_id = entrada.itemId,
                        item_type = entrada.itemType,
                    )
                }
            }
        }

    override suspend fun getLedgerEntry(submissionId: String): WebLedgerEntry? =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectWebSubmissionLedgerEntry(submissionId)
                .executeAsOneOrNull()
                ?.let(::mapLedger)
        }

    override suspend fun listLedgerForForm(formInstanceId: String): List<WebLedgerEntry> =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectWebSubmissionLedgerForForm(formInstanceId)
                .executeAsList()
                .map(::mapLedger)
        }

    override suspend fun recordLedgerEntry(entry: WebLedgerEntry) =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.upsertWebSubmissionLedgerEntry(
                submission_id = entry.submissionId,
                form_instance_id = entry.formInstanceId,
                alias = entry.alias,
                student_id = entry.studentId,
                status = entry.status,
                reject_reason = entry.rejectReason,
                answer_count = entry.answerCount,
                client_submitted_at_epoch_ms = entry.clientSubmittedAtEpochMs,
                imported_at_epoch_ms = entry.importedAtEpochMs,
            )
        }

    private fun mapFormInstance(fila: com.migestor.data.db.Web_form_instances): WebFormInstance =
        WebFormInstance(
            formInstanceId = fila.form_instance_id,
            classId = fila.class_id,
            columnId = fila.column_id,
            templateId = fila.template_id,
            title = fila.title,
            recipientPublicKey = fila.recipient_public_key,
            privateKeyRef = fila.private_key_ref,
            publisherPublicKey = fila.publisher_public_key,
            expiresAtEpochMs = fila.expires_at_epoch_ms,
            revoked = fila.revoked != 0L,
            manifestJson = fila.manifest_json,
            createdAtEpochMs = fila.created_at_epoch_ms,
            updatedAtEpochMs = fila.updated_at_epoch_ms,
        )

    private fun mapLedger(fila: com.migestor.data.db.Web_submission_ledger): WebLedgerEntry =
        WebLedgerEntry(
            submissionId = fila.submission_id,
            formInstanceId = fila.form_instance_id,
            alias = fila.alias,
            studentId = fila.student_id,
            status = fila.status,
            rejectReason = fila.reject_reason,
            answerCount = fila.answer_count,
            clientSubmittedAtEpochMs = fila.client_submitted_at_epoch_ms,
            importedAtEpochMs = fila.imported_at_epoch_ms,
        )
}
