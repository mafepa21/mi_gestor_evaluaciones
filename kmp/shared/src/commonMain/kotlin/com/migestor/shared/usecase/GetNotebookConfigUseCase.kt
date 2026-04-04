package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookConfig
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.repository.NotebookConfigRepository

class GetNotebookConfigUseCase(
    private val configRepository: NotebookConfigRepository
) {
    suspend fun invoke(classId: Long): NotebookConfig {
        val tabs = configRepository.listTabs(classId)
        val columns = configRepository.listColumns(classId)
        val columnCategories = configRepository.listColumnCategories(classId)
        val workGroups = configRepository.listWorkGroups(classId)
        val workGroupMembers = configRepository.listWorkGroupMembers(classId)
        
        // Si no hay configuración guardada, podríamos devolver una por defecto
        // Pero por ahora simplemente devolvemos lo que haya en la BD
        return NotebookConfig(
            classId = classId,
            tabs = tabs,
            columns = columns,
            columnCategories = columnCategories,
            workGroups = workGroups,
            workGroupMembers = workGroupMembers
        )
    }
}
