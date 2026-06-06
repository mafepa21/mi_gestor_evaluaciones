package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationLinkedResource
import com.migestor.shared.domain.LearningSituationResourceKind
import com.migestor.shared.domain.LearningSituationSessionPlan
import com.migestor.shared.domain.LearningSituationSessionSequenceVersion
import com.migestor.shared.domain.LearningSituationStatus
import com.migestor.shared.domain.LearningSituationVersion
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull

class LearningSituationsRepositorySqlDelightTest {
    @Test
    fun `schema migration from 22 creates learning situation tables and planner link column`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        createVersion22Baseline(driver)
        driver.createLegacyPerformanceIndexTables()
        driver.createLegacyNotebookCellAuditTable()

        AppDatabase.Schema.migrate(driver, 22, AppDatabase.Schema.version)

        assertEquals(
            setOf(
                "learning_situations",
                "learning_situation_versions",
                "learning_situation_classes",
                "learning_situation_links",
                "learning_situation_sequence_versions",
                "learning_situation_session_plans",
            ),
            existingLearningSituationTables(driver),
        )
        assertEquals(
            1L,
            driver.scalarLong(
                "SELECT COUNT(*) FROM pragma_table_info('planner_session') WHERE name = 'learning_situation_session_plan_id'",
            ),
        )
        assertEquals(1L, driver.scalarLong("SELECT COUNT(*) FROM planner_session WHERE id = 1"))
    }

    @Test
    fun `repository persists situation versions sequence plans class links and resource links`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val repository = LearningSituationsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "2 ESO A", course = 2, description = "EF")
        val situationId = repository.saveSituation(
            LearningSituation(
                title = "Orientacion en el centro",
                stageLabel = "ESO",
                courseLabel = "2 ESO",
                subjectLabel = "Educacion Fisica",
                termLabel = "2",
                centerLabel = "IES Demo",
                sessionCount = 4,
                challenge = "Resolver un recorrido cooperativo",
                finalProduct = "Mapa anotado",
                payloadJson = """{"source":"fixture"}""",
                status = LearningSituationStatus.ACTIVE,
            )
        )
        assertNotEquals(0L, situationId)

        val importedVersionId = repository.saveVersion(
            LearningSituationVersion(
                learningSituationId = situationId,
                versionNumber = 0,
                originalFileName = "situacion.docx",
                sha256 = "abc123",
                sizeBytes = 128,
                payloadJson = """{"title":"imported"}""",
                warningsJson = """["revisar criterios"]""",
            )
        )
        val sequenceVersionId = repository.saveSessionSequenceVersion(
            LearningSituationSessionSequenceVersion(
                learningSituationId = situationId,
                versionNumber = 0,
                originalFileName = "secuencia.docx",
                sha256 = "def456",
                sizeBytes = 256,
            )
        )
        val planId = repository.saveSessionPlan(
            LearningSituationSessionPlan(
                learningSituationId = situationId,
                sequenceVersionId = sequenceVersionId,
                sessionNumber = 1,
                sourceLabel = "Sesion 1",
                title = "Exploracion del espacio",
                sessionType = "Practica",
                effectiveMinutes = 50,
                objective = "Identificar referencias espaciales",
                criteriaJson = """["CE1"]""",
                material = "Conos y mapa",
                developmentJson = """["inicio","reto"]""",
                adaptationsJson = """["parejas"]""",
            )
        )

        repository.replaceClassLinks(situationId, listOf(classId, classId))
        val resourceId = repository.saveLinkedResource(
            LearningSituationLinkedResource(
                learningSituationId = situationId,
                kind = LearningSituationResourceKind.PLANNING_SESSION,
                resourceId = planId.toString(),
                classId = classId,
                label = "Sesion planificada",
            )
        )

        val situation = repository.getSituation(situationId)
        assertNotNull(situation)
        assertEquals("Orientacion en el centro", situation.title)
        assertEquals(LearningSituationStatus.ACTIVE, situation.status)
        assertEquals(4, situation.sessionCount)

        val versions = repository.listVersions(situationId)
        assertEquals(listOf(importedVersionId), versions.map { it.id })
        assertEquals(1, versions.first().versionNumber)

        val sequenceVersions = repository.listSessionSequenceVersions(situationId)
        assertEquals(listOf(sequenceVersionId), sequenceVersions.map { it.id })
        assertEquals(1, sequenceVersions.first().versionNumber)

        val plans = repository.listSessionPlans(sequenceVersionId)
        assertEquals(listOf(planId), plans.map { it.id })
        assertEquals("Exploracion del espacio", plans.first().title)
        assertEquals(planId, repository.getSessionPlan(planId)?.id)

        val classLinks = repository.listClassLinks(situationId)
        assertEquals(listOf(classId), classLinks.map { it.classId })

        val resources = repository.listLinkedResources(situationId)
        assertEquals(listOf(resourceId), resources.map { it.id })
        assertEquals(LearningSituationResourceKind.PLANNING_SESSION, resources.first().kind)
        assertEquals(classId, resources.first().classId)
    }

    private fun createVersion22Baseline(driver: JdbcSqliteDriver) {
        driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        driver.execute(
            null,
            """
            CREATE TABLE classes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                course INTEGER NOT NULL,
                description TEXT,
                updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
                device_id TEXT,
                sync_version INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
            0,
        )
        driver.execute(
            null,
            """
            CREATE TABLE notebook_tabs (
                id TEXT PRIMARY KEY,
                class_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                is_archived INTEGER NOT NULL DEFAULT 0,
                created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
                updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
            0,
        )
        driver.execute(
            null,
            """
            CREATE TABLE planner_session (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                group_id INTEGER NOT NULL,
                period INTEGER NOT NULL,
                unit_id INTEGER,
                objectives TEXT DEFAULT '',
                activities TEXT DEFAULT '',
                evaluation TEXT DEFAULT '',
                linked_assessment_ids_csv TEXT NOT NULL DEFAULT '',
                teacher_schedule_slot_id INTEGER,
                start_time TEXT,
                end_time TEXT,
                status TEXT DEFAULT 'PENDING',
                updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
                device_id TEXT,
                sync_version INTEGER NOT NULL DEFAULT 0,
                UNIQUE(date, group_id, period),
                FOREIGN KEY (group_id) REFERENCES classes(id) ON DELETE CASCADE
            )
            """.trimIndent(),
            0,
        )
        driver.execute(null, "INSERT INTO classes(id, name, course) VALUES (1, '1 ESO A', 1)", 0)
        driver.execute(
            null,
            "INSERT INTO planner_session(id, date, group_id, period, status) VALUES (1, '2026-05-31', 1, 1, 'PLANNED')",
            0,
        )
        driver.createLegacyWorkGroupsTable()
    }

    private fun existingLearningSituationTables(driver: JdbcSqliteDriver): Set<String> =
        driver.queryStrings(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table' AND name LIKE 'learning_situation%'
            ORDER BY name
            """.trimIndent(),
        ).toSet()
}
