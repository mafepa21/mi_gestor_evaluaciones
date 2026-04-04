package com.migestor.desktop.ui.notebook

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.desktop.ui.theme.*

@Composable
fun CellInputOverlay(
    type: NotebookColumnType,
    initialValue: String,
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    Popup(
        alignment = Alignment.Center,
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.PopupProperties(
            focusable = true,
            dismissOnClickOutside = true,
            dismissOnBackPress = true
        )
    ) {
        Surface(
            shape = RoundedCornerShape(NotebookVisualTokens.dialogCorner),
            tonalElevation = 8.dp,
            shadowElevation = 8.dp,
            modifier = Modifier
                .width(280.dp)
                .padding(8.dp)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f), RoundedCornerShape(NotebookVisualTokens.dialogCorner))
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = when(type) {
                        NotebookColumnType.NUMERIC -> "Entrada Numérica"
                        NotebookColumnType.ICON -> "Seleccionar Icono/Estado"
                        NotebookColumnType.ORDINAL -> "Escala Ordinal"
                        NotebookColumnType.ATTENDANCE -> "Asistencia"
                        NotebookColumnType.CHECK -> "Seguimiento / Switch"
                        else -> "Editar Celda"
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold
                )

                when (type) {
                    NotebookColumnType.NUMERIC -> NumericInputKeyboard(initialValue, onValueChange, onDismiss)
                    NotebookColumnType.ICON -> IconInputPicker(onValueChange, onDismiss)
                    NotebookColumnType.ORDINAL -> OrdinalInputPicker(onValueChange, onDismiss)
                    NotebookColumnType.ATTENDANCE -> AttendanceInputPicker(initialValue, onValueChange, onDismiss)
                    NotebookColumnType.CHECK -> CheckInputPicker(initialValue, onValueChange, onDismiss)
                    else -> TextInputArea(initialValue, onValueChange, onDismiss)
                }
            }
        }
    }
}

@Composable
private fun NumericInputKeyboard(
    initialValue: String,
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var text by remember { mutableStateOf(initialValue) }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
            textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        )

        // Quick Scores
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("0", "5", "10").forEach { score ->
                InputChip(
                    onClick = { text = score; onValueChange(score); onDismiss() },
                    label = { Text(score) },
                    selected = text == score,
                    shape = RoundedCornerShape(NotebookVisualTokens.chipCorner)
                )
            }
        }

        // Keypad (abbreviated for desktop, but useful for quick clicks)
        val keys = listOf(
            listOf("7", "8", "9"),
            listOf("4", "5", "6"),
            listOf("1", "2", "3"),
            listOf("0", ".", "C")
        )

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            keys.forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    row.forEach { key ->
                        Surface(
                            onClick = {
                                when (key) {
                                    "C" -> text = ""
                                    else -> text += key
                                }
                            },
                            modifier = Modifier.weight(1f).height(40.dp),
                            shape = RoundedCornerShape(NotebookVisualTokens.chipCorner),
                            color = MaterialTheme.colorScheme.surfaceVariant
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Text(key, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }
            }
        }

        Button(
            onClick = { onValueChange(text); onDismiss() },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
        ) {
            Text("Aceptar")
        }
    }
}

@Composable
private fun IconInputPicker(
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val states = listOf(
        "🟢" to "Bien / Completado",
        "🟡" to "En proceso / Duda",
        "🔴" to "Pendiente / Error",
        "⭐" to "Destacado",
        "❓" to "Revisar",
        "✅" to "Validado"
    )

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        states.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (icon, label) ->
                    Surface(
                        onClick = { onValueChange(icon); onDismiss() },
                        modifier = Modifier.weight(1f).aspectRatio(1f),
                        shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                        color = MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                            modifier = Modifier.padding(4.dp)
                        ) {
                            Text(icon, fontSize = 24.sp)
                            Text(label.substringBefore(" "), fontSize = 10.sp, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OrdinalInputPicker(
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val levels = listOf("A", "B", "C", "D", "F")
    
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            levels.forEach { level ->
                Surface(
                    onClick = { onValueChange(level); onDismiss() },
                    modifier = Modifier.weight(1f).height(50.dp),
                    shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                    color = when(level) {
                        "A" -> Color(0xFF4CAF50).copy(alpha = 0.2f)
                        "B" -> Color(0xFF8BC34A).copy(alpha = 0.2f)
                        "C" -> Color(0xFFFFEB3B).copy(alpha = 0.2f)
                        "D" -> Color(0xFFFF9800).copy(alpha = 0.2f)
                        else -> Color(0xFFF44336).copy(alpha = 0.2f)
                    },
                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(level, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp)
                    }
                }
            }
        }
        
        Text("Nota: Puedes configurar estos valores en los ajustes.", 
            style = MaterialTheme.typography.labelSmall, 
            color = MaterialTheme.colorScheme.outline)
    }
}

@Composable
private fun TextInputArea(
    initialValue: String,
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var text by remember { mutableStateOf(initialValue) }
    
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.fillMaxWidth().height(120.dp),
            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
            placeholder = { Text("Añadir comentario...") }
        )
        
        Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
            TextButton(onClick = onDismiss) { Text("Cancelar") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = { onValueChange(text); onDismiss() }, shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)) {
                Text("Guardar")
            }
        }
    }
}

@Composable
private fun AttendanceInputPicker(
    initialValue: String,
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val options = listOf(
        Triple("P", "Presente", "✅"),
        Triple("A", "Ausente", "❌"),
        Triple("R", "Retraso", "⏰"),
        Triple("J", "Justificado", "📋")
    )

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (code, label, emoji) ->
                    Surface(
                        onClick = { onValueChange(code); onDismiss() },
                        modifier = Modifier.weight(1f).height(60.dp),
                        shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                        color = if (initialValue == code) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                            modifier = Modifier.padding(4.dp)
                        ) {
                            Text(emoji, fontSize = 20.sp)
                            Spacer(Modifier.width(8.dp))
                            Text(label, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }
        }
        
        if (initialValue.isNotEmpty()) {
            TextButton(
                onClick = { onValueChange(""); onDismiss() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Limpiar", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun CheckInputPicker(
    initialValue: String,
    onValueChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val isChecked = initialValue.toBoolean()

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Switch(
            checked = isChecked,
            onCheckedChange = { onValueChange(it.toString()); onDismiss() },
            thumbContent = {
                if (isChecked) {
                    Icon(Icons.Default.Check, null, modifier = Modifier.size(SwitchDefaults.IconSize))
                }
            }
        )
        
        Text(
            if (isChecked) "Activado" else "Desactivado",
            style = MaterialTheme.typography.bodyMedium
        )

        Button(
            onClick = onDismiss,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
        ) {
            Text("Cerrar")
        }
    }
}
