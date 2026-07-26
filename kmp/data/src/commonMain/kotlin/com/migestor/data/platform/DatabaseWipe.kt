package com.migestor.data.platform

import app.cash.sqldelight.Transacter
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver

/**
 * Vacia todas las tablas de datos del usuario **sin tocar los ficheros de la base**.
 *
 * Existe porque el borrado total de Apple (`SettingsDangerZoneView.wipeAllData()`)
 * eliminaba `desktop_mi_gestor_kmp.db`, `-wal` y `-shm` del disco mientras el driver
 * de SQLDelight los tenia abiertos. macOS invalida entonces todos los descriptores
 * del pool de conexiones (`vnode unlinked while in use` + `invalidated open fd`), la
 * siguiente consulta falla con `SQLITE_IOERR` y el proceso aborta. Ese fue un crash
 * real reportado por el usuario, parcheado dos veces por sintomas (guards de
 * `needsRestart`) antes de atacar la causa.
 *
 * Borrar el *contenido* por SQL con la conexion que ya esta abierta no invalida
 * ningun descriptor, no puede fallar por E/S y deja el esquema y `user_version`
 * intactos: la app sigue siendo utilizable sin reiniciar.
 *
 * No borra los adjuntos ni las copias de seguridad (ficheros que nadie tiene
 * abiertos): de eso se encarga la capa Swift, que si puede borrarlos con seguridad.
 */
internal fun wipeAllUserData(driver: SqlDriver, transacter: Transacter) {
    val allTables = allTableNames(driver)
    val tables = allTables.filterNot { it.startsWith("sqlite_") || it == "android_metadata" }

    // `defer_foreign_keys` aplaza la comprobacion de claves ajenas al commit, de modo
    // que el orden en que se vacian las tablas deja de importar. Sin esto habria que
    // mantener a mano un orden topologico de ~60 tablas que se rompe en cuanto alguien
    // añade una relacion nueva.
    driver.execute(null, "PRAGMA defer_foreign_keys = ON", 0)

    // Todo o nada: si una tabla falla, no queda una base a medio vaciar.
    transacter.transaction {
        for (table in tables) {
            driver.execute(null, """DELETE FROM "$table"""", 0)
        }
        // Reinicia los AUTOINCREMENT para que la base recien vaciada no siga entregando
        // ids altos heredados de los datos borrados.
        if ("sqlite_sequence" in allTables) {
            driver.execute(null, "DELETE FROM sqlite_sequence", 0)
        }
    }

    // Fuera de transaccion: vuelca los datos confirmados del WAL al fichero principal
    // y trunca el fichero WAL a 0 bytes sin reconstruir la base ni tocar descriptores de archivo.
    // NUNCA usar VACUUM aquí: VACUUM crea un fichero db temporal, borra el original y renombra,
    // lo que en macOS desvincula el vnode (`vnode unlinked while in use`) en conexiones concurrentes.
    try {
        driver.execute(null, "PRAGMA wal_checkpoint(TRUNCATE)", 0)
    } catch (error: Throwable) {
        println("[DatabaseWipe] WAL checkpoint fallo tras el borrado (no critico): ${error.message}")
    }
}

/**
 * Todas las tablas de la base. Se consulta a `sqlite_master` en vez de mantener una
 * lista fija para que una tabla nueva no se quede sin borrar en silencio la proxima
 * vez que alguien toque el esquema.
 */
private fun allTableNames(driver: SqlDriver): List<String> {
    return driver.executeQuery(
        identifier = null,
        sql = "SELECT name FROM sqlite_master WHERE type = 'table'",
        mapper = { cursor ->
            val names = mutableListOf<String>()
            while (cursor.next().value) {
                cursor.getString(0)?.let(names::add)
            }
            QueryResult.Value(names)
        },
        parameters = 0,
    ).value
}
