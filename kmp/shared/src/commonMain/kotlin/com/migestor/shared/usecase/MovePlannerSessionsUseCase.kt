package com.migestor.shared.usecase

import com.migestor.shared.repository.PlannerRepository

class MovePlannerSessionsUseCase(private val repo: PlannerRepository) {

    /**
     * Desplaza todas las sesiones de [fromWeek]/[fromYear]
     * en [offsetWeeks] semanas hacia adelante (positivo) o atrás (negativo).
     */
    suspend operator fun invoke(
        fromWeek: Int,
        fromYear: Int,
        offsetWeeks: Int
    ) {
        // La llamada suspend está dentro del operador suspend: correcto.
        repo.moveSessionsFromWeek(fromWeek, fromYear, offsetWeeks)
    }
}
