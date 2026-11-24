package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookEvaluationBlockResult
import com.migestor.shared.domain.NotebookEvaluationExplanation
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.computeAverageExplanation

/**
 * Pestaña de evaluación: una pestaña raíz con pestañas hijas (bloques, una por situación
 * de aprendizaje). Cada nota pesa dentro de su bloque (peso de columna, como siempre) y
 * cada bloque pesa en la evaluación ([NotebookTab.weight]).
 *
 * Nota de evaluación = Σ (peso del bloque × media del bloque) / Σ pesos de los bloques
 * que tienen nota. Un bloque sin notas no cuenta como 0.
 */
object NotebookEvaluation {
    /** Prefijo de las categorías de mentira que agrupan las columnas por bloque en el Resumen. */
    const val BLOCK_CATEGORY_PREFIX = "evalblock:"

    fun isEvaluationTab(tabs: List<NotebookTab>, tabId: String?): Boolean {
        if (tabId == null) return false
        val tab = tabs.firstOrNull { it.id == tabId } ?: return false
        return tab.parentTabId == null && tabs.any { it.parentTabId == tabId }
    }

    /** Evaluación de una pestaña: ella misma si es evaluación, su padre si es un bloque, o `null`. */
    fun evaluationTabId(tabs: List<NotebookTab>, tabId: String?): String? {
        val tab = tabs.firstOrNull { it.id == tabId } ?: return null
        if (isEvaluationTab(tabs, tab.id)) return tab.id
        return tab.parentTabId?.takeIf { parent -> tabs.any { it.id == parent } }
    }

    fun blocks(tabs: List<NotebookTab>, evaluationTabId: String): List<NotebookTab> =
        tabs.filter { it.parentTabId == evaluationTabId }
            .sortedWith(compareBy<NotebookTab> { it.order }.thenBy { it.id })

    /**
     * Peso de cada bloque en porcentaje, repartido para que sumen 100. Un bloque sin peso
     * (`null`) cuenta como uno más a partes iguales. Pesos negativos cuentan como 0.
     * Si todos son 0, todos pesan igual.
     */
    fun weightPercents(blocks: List<NotebookTab>): Map<String, Double> {
        if (blocks.isEmpty()) return emptyMap()
        val equalShare = 100.0 / blocks.size
        val raw = blocks.associate { it.id to (it.weight ?: equalShare).coerceAtLeast(0.0) }
        val total = raw.values.sum()
        if (total <= 0.0) return blocks.associate { it.id to equalShare }
        return raw.mapValues { (_, value) -> value / total * 100.0 }
    }

    /** Columnas que pertenecen a una pestaña (las mismas reglas que la barra de pestañas). */
    fun columnsForTab(columns: List<NotebookColumnDefinition>, tabId: String): List<NotebookColumnDefinition> =
        columns.filter { column ->
            column.visibility == NotebookColumnVisibility.VISIBLE &&
                (column.tabIds.contains(tabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty()))
        }

    /** Columnas que se ven en el Resumen: las propias de la evaluación y las de sus bloques. */
    fun columnsForEvaluation(
        tabs: List<NotebookTab>,
        columns: List<NotebookColumnDefinition>,
        evaluationTabId: String,
    ): List<NotebookColumnDefinition> {
        val familyIds = setOf(evaluationTabId) + blocks(tabs, evaluationTabId).map { it.id }
        return columns.filter { column ->
            column.visibility == NotebookColumnVisibility.VISIBLE && column.tabIds.any { it in familyIds }
        }
    }

    /** Bloque de una columna en una evaluación: el primero de sus `tabIds` que sea bloque. */
    fun blockIdForColumn(column: NotebookColumnDefinition, blockIds: List<String>): String? =
        blockIds.firstOrNull { it in column.tabIds }

    /** Media de una pestaña para un alumno con el motor de siempre (pesos de columna). */
    fun tabAverage(
        row: NotebookRow,
        columns: List<NotebookColumnDefinition>,
        tabId: String,
        numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
    ): Double? = row.computeAverageExplanation(
        columns = columnsForTab(columns, tabId),
        numericDrafts = numericDrafts,
    )?.average

    fun explain(
        row: NotebookRow,
        tabs: List<NotebookTab>,
        columns: List<NotebookColumnDefinition>,
        evaluationTabId: String,
        numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
    ): NotebookEvaluationExplanation? {
        val blocks = blocks(tabs, evaluationTabId)
        if (blocks.isEmpty()) return null
        val percents = weightPercents(blocks)
        val results = blocks.map { block ->
            val explanation = row.computeAverageExplanation(
                columns = columnsForTab(columns, block.id),
                numericDrafts = numericDrafts,
            )
            NotebookEvaluationBlockResult(
                tabId = block.id,
                title = block.title,
                weightPercent = percents[block.id] ?: 0.0,
                average = explanation?.average,
                includedColumnCount = explanation?.included?.size ?: 0,
            )
        }
        val withGrade = results.filter { it.average != null && it.weightPercent > 0.0 }
        val totalWeight = withGrade.sumOf { it.weightPercent }
        val average = if (totalWeight > 0.0) {
            withGrade.sumOf { it.weightPercent * (it.average ?: 0.0) } / totalWeight
        } else {
            null
        }
        return NotebookEvaluationExplanation(studentId = row.student.id, average = average, blocks = results)
    }

    /**
     * Categorías de mentira para agrupar el Resumen por bloque («Hockey · 60 %»). No se
     * guardan: el id lleva [BLOCK_CATEGORY_PREFIX] y el id del bloque.
     */
    fun blockCategories(classId: Long, tabs: List<NotebookTab>, evaluationTabId: String): List<NotebookColumnCategory> {
        val blocks = blocks(tabs, evaluationTabId)
        val percents = weightPercents(blocks)
        return blocks.mapIndexed { index, block ->
            NotebookColumnCategory(
                id = BLOCK_CATEGORY_PREFIX + block.id,
                classId = classId,
                tabId = evaluationTabId,
                name = "${block.title} · ${formatPercent(percents[block.id] ?: 0.0)}",
                order = index,
            )
        }
    }

    /** La misma explicación de columnas con otra media (la nota de evaluación). Para Swift. */
    fun withAverage(
        explanation: com.migestor.shared.domain.NotebookAverageExplanation,
        average: Double?,
    ): com.migestor.shared.domain.NotebookAverageExplanation = explanation.copy(average = average)

    fun blockIdFromCategoryId(categoryId: String): String? =
        categoryId.takeIf { it.startsWith(BLOCK_CATEGORY_PREFIX) }?.removePrefix(BLOCK_CATEGORY_PREFIX)

    /** «60 %», «33,3 %». */
    fun formatPercent(value: Double): String {
        val rounded = kotlin.math.round(value * 10.0) / 10.0
        val text = if (rounded % 1.0 == 0.0) rounded.toLong().toString() else rounded.toString().replace('.', ',')
        return "$text %"
    }
}
