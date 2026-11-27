package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookColumnCategoryKind
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.gradeValueFor
import com.migestor.shared.workgroup.WorkGroupMark

/**
 * Lo que la hoja «Agrupar automáticamente» manda para el criterio «Por nivel técnico»:
 * columnas elegidas en cada apartado, marcas del docente y los dos interruptores.
 */
data class WorkGroupSkillRequest(
    val techniqueColumnIds: List<String> = emptyList(),
    val behaviourColumnIds: List<String> = emptyList(),
    val leadershipColumnIds: List<String> = emptyList(),
    val marks: Map<Long, WorkGroupMark> = emptyMap(),
    val oneLeaderPerGroup: Boolean = true,
    val spreadLowBehaviour: Boolean = true,
)

/** Qué mide un grupo de instrumentos al organizar grupos por nivel. */
enum class WorkGroupSkillDimension {
    TECHNIQUE,
    BEHAVIOUR,
    LEADERSHIP,
}

/**
 * Columnas del Cuaderno que pueden dar una nota de técnica, comportamiento o
 * liderazgo, la sugerencia inicial de cuáles van en cada apartado y la nota de
 * cada alumno con las columnas elegidas.
 */
object WorkGroupSkillColumns {

    private val gradedTypes = setOf(NotebookColumnType.NUMERIC, NotebookColumnType.RUBRIC, NotebookColumnType.ORDINAL)

    /**
     * Columnas con nota que el docente puede elegir: numéricas, rúbricas y ordinales,
     * sin archivadas ni plantillas. Las calculadas quedan fuera: su nota sale de otras.
     * La asistencia y los datos brutos de pruebas físicas tampoco son una nota de nivel.
     */
    fun candidates(columns: List<NotebookColumnDefinition>): List<NotebookColumnDefinition> =
        columns.filter { column ->
            column.type in gradedTypes &&
                column.visibility != NotebookColumnVisibility.ARCHIVED &&
                !column.isTemplate &&
                column.categoryKind != NotebookColumnCategoryKind.ATTENDANCE
        }

    /** Ids de las columnas que parecen de ese apartado por su nombre o su tipo de instrumento. */
    fun suggest(columns: List<NotebookColumnDefinition>, dimension: WorkGroupSkillDimension): List<String> =
        candidates(columns).filter { matches(it, dimension) }.map { it.id }

    fun matches(column: NotebookColumnDefinition, dimension: WorkGroupSkillDimension): Boolean {
        val title = normalize(column.title)
        val keywords = when (dimension) {
            WorkGroupSkillDimension.TECHNIQUE -> techniqueKeywords
            WorkGroupSkillDimension.BEHAVIOUR -> behaviourKeywords
            WorkGroupSkillDimension.LEADERSHIP -> leadershipKeywords
        }
        if (keywords.any { title.contains(it) }) return true
        return dimension == WorkGroupSkillDimension.BEHAVIOUR &&
            column.instrumentKind in setOf(NotebookInstrumentKind.BEHAVIOUR, NotebookInstrumentKind.ATTITUDE)
    }

    /**
     * Nota de 0 a 10 de cada alumno: media simple de las columnas elegidas que tienen
     * nota. Un alumno sin ninguna nota en ellas no aparece en el resultado.
     */
    fun scores(
        rows: List<NotebookRow>,
        columns: List<NotebookColumnDefinition>,
        columnIds: Collection<String>,
        numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
    ): Map<Long, Double> {
        if (columnIds.isEmpty()) return emptyMap()
        val wanted = columnIds.toSet()
        val selected = candidates(columns).filter { it.id in wanted }
        if (selected.isEmpty()) return emptyMap()
        return rows.mapNotNull { row ->
            val values = selected.mapNotNull { row.gradeValueFor(it, numericDrafts = numericDrafts) }
            if (values.isEmpty()) null else row.student.id to values.average()
        }.toMap()
    }

    private val techniqueKeywords = listOf("tecnic", "habilidad", "destreza", "ejecucion", "motriz", "motor")
    private val behaviourKeywords = listOf("comportamiento", "conducta", "actitud", "convivencia", "respeto", "disciplina")
    private val leadershipKeywords = listOf("lider", "capitan", "iniciativa")

    private fun normalize(text: String): String = buildString {
        for (char in text.lowercase()) {
            append(
                when (char) {
                    'á', 'à', 'ä', 'â' -> 'a'
                    'é', 'è', 'ë', 'ê' -> 'e'
                    'í', 'ì', 'ï', 'î' -> 'i'
                    'ó', 'ò', 'ö', 'ô' -> 'o'
                    'ú', 'ù', 'ü', 'û' -> 'u'
                    else -> char
                },
            )
        }
    }
}
