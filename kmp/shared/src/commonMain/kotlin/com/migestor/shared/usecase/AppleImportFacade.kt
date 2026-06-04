package com.migestor.shared.usecase

import com.migestor.shared.viewmodel.RubricUiState

class AppleImportFacade {
    private val studentImporter = XlsxStudentImporter()
    private val rubricImporter = RubricImporter()

    fun previewStudentsFromTsv(text: String): XlsxImportPreview {
        return studentImporter.parse(parseDelimitedText(text))
    }

    fun previewRubricFromTsv(text: String): RubricUiState? {
        return rubricImporter.parse(parseDelimitedText(text))
    }

    private fun parseDelimitedText(text: String): List<List<String>> {
        return text
            .lines()
            .filter { it.isNotBlank() }
            .map { line ->
                line.split('\t').map { it.trim() }
            }
    }
}
