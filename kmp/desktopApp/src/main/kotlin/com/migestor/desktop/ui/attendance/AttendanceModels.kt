package com.migestor.desktop.ui.attendance

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.NoteAlt
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

enum class AttendanceStatus(
    val label: String,
    val shortLabel: String,
    val code: String,
    val color: Color,
    val icon: ImageVector
) {
    PRESENT("Presente", "P", "PRESENTE", Color(0xFF4CAF50), Icons.Default.Check),
    ABSENT("Ausente", "A", "AUSENTE", Color(0xFFF44336), Icons.Default.Close),
    LATE("Retraso", "R", "TARDE", Color(0xFFFF9800), Icons.Default.Schedule),
    JUSTIFIED("Justificada", "J", "JUSTIFICADO", Color(0xFF7E8A97), Icons.Default.Info),
    NO_MATERIAL("Sin material", "M", "SIN_MATERIAL", Color(0xFFF57C00), Icons.Default.Inventory2),
    EXEMPT("Exento", "E", "EXENTO", Color(0xFF5C6BC0), Icons.Default.Block),
    OBSERVATION("Observación", "O", "OBSERVACION", Color(0xFF8E24AA), Icons.Default.NoteAlt);

    companion object {
        fun fromCode(code: String): AttendanceStatus =
            values().find { it.code.equals(code, ignoreCase = true) } ?: PRESENT
    }
}
