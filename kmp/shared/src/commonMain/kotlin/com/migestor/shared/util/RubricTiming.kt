package com.migestor.shared.util

import com.migestor.shared.domain.RubricLevel

/**
 * Cortes de cronómetro de un criterio de rúbrica: el tiempo medido pone el nivel.
 *
 * Se guarda como texto en `rubric_criteria.timing_config`:
 * `"lower;10.0;12.0;15.0"` = menos es mejor; por debajo de 10 s nivel más alto,
 * de 10 a 12 el siguiente, de 12 a 15 el siguiente y por encima de 15 el más bajo.
 * `"higher;…"` invierte el sentido (más es mejor). Los cortes van siempre de menor a mayor.
 */
data class RubricTiming(
    val lowerIsBetter: Boolean,
    val cuts: List<Double>,
) {
    /** Puesto del nivel desde abajo: 0 = el de menos puntos, `cuts.size` = el de más. */
    fun rankFor(value: Double): Int {
        val above = cuts.count { value >= it }
        return if (lowerIsBetter) cuts.size - above else above
    }

    /** Nivel de la rúbrica que corresponde al tiempo, ordenando los niveles por puntos. */
    fun levelFor(value: Double, levels: List<RubricLevel>): RubricLevel? {
        if (levels.size != cuts.size + 1) return null
        return levels.sortedWith(compareBy({ it.points }, { it.order }))[rankFor(value)]
    }

    fun serialize(): String =
        (listOf(if (lowerIsBetter) "lower" else "higher") + cuts.map { it.toString() }).joinToString(";")

    companion object {
        fun parse(raw: String?): RubricTiming? {
            val parts = raw?.split(";")?.map { it.trim() } ?: return null
            val lowerIsBetter = when (parts.firstOrNull()) {
                "lower" -> true
                "higher" -> false
                else -> return null
            }
            val cuts = parts.drop(1).map { it.replace(',', '.').toDoubleOrNull() ?: return null }
            if (cuts.isEmpty() || cuts.zipWithNext().any { (a, b) -> a >= b }) return null
            return RubricTiming(lowerIsBetter, cuts)
        }
    }
}
