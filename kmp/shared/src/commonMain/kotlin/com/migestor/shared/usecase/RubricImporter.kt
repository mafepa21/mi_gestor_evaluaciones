package com.migestor.shared.usecase

import com.migestor.shared.viewmodel.RubricUiState
import com.migestor.shared.viewmodel.RubricCriterionState
import com.migestor.shared.viewmodel.RubricLevelState

class RubricImporter {
    /**
     * Parsea una cuadrícula de strings (de un CSV o Excel)
     * Formato esperado:
     * Col 0: "Criterio" o vacío (cabecera)
     * Col 1 en adelante: Nombre del nivel + nota en paréntesis -> "Excelente (10)"
     * Filas siguientes: Col 0 = nombre criterio, Col 1 en adelante = descripciones
     */
    fun parse(rows: List<List<String>>): RubricUiState? {
        if (rows.isEmpty()) return null

        val headers = rows.first()
        if (headers.size < 2) return null

        // 1. Extraer niveles de la primera fila
        val levelDefinitions = headers.drop(1).mapIndexed { index, header ->
            val match = Regex("""(.*)\((.*)\)""").find(header)
            val name = match?.groupValues?.get(1)?.trim() ?: header.trim()
            val pointsStr = match?.groupValues?.get(2)?.trim() ?: "0"
            
            // Manejar rangos (usamos el valor máximo del rango por simplicidad)
            val points = if (pointsStr.contains("-")) {
                pointsStr.split("-").last().trim().toIntOrNull() ?: 0
            } else {
                pointsStr.toIntOrNull() ?: 0
            }

            RubricLevelState(
                name = name,
                points = points,
                order = index,
                uid = "imported_level_${index}"
            )
        }

        // 2. Extraer criterios y descripciones de las filas restantes
        val criteria = rows.drop(1).filter { it.isNotEmpty() && it[0].isNotBlank() }.mapIndexed { cIdx, row ->
            val description = row[0].trim()
            val levelDescriptions = mutableMapOf<String, String>()
            
            row.drop(1).forEachIndexed { lIdx, cell ->
                if (lIdx < levelDefinitions.size) {
                    val levelUid = levelDefinitions[lIdx].uid
                    levelDescriptions[levelUid] = cell.trim()
                }
            }

            RubricCriterionState(
                description = description,
                weight = 0.0, // El usuario deberá ajustarlo
                order = cIdx,
                levelDescriptions = levelDescriptions
            )
        }

        return RubricUiState(
            rubricName = "Rúbrica Importada",
            levels = levelDefinitions,
            criteria = criteria,
            totalWeight = 0.0
        )
    }
}
