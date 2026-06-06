package com.migestor.data.repository

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver

internal fun JdbcSqliteDriver.scalarLong(sql: String): Long =
    executeQuery(
        identifier = null,
        sql = sql,
        mapper = { cursor ->
            val value = if (cursor.next().value) cursor.getLong(0) ?: 0L else 0L
            QueryResult.Value(value)
        },
        parameters = 0,
    ).value

internal fun JdbcSqliteDriver.queryStrings(sql: String): List<String> =
    executeQuery(
        identifier = null,
        sql = sql,
        mapper = { cursor ->
            val values = mutableListOf<String>()
            while (cursor.next().value) {
                cursor.getString(0)?.let(values::add)
            }
            QueryResult.Value(values)
        },
        parameters = 0,
    ).value

internal fun JdbcSqliteDriver.createLegacyClassesTable() {
    execute(
        null,
        """
        CREATE TABLE IF NOT EXISTS classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            course INTEGER NOT NULL,
            description TEXT,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0
        )
        """.trimIndent(),
        0
    )
}

internal fun JdbcSqliteDriver.createLegacyWorkGroupsTable() {
    execute(
        null,
        """
        CREATE TABLE IF NOT EXISTS notebook_work_groups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            tab_id TEXT NOT NULL,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            UNIQUE(class_id, tab_id, name),
            FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
        )
        """.trimIndent(),
        0
    )
}

internal fun JdbcSqliteDriver.createLegacyPerformanceIndexTables() {
    listOf(
        """
        CREATE TABLE IF NOT EXISTS attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            class_id INTEGER NOT NULL,
            date_epoch_ms INTEGER NOT NULL,
            status TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS incidents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            student_id INTEGER,
            date_epoch_ms INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS notebook_cell_entries (
            class_id INTEGER NOT NULL,
            student_id INTEGER NOT NULL,
            column_id TEXT NOT NULL,
            PRIMARY KEY (class_id, student_id, column_id)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS planned_session (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            school_class_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            start_time TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS teacher_schedule_slots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            teacher_schedule_id INTEGER NOT NULL,
            school_class_id INTEGER NOT NULL,
            day_of_week INTEGER NOT NULL,
            start_time TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS evaluations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS rubric_criteria (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rubric_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS rubric_levels (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            criterion_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS evaluation_competency_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            evaluation_id INTEGER NOT NULL
        )
        """,
    ).forEach { sql ->
        execute(null, sql.trimIndent(), 0)
    }
}

internal fun JdbcSqliteDriver.createLegacyNotebookCellAuditTable() {
    execute(
        null,
        """
        CREATE TABLE IF NOT EXISTS notebook_cell_audit_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            student_id INTEGER NOT NULL,
            column_id TEXT NOT NULL,
            changed_at_epoch_ms INTEGER NOT NULL
        )
        """.trimIndent(),
        0
    )
}
