package com.migestor.shared.notebook

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.formula.FormulaEvaluator

data class NotebookFormulaValidationResult(
    val isValid: Boolean,
    val errors: List<NotebookFormulaError>,
    val referencedColumnIds: List<String>,
    val previewValue: Double?,
)

data class NotebookFormulaError(
    val kind: NotebookFormulaErrorKind,
    val message: String,
    val token: String? = null,
)

enum class NotebookFormulaErrorKind {
    SYNTAX,
    UNKNOWN_COLUMN,
    CIRCULAR_REFERENCE,
    UNSUPPORTED_FUNCTION,
    DIVISION_BY_ZERO,
    EMPTY_FORMULA,
    NON_NUMERIC_RESULT,
}

private val referenceRegex = Regex("""\[([^\]]+)]""")
private val functionRegex = Regex("""\b([A-Za-z_][A-Za-z0-9_]*)\s*\(""")
private val allowedFunctions = setOf("SUMA", "PROMEDIO", "MIN", "MAX", "REDONDEAR", "SI")
private val evaluator = FormulaEvaluator()

fun validateFormula(
    formula: String,
    targetColumnId: String,
    availableColumns: List<NotebookColumnDefinition>,
    formulaColumns: List<NotebookColumnDefinition>,
): NotebookFormulaValidationResult {
    val trimmed = formula.trim().trimStart('=').trim()
    if (trimmed.isEmpty()) {
        return NotebookFormulaValidationResult(
            isValid = false,
            errors = listOf(NotebookFormulaError(NotebookFormulaErrorKind.EMPTY_FORMULA, "La fórmula no puede estar vacía.")),
            referencedColumnIds = emptyList(),
            previewValue = null,
        )
    }

    val errors = mutableListOf<NotebookFormulaError>()
    val references = referenceRegex.findAll(trimmed)
        .map { it.groupValues[1].trim() }
        .filter { it.isNotEmpty() }
        .distinct()
        .toList()

    val availableIds = availableColumns.map { it.id }.toSet()
    references.filterNot { it in availableIds }.forEach { columnId ->
        errors += NotebookFormulaError(
            kind = NotebookFormulaErrorKind.UNKNOWN_COLUMN,
            message = "La columna [$columnId] no existe.",
            token = columnId,
        )
    }

    unsupportedFunctions(trimmed).forEach { function ->
        errors += NotebookFormulaError(
            kind = NotebookFormulaErrorKind.UNSUPPORTED_FUNCTION,
            message = "Función no soportada: $function.",
            token = function,
        )
    }

    if (references.contains(targetColumnId) || hasCircularReference(targetColumnId, references, formulaColumns)) {
        errors += NotebookFormulaError(
            kind = NotebookFormulaErrorKind.CIRCULAR_REFERENCE,
            message = "La fórmula crea una referencia circular.",
            token = targetColumnId,
        )
    }

    val normalized = normalizeReferences(trimmed)
    val variables = references.flatMap { id ->
        listOf(id to 1.0, safeIdentifier(id) to 1.0)
    }.toMap()

    val preview = if (errors.none { it.kind == NotebookFormulaErrorKind.UNKNOWN_COLUMN || it.kind == NotebookFormulaErrorKind.UNSUPPORTED_FUNCTION || it.kind == NotebookFormulaErrorKind.CIRCULAR_REFERENCE }) {
        runCatching { evaluator.evaluate(normalized, variables) }
            .fold(
                onSuccess = { value ->
                    if (value.isFinite()) {
                        value
                    } else {
                        errors += NotebookFormulaError(
                            kind = NotebookFormulaErrorKind.NON_NUMERIC_RESULT,
                            message = "La fórmula no devuelve un número válido.",
                        )
                        null
                    }
                },
                onFailure = { throwable ->
                    errors += NotebookFormulaError(
                        kind = if (throwable.message?.contains("División por cero", ignoreCase = true) == true) {
                            NotebookFormulaErrorKind.DIVISION_BY_ZERO
                        } else {
                            NotebookFormulaErrorKind.SYNTAX
                        },
                        message = throwable.message ?: "La fórmula tiene una sintaxis no válida.",
                    )
                    null
                }
            )
    } else {
        null
    }

    return NotebookFormulaValidationResult(
        isValid = errors.isEmpty(),
        errors = errors,
        referencedColumnIds = references,
        previewValue = preview,
    )
}

private fun unsupportedFunctions(formula: String): List<String> {
    val withoutReferences = referenceRegex.replace(formula, "1")
    return functionRegex.findAll(withoutReferences)
        .map { it.groupValues[1] }
        .filterNot { it.uppercase() in allowedFunctions }
        .distinct()
        .toList()
}

private fun hasCircularReference(
    targetColumnId: String,
    directReferences: List<String>,
    formulaColumns: List<NotebookColumnDefinition>,
): Boolean {
    val graph = formulaColumns
        .filter { it.type == NotebookColumnType.CALCULATED && !it.formula.isNullOrBlank() }
        .associate { column ->
            column.id to referenceRegex.findAll(column.formula.orEmpty()).map { it.groupValues[1].trim() }.toList()
        }

    fun visitsTarget(columnId: String, seen: Set<String>): Boolean {
        if (columnId == targetColumnId) return true
        if (columnId in seen) return false
        return graph[columnId].orEmpty().any { next -> visitsTarget(next, seen + columnId) }
    }

    return directReferences.any { visitsTarget(it, emptySet()) }
}

private fun normalizeReferences(formula: String): String {
    return referenceRegex.replace(formula) { match -> safeIdentifier(match.groupValues[1].trim()) }
}

private fun safeIdentifier(raw: String): String {
    val identifier = raw.map { char ->
        if (char.isLetterOrDigit() || char == '_') char else '_'
    }.joinToString("")
    return if (identifier.firstOrNull()?.isDigit() == true) "_$identifier" else identifier
}
