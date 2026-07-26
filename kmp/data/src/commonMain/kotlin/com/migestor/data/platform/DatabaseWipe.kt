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

enum class WipeCategory(
    val displayName: String,
    val description: String,
    val tableNames: List<String>,
) {
    CLASSES(
        displayName = "Cursos y evaluaciones",
        description = "Clases, calificaciones, cuaderno docente, asistencias e incidencias",
        tableNames = listOf(
            "classes", "class_students", "student_enrollments", "evaluations", "grades",
            "attendance", "incidents", "notebook_tabs", "notebook_columns",
            "notebook_column_categories", "notebook_work_groups", "notebook_cell_entries",
            "notebook_instrument_templates", "notebook_instrument_items", "notebook_instrument_responses"
        )
    ),
    STUDENTS(
        displayName = "Alumnado",
        description = "Fichas de estudiantes, medidas de apoyo y tutorías",
        tableNames = listOf(
            "students", "student_support_measures", "student_tutoring_sessions"
        )
    ),
    RUBRICS(
        displayName = "Rúbricas",
        description = "Plantillas de rúbricas, criterios, niveles y evaluaciones de rúbrica",
        tableNames = listOf(
            "rubrics", "rubric_criteria", "rubric_levels", "rubric_assessments"
        )
    ),
    LEARNING_SITUATIONS(
        displayName = "Situaciones de aprendizaje",
        description = "Unidades didácticas, planes de sesión y recursos enlazados",
        tableNames = listOf(
            "learning_situations", "learning_situation_versions", "learning_situation_classes",
            "learning_situation_links", "learning_situation_sequence_versions",
            "learning_situation_session_plans", "units", "sessions"
        )
    ),
    TEACHER_SCHEDULE(
        displayName = "Horario y Planificador",
        description = "Franjas de horario, calendario, sesiones planificadas y diario",
        tableNames = listOf(
            "teacher_schedules", "teacher_schedule_slots", "planner_evaluation_periods",
            "calendar_events", "planner_week_plan", "weekly_template_slots", "planned_sessions",
            "session_journal"
        )
    ),
    MEETINGS(
        displayName = "Reuniones",
        description = "Actas de reunión y acuerdos registrados",
        tableNames = listOf(
            "meetings", "meeting_agreements"
        )
    ),
    AI_AUDIT(
        displayName = "Auditoría de IA",
        description = "Historial de sugerencias y logs de agentes de IA local",
        tableNames = listOf(
            "ai_audit_events"
        )
    )
}

/**
 * Vacia las tablas pertenecientes a las categorias seleccionadas **sin tocar los ficheros de la base**
 * ni eliminar las copias de seguridad.
 */
internal fun wipeSelectiveUserData(
    driver: SqlDriver,
    transacter: Transacter,
    categories: Set<WipeCategory>
) {
    if (categories.isEmpty()) return
    val allTables = allTableNames(driver)
    val targetTables = categories.flatMap { it.tableNames }.distinct().filter { it in allTables }

    driver.execute(null, "PRAGMA defer_foreign_keys = ON", 0)

    transacter.transaction {
        for (table in targetTables) {
            driver.execute(null, """DELETE FROM "$table"""", 0)
        }
        if ("sqlite_sequence" in allTables && categories.contains(WipeCategory.CLASSES)) {
            driver.execute(null, "DELETE FROM sqlite_sequence", 0)
        }
    }

    try {
        driver.execute(null, "PRAGMA wal_checkpoint(TRUNCATE)", 0)
    } catch (error: Throwable) {
        println("[DatabaseWipe] WAL checkpoint fallo tras el borrado selectivo (no critico): ${error.message}")
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
