package com.migestor.data.sync

import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import kotlinx.datetime.Clock

data class SyncDatasetFingerprint(
    val schemaVersion: Long,
    val countsByEntity: Map<String, Int>,
    val digest: String,
    val computedAtEpochMs: Long,
) {
    fun toJson(): String {
        val countsJson = countsByEntity.entries
            .sortedBy { it.key }
            .joinToString(",") { "\"${it.key}\":${it.value}" }
        return "{\"schemaVersion\":$schemaVersion,\"countsByEntity\":{$countsJson},\"digest\":\"$digest\",\"computedAtEpochMs\":$computedAtEpochMs}"
    }

    companion object {
        private const val FNV_OFFSET_BASIS_64: ULong = 14695981039346656037UL
        private const val FNV_PRIME_64: ULong = 1099511628211UL

        fun fnv1a64(text: String): ULong {
            var hash = FNV_OFFSET_BASIS_64
            for (char in text) {
                hash = hash xor (char.code.toULong() and 0xFFUL)
                hash = hash * FNV_PRIME_64
            }
            return hash
        }

        fun computeDigest(records: List<String>): String {
            val sorted = records.sorted()
            var hash = FNV_OFFSET_BASIS_64
            for (record in sorted) {
                for (char in record) {
                    hash = hash xor (char.code.toULong() and 0xFFUL)
                    hash = hash * FNV_PRIME_64
                }
                hash = hash xor '\n'.code.toULong()
                hash = hash * FNV_PRIME_64
            }
            return hash.toString(16).padStart(16, '0')
        }

        suspend fun compute(container: KmpContainer): SyncDatasetFingerprint {
            val records = mutableListOf<String>()
            val counts = mutableMapOf<String, Int>()

            // 1. academic_year
            val years = container.academicYearsRepository.listAcademicYears()
            counts["academic_year"] = years.size
            years.forEach { year ->
                records.add("academic_year:${year.id}:${year.name}:${year.trace.updatedAt.toEpochMilliseconds()}")
            }

            // 2. class & class-related
            val classes = container.classesRepository.listClasses()
            counts["class"] = classes.size
            classes.forEach { schoolClass ->
                records.add("class:${schoolClass.id}:${schoolClass.name}:${schoolClass.trace.updatedAt.toEpochMilliseconds()}")
            }

            // 3. student
            val students = container.studentsRepository.listStudents()
            counts["student"] = students.size
            students.forEach { student ->
                records.add("student:${student.id}:${student.firstName} ${student.lastName}:${student.trace.updatedAt.toEpochMilliseconds()}")
            }

            // 4. class_roster
            var totalRosters = 0
            classes.forEach { schoolClass ->
                val studentsInClass = container.classesRepository.listStudentsInClass(schoolClass.id)
                if (studentsInClass.isNotEmpty()) {
                    totalRosters++
                    val rosterIds = studentsInClass.map { it.id }.sorted().joinToString(",")
                    records.add("class_roster:${schoolClass.id}:$rosterIds")
                }
            }
            counts["class_roster"] = totalRosters

            // 5. evaluation & grade & notebook_tab & notebook_column
            var totalEvaluations = 0
            var totalGrades = 0
            var totalTabs = 0
            var totalColumns = 0

            classes.forEach { schoolClass ->
                val evals = container.evaluationsRepository.listClassEvaluations(schoolClass.id)
                totalEvaluations += evals.size
                evals.forEach { eval ->
                    records.add("evaluation:${eval.id}:${eval.name}:${eval.weight}:${eval.trace.updatedAt.toEpochMilliseconds()}")
                }

                val grades = container.gradesRepository.listGradesForClass(schoolClass.id)
                totalGrades += grades.size
                grades.forEach { grade ->
                    records.add("grade:${grade.classId}-${grade.studentId}-${grade.columnId}:${grade.value ?: 0.0}:${grade.trace.updatedAt.toEpochMilliseconds()}")
                }

                val tabs = container.notebookConfigRepository.listTabs(schoolClass.id)
                totalTabs += tabs.size
                tabs.forEach { tab ->
                    records.add("notebook_tab:${tab.id}:${tab.title}:${tab.trace.updatedAt.toEpochMilliseconds()}")
                }

                val cols = container.notebookConfigRepository.listColumns(schoolClass.id)
                totalColumns += cols.size
                cols.forEach { col ->
                    val colId = col.evaluationId?.let { "eval_$it" } ?: col.id
                    records.add("notebook_column:$colId:${col.title}:${col.trace.updatedAt.toEpochMilliseconds()}")
                }
            }
            counts["evaluation"] = totalEvaluations
            counts["grade"] = totalGrades
            counts["notebook_tab"] = totalTabs
            counts["notebook_column"] = totalColumns

            // 6. teaching_unit & planning_session
            val units = container.plannerRepository.listAllTeachingUnits()
            counts["teaching_unit"] = units.size
            units.forEach { unit ->
                records.add("teaching_unit:${unit.id}:${unit.name}")
            }

            val sessions = container.plannerRepository.listAllSessions()
            counts["planning_session"] = sessions.size
            sessions.forEach { session ->
                records.add("planning_session:${session.id}:${session.status.name}")
            }

            // 7. learning_situation
            val situations = container.learningSituationsRepository.listSituations()
            counts["learning_situation"] = situations.size
            situations.forEach { situation ->
                records.add("learning_situation:${situation.id}:${situation.trace.updatedAt.toEpochMilliseconds()}")
            }

            val digest = computeDigest(records)
            val schemaVersion = AppDatabase.Schema.version

            return SyncDatasetFingerprint(
                schemaVersion = schemaVersion,
                countsByEntity = counts,
                digest = digest,
                computedAtEpochMs = Clock.System.now().toEpochMilliseconds(),
            )
        }
    }
}
