package com.migestor.shared.repository

/**
 * Contrato de la tabla de correspondencias de las entregas del alumnado hechas
 * desde la web. Diseño en `plan_entregas_web_alumnado_2026-07-29.md`; esquema en
 * la migracion 39.
 *
 * Los modelos viven aqui y no en `domain/Models.kt` a proposito: son tipos de
 * frontera de esta feature, no conceptos del dominio docente. Un `WebAliasEntry`
 * no significa nada para el Cuaderno ni para las notas; solo existe para traducir
 * lo que manda un navegador. Mantenerlos fuera del dominio evita ademas tocar un
 * archivo protegido sin necesidad.
 *
 * Ninguna de estas cuatro entidades lleva `deviceId` ni `syncVersion`, y es
 * deliberado: no deben viajar por Sync LAN. Su valor de privacidad depende de
 * existir en un solo dispositivo. Ver la cabecera de `39.sqm`.
 */

/** Un formulario publicado. `formInstanceId` es lo unico que ve la web. */
data class WebFormInstance(
    val formInstanceId: String,
    val classId: Long,
    val columnId: String,
    val templateId: String?,
    val title: String,
    /** Clave publica X25519 etiquetada (`x25519:...`) que se publica en el manifiesto. */
    val recipientPublicKey: String,
    /**
     * Referencia a la clave privada en el llavero del sistema. La clave en si
     * NUNCA se guarda en la base de datos: si la base se copia o se restaura en
     * otro sitio, las entregas siguen sin poder abrirse.
     */
    val privateKeyRef: String,
    /** Clave publica Ed25519 etiquetada con la que se firma el manifiesto. */
    val publisherPublicKey: String?,
    val expiresAtEpochMs: Long,
    val revoked: Boolean,
    val createdAtEpochMs: Long,
    val updatedAtEpochMs: Long,
)

/** alias -> alumno, dentro de un formulario concreto. */
data class WebAliasEntry(
    val alias: String,
    val studentId: Long,
    val createdAtEpochMs: Long,
)

/** `webItemId` -> `notebook_instrument_items.id`. */
data class WebItemMapEntry(
    val webItemId: String,
    val itemId: String,
    val itemType: String,
)

/** Estado de una entrega ya vista. Sirve para la idempotencia. */
data class WebLedgerEntry(
    val submissionId: String,
    val formInstanceId: String,
    val alias: String?,
    val studentId: Long?,
    /** `IMPORTED` o `REJECTED`. */
    val status: String,
    val rejectReason: String?,
    val answerCount: Long,
    val clientSubmittedAtEpochMs: Long,
    val importedAtEpochMs: Long,
)

interface WebSubmissionsRepository {
    @Throws(Throwable::class)
    suspend fun getFormInstance(formInstanceId: String): WebFormInstance?

    @Throws(Throwable::class)
    suspend fun listFormInstancesForClass(classId: Long): List<WebFormInstance>

    @Throws(Throwable::class)
    suspend fun saveFormInstance(instance: WebFormInstance)

    @Throws(Throwable::class)
    suspend fun revokeFormInstance(formInstanceId: String, updatedAtEpochMs: Long)

    /**
     * Todos los alias de un formulario de una vez. La pantalla de importacion los
     * carga en bloque y luego resuelve en memoria: son pocos (uno por alumno) y
     * asi se evita una consulta por entrega.
     */
    @Throws(Throwable::class)
    suspend fun listAliases(formInstanceId: String): List<WebAliasEntry>

    @Throws(Throwable::class)
    suspend fun saveAliases(formInstanceId: String, entries: List<WebAliasEntry>)

    @Throws(Throwable::class)
    suspend fun listItemMap(formInstanceId: String): List<WebItemMapEntry>

    @Throws(Throwable::class)
    suspend fun saveItemMap(formInstanceId: String, entries: List<WebItemMapEntry>)

    @Throws(Throwable::class)
    suspend fun getLedgerEntry(submissionId: String): WebLedgerEntry?

    /** Los `submissionId` ya registrados de un formulario, para la idempotencia. */
    @Throws(Throwable::class)
    suspend fun listLedgerForForm(formInstanceId: String): List<WebLedgerEntry>

    @Throws(Throwable::class)
    suspend fun recordLedgerEntry(entry: WebLedgerEntry)
}
