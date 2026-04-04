package com.migestor.desktop.ui.rubrics

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.migestor.shared.viewmodel.RubricsViewModel

@Composable
fun AssignRubricToTabDialog(viewModel: RubricsViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val state = uiState.assignDialogState ?: return

    Dialog(onDismissRequest = { viewModel.dismissAssignDialog() }) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            tonalElevation = 6.dp,
            modifier = Modifier.width(480.dp)
        ) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                // Header
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Output, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(12.dp))
                    Text(
                        "Asignar rúbrica a Cuaderno", 
                        style = MaterialTheme.typography.titleLarge, 
                        fontWeight = FontWeight.Bold
                    )
                }

                Text(
                    "Rúbrica: ${state.rubricName}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))

                // Step 1: Select Class
                Text("1. Selecciona el curso", style = MaterialTheme.typography.labelLarge)
                LazyColumn(Modifier.heightIn(max = 120.dp)) {
                    items(uiState.allClasses) { schoolClass ->
                        ListItem(
                            headlineContent = { Text(schoolClass.name) },
                            leadingContent = {
                                RadioButton(
                                    selected = state.selectedClassId == schoolClass.id,
                                    onClick = { viewModel.onAssignClassSelected(schoolClass.id) }
                                )
                            },
                            modifier = Modifier.clickable { viewModel.onAssignClassSelected(schoolClass.id) }
                        )
                    }
                }

                if (state.selectedClassId != null) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    // Step 2: Select Tab
                    Text("2. Selecciona la pestaña (o crea una nueva)", style = MaterialTheme.typography.labelLarge)
                    
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Checkbox(
                            checked = state.createNewTab,
                            onCheckedChange = { viewModel.onToggleCreateNewTab(it) }
                        )
                        Text("Crear nueva pestaña", style = MaterialTheme.typography.bodyMedium)
                    }

                    if (state.createNewTab) {
                        OutlinedTextField(
                            value = state.newTabName,
                            onValueChange = { viewModel.onNewTabNameChanged(it) },
                            label = { Text("Nombre de la nueva pestaña") },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp)
                        )
                    } else if (state.availableTabs.isNotEmpty()) {
                        LazyColumn(Modifier.heightIn(max = 120.dp)) {
                            items(state.availableTabs) { tabName ->
                                ListItem(
                                    headlineContent = { Text(tabName) },
                                    leadingContent = {
                                        RadioButton(
                                            selected = state.selectedTab == tabName && !state.createNewTab,
                                            onClick = { viewModel.onAssignTabSelected(tabName) }
                                        )
                                    },
                                    modifier = Modifier.clickable { viewModel.onAssignTabSelected(tabName) }
                                )
                            }
                        }
                    } else {
                        Text("No hay pestañas creadas. Por favor, crea una nueva.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    }
                }

                Spacer(Modifier.height(8.dp))

                // Footer Actions
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = { viewModel.dismissAssignDialog() }) {
                        Text("Cancelar")
                    }
                    Spacer(Modifier.width(12.dp))
                    Button(
                        onClick = { viewModel.confirmAssignRubric() },
                        enabled = state.selectedClassId != null && 
                                 ((state.createNewTab && state.newTabName.isNotBlank()) || 
                                  (!state.createNewTab && state.selectedTab != null)),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Confirmar asignación")
                    }
                }
            }
        }
    }
}
