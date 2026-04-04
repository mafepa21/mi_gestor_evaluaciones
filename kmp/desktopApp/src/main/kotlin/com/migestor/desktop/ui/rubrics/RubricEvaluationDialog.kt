package com.migestor.desktop.ui.rubrics

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.migestor.shared.domain.*
import com.migestor.shared.viewmodel.*
import com.migestor.desktop.ui.components.*

@Composable
fun RubricEvaluationDialog(
    viewModel: RubricEvaluationViewModel,
    onDismiss: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.3f))
                .clickable(enabled = false) {},
            contentAlignment = Alignment.Center
        ) {
            OrganicGlassCard(
                modifier = Modifier
                    .width(1100.dp)
                    .height(820.dp) // Un poco más alto para notas
                    .padding(16.dp),
                elevation = 16.dp
            ) {
                MeshBackground {
                    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
                        // Header
                        EvaluationDialogHeader(
                            studentName = uiState.studentName,
                            rubricName = uiState.rubricName,
                            onClose = onDismiss
                        )
                        
                        Spacer(modifier = Modifier.height(24.dp))

                        if (uiState.isLoading) {
                            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator()
                            }
                        } else {
                            Row(modifier = Modifier.weight(1f)) {
                                // Left side: Criteria
                                Column(modifier = Modifier.weight(1.2f)) {
                                    LazyColumn(
                                        modifier = Modifier.fillMaxSize(),
                                        verticalArrangement = Arrangement.spacedBy(16.dp),
                                        contentPadding = PaddingValues(bottom = 24.dp)
                                    ) {
                                        val detail = uiState.rubricDetail
                                        if (detail != null) {
                                            items(detail.criteria) { criterionWithLevels ->
                                                CriterionEvaluationCard(
                                                    criterion = criterionWithLevels.criterion,
                                                    levels = criterionWithLevels.levels,
                                                    selectedLevelId = uiState.selectedLevels[criterionWithLevels.criterion.id],
                                                    totalCriteriaCount = detail.criteria.size,
                                                    onLevelSelected = { lvlId ->
                                                        viewModel.selectLevel(criterionWithLevels.criterion.id, lvlId)
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }

                                Spacer(modifier = Modifier.width(24.dp))

                                // Right side: Score & States
                                Column(modifier = Modifier.weight(0.8f)) {
                                    GlassScorePanel(
                                        score = uiState.totalScore,
                                        isSaving = uiState.isSaving,
                                        isSaveSuccessful = uiState.isSaveSuccessful,
                                        error = uiState.error,
                                        notes = uiState.notes,
                                        onNotesChange = { viewModel.updateNotes(it) },
                                        onSave = { viewModel.save {} },
                                        onClose = onDismiss
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EvaluationDialogHeader(
    studentName: String,
    rubricName: String,
    onClose: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column {
            Text(
                text = studentName,
                fontSize = 24.sp,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Surface(
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
                shape = RoundedCornerShape(8.dp)
            ) {
                Text(
                    text = rubricName,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp
                )
            }
        }
        
        Spacer(Modifier.weight(1f))
        
        IconButton(
            onClick = onClose,
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.5f))
        ) {
            Icon(Icons.Default.Close, "Cerrar")
        }
    }
}

@Composable
private fun CriterionEvaluationCard(
    criterion: RubricCriterion,
    levels: List<RubricLevel>,
    selectedLevelId: Long?,
    totalCriteriaCount: Int,
    onLevelSelected: (Long) -> Unit
) {
    OrganicGlassCard(
        modifier = Modifier.fillMaxWidth(),
        backgroundColor = Color.White.copy(alpha = 0.6f),
        elevation = 2.dp
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = criterion.description,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                
                Surface(
                    color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.1f),
                    shape = RoundedCornerShape(6.dp)
                ) {
                    Text(
                        "${(100 / (if (totalCriteriaCount > 0) totalCriteriaCount else 1))}%",
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            
            Spacer(Modifier.height(16.dp))

            // Mejorado: Scroll horizontal para niveles si hay muchos (Matrix-like feel but Cards)
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                levels.sortedBy { it.order }.forEach { level ->
                    LevelGlassOption(
                        level = level,
                        isSelected = selectedLevelId == level.id,
                        onClick = { onLevelSelected(level.id) },
                        modifier = Modifier.width(180.dp) // Ancho fijo para facilitar scroll consistente
                    )
                }
            }
        }
    }
}

@Composable
private fun LevelGlassOption(
    level: RubricLevel,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val borderColor = if (isSelected) MaterialTheme.colorScheme.primary else Color.Transparent
    val backgroundColor = if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else Color.White.copy(alpha = 0.4f)

    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(16.dp),
        color = backgroundColor,
        border = if (isSelected) BorderStroke(2.dp, borderColor) else null,
        modifier = modifier.heightIn(min = 140.dp)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                level.name,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            
            Text(
                "${level.order + 1} pts",
                style = MaterialTheme.typography.labelSmall,
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.ExtraBold
            )

            Spacer(Modifier.height(4.dp))
            
            Text(
                level.description ?: "",
                style = MaterialTheme.typography.bodySmall,
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                lineHeight = 14.sp,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun GlassScorePanel(
    score: Double,
    isSaving: Boolean,
    isSaveSuccessful: Boolean,
    error: String?,
    notes: String,
    onNotesChange: (String) -> Unit,
    onSave: () -> Unit,
    onClose: () -> Unit
) {
    OrganicGlassCard(
        modifier = Modifier.fillMaxWidth().fillMaxHeight(),
        backgroundColor = Color.White.copy(alpha = 0.7f)
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "Puntuación Final",
                fontSize = 18.sp,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            
            Spacer(Modifier.height(24.dp))
            
            RadialScoreView(score = score, size = 180.dp, strokeWidth = 14.dp)
            
            Spacer(Modifier.height(32.dp))

            // Campo de Notas / Evidencia
            OutlinedTextField(
                value = notes,
                onValueChange = onNotesChange,
                modifier = Modifier.fillMaxWidth().height(120.dp),
                label = { Text("Notas / Evidencias") },
                placeholder = { Text("Escribe anotaciones sobre la evaluación...") },
                shape = RoundedCornerShape(12.dp),
                textStyle = MaterialTheme.typography.bodySmall
            )

            Spacer(Modifier.weight(1f))

            // Indicador de Estado de Guardado
            AnimatedVisibility(visible = isSaving || isSaveSuccessful || error != null) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(bottom = 16.dp)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Guardando...", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    } else if (isSaveSuccessful) {
                        Icon(Icons.Default.CheckCircle, null, Modifier.size(16.dp), tint = Color(0xFF4CAF50))
                        Spacer(Modifier.width(8.dp))
                        Text("Guardado", style = MaterialTheme.typography.labelSmall, color = Color(0xFF4CAF50))
                    } else if (error != null) {
                        Icon(Icons.Default.Error, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(8.dp))
                        Text(error, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
                    }
                }
            }
            
            Button(
                onClick = onSave,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = !isSaving,
                shape = RoundedCornerShape(16.dp),
                elevation = ButtonDefaults.buttonElevation(defaultElevation = 8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary
                )
            ) {
                if (isSaving) {
                    CircularProgressIndicator(Modifier.size(24.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp)
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Save, null, Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Guardar Evaluación", fontWeight = FontWeight.Bold)
                    }
                }
            }

            Spacer(Modifier.height(12.dp))
            
            Button(
                onClick = onClose,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                shape = RoundedCornerShape(16.dp),
                elevation = ButtonDefaults.buttonElevation(defaultElevation = 4.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                )
            ) {
                Text("Cerrar", fontWeight = FontWeight.Bold)
            }
        }
    }
}
