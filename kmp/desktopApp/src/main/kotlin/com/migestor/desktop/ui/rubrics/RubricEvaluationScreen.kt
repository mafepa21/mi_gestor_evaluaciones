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
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.shared.viewmodel.RubricEvaluationViewModel
import com.migestor.shared.domain.*
import com.migestor.desktop.ui.navigation.Navigator
import com.migestor.desktop.ui.components.*

@Composable
fun RubricEvaluationScreen(viewModel: RubricEvaluationViewModel) {
    val state by viewModel.uiState.collectAsState()

    if (state.isLoading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
        }
        return
    }

    if (state.error != null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            OrganicGlassCard(modifier = Modifier.width(400.dp)) {
                Column(Modifier.padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Error, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(64.dp))
                    Spacer(Modifier.height(16.dp))
                    Text(state.error!!, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(24.dp))
                    Button(onClick = { Navigator.goBack() }) {
                        Text("Cerrar")
                    }
                }
            }
        }
        return
    }

    val rubricDetail = state.rubricDetail ?: return

    MeshBackground {
        Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
            // Header (Breadcrumbs + Actions)
            EvaluationTopHeader(
                studentName = state.studentName,
                rubricName = state.rubricName,
                onBack = { Navigator.goBack() }
            )
            
            Spacer(modifier = Modifier.height(24.dp))

            Row(modifier = Modifier.weight(1f)) {
                // Left Side: Criteria List
                Column(modifier = Modifier.weight(1f)) {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        contentPadding = PaddingValues(bottom = 24.dp)
                    ) {
                        items(rubricDetail.criteria) { criterionWithLevels ->
                            GlassCriterionRow(
                                criterion = criterionWithLevels.criterion,
                                levels = criterionWithLevels.levels,
                                selectedLevelId = state.selectedLevels[criterionWithLevels.criterion.id],
                                totalCriteriaCount = rubricDetail.criteria.size,
                                onLevelSelected = { lvlId ->
                                    viewModel.selectLevel(criterionWithLevels.criterion.id, lvlId)
                                }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.width(24.dp))

                // Right Side: Score Panel
                GlassScorePanel(
                    score = state.totalScore,
                    notes = state.notes,
                    onNotesChange = { viewModel.updateNotes(it) },
                    onSave = { viewModel.save { Navigator.goBack() } },
                    isSaving = state.isSaving
                )
            }
        }
    }
}

@Composable
private fun EvaluationTopHeader(
    studentName: String,
    rubricName: String,
    onBack: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(
            onClick = onBack,
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.5f))
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver")
        }
        
        Spacer(Modifier.width(16.dp))
        
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Cuaderno", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(Icons.Default.ChevronRight, null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Evaluación de alumno", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                text = studentName,
                fontSize = 24.sp,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        
        Spacer(Modifier.weight(1f))
        
        Surface(
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
            shape = RoundedCornerShape(20.dp),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.2f))
        ) {
            Text(
                text = rubricName,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp
            )
        }
    }
}

@Composable
private fun GlassCriterionRow(
    criterion: RubricCriterion,
    levels: List<RubricLevel>,
    selectedLevelId: Long?,
    totalCriteriaCount: Int,
    onLevelSelected: (Long) -> Unit
) {
    OrganicGlassCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = criterion.description,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                
                Surface(
                    color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.1f),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text(
                        "Ponderación: ${(100 / (if (totalCriteriaCount > 0) totalCriteriaCount else 1))}%",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.secondary,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            
            Spacer(Modifier.height(20.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                levels.forEach { level ->
                    LevelGlassCard(
                        level = level,
                        isSelected = selectedLevelId == level.id,
                        onClick = { onLevelSelected(level.id) },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun LevelGlassCard(
    level: RubricLevel,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val borderColor = if (isSelected) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.4f)
    val backgroundColor = if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.05f) else Color.White.copy(alpha = 0.6f)
    val elevation = if (isSelected) 8.dp else 2.dp

    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(20.dp),
        color = backgroundColor,
        border = BorderStroke(if (isSelected) 2.dp else 1.dp, borderColor),
        modifier = modifier.heightIn(min = 160.dp),
        shadowElevation = elevation
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                level.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.ExtraBold,
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center
            )
            
            Surface(
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(
                    "${level.order + 1} pts",
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelLarge,
                    color = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Bold
                )
            }

            Spacer(Modifier.height(4.dp))
            
            Text(
                level.description ?: "",
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
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
    notes: String,
    onNotesChange: (String) -> Unit,
    onSave: () -> Unit,
    isSaving: Boolean
) {
    OrganicGlassCard(modifier = Modifier.width(360.dp).fillMaxHeight()) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "Puntuación Final",
                fontSize = 20.sp,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            
            Spacer(Modifier.height(32.dp))
            
            RadialScoreView(score = score)
            
            Spacer(Modifier.height(32.dp))
            
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            
            Spacer(Modifier.height(24.dp))
            
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "Observaciones",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = notes,
                    onValueChange = onNotesChange,
                    modifier = Modifier.fillMaxWidth().height(150.dp),
                    placeholder = { Text("Escribe aquí lo más relevante de la sesión...") },
                    shape = RoundedCornerShape(16.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedContainerColor = Color.White.copy(alpha = 0.3f),
                        focusedContainerColor = Color.White.copy(alpha = 0.5f)
                    )
                )
            }
            
            Spacer(Modifier.weight(1f))
            
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = onSave,
                    enabled = !isSaving,
                    modifier = Modifier.weight(1f).height(56.dp),
                    shape = RoundedCornerShape(16.dp),
                    elevation = ButtonDefaults.buttonElevation(defaultElevation = 4.dp)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(Modifier.size(24.dp), color = Color.White)
                    } else {
                        Icon(Icons.Default.Save, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Guardar", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}
