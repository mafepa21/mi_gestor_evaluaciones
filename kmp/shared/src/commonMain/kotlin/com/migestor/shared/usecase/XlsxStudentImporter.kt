package com.migestor.shared.usecase

data class XlsxImportPreview(
    val className: String?,
    val course: String?,
    val students: List<ParsedStudent>
)

data class ParsedStudent(
    val fullName: String,
    val firstName: String,
    val lastName: String,
    val rowNumber: Int
)

class XlsxStudentImporter {

    /**
     * Parsea el contenido del Excel exportado por el colegio.
     * Formato esperado:
     *   Fila 1: nombre del colegio
     *   Fila 5: "Clase: 1º BACH-A"
     *   Fila 9+: "1. | APELLIDOS NOMBRE"
     */
    fun parse(rows: List<List<String>>): XlsxImportPreview {
        var className: String? = null
        var course: String? = null
        val students = mutableListOf<ParsedStudent>()

        for ((index, row) in rows.withIndex()) {
            val colA = row.getOrNull(0)?.trim() ?: ""
            val colB = row.getOrNull(1)?.trim() ?: ""

            // Detectar metadatos en las primeras 8 filas
            if (index < 8) {
                if (colA.startsWith("Clase:", ignoreCase = true)) {
                    className = colA.removePrefix("Clase:").trim()
                }
                if (colA.startsWith("Curso escolar:", ignoreCase = true)) {
                    course = colA.removePrefix("Curso escolar:").trim()
                }
                continue
            }

            // Detectar filas de alumnos: columna A es "N." y columna B es el nombre
            val isStudentRow = colA.matches(Regex("\\d+\\.?")) && colB.isNotBlank()
            if (!isStudentRow) continue

            val rowNum = colA.trimEnd('.').toIntOrNull() ?: (students.size + 1)
            val parsed = parseFullName(colB, rowNum)
            students.add(parsed)
        }

        return XlsxImportPreview(
            className = className,
            course    = course,
            students  = students
        )
    }

    /**
     * Convierte "GARCÍA LÓPEZ ANTONIO JESÚS" en firstName="Antonio Jesús", lastName="García López"
     * Heurística: los dos primeros tokens son apellidos, el resto nombre.
     * Si solo hay dos tokens: primer token apellido, segundo nombre.
     */
    private fun parseFullName(fullName: String, rowNumber: Int): ParsedStudent {
        val tokens = fullName.trim().split(Regex("\\s+")).filter { it.isNotBlank() }

        val (firstName, lastName) = when {
            tokens.size >= 3 -> {
                val last  = tokens.take(2).joinToString(" ") { it.capitalize() }
                val first = tokens.drop(2).joinToString(" ") { it.capitalize() }
                first to last
            }
            tokens.size == 2 -> {
                tokens[1].capitalize() to tokens[0].capitalize()
            }
            tokens.size == 1 -> {
                tokens[0].capitalize() to ""
            }
            else -> "" to ""
        }

        return ParsedStudent(
            fullName   = fullName.split(" ").joinToString(" ") { it.capitalize() },
            firstName  = firstName,
            lastName   = lastName,
            rowNumber  = rowNumber
        )
    }

    private fun String.capitalize(): String =
        lowercase().replaceFirstChar { it.uppercase() }
}
