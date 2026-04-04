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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.shared.viewmodel.RubricBulkEvaluationViewModel
import com.migestor.shared.domain.*
import com.migestor.desktop.ui.navigation.Navigator
import com.migestor.desktop.ui.components.*

import com.migestor.desktop.ui.planner.hexToColor

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun RubricBulkEvaluationScreen(viewModel: RubricBulkEvaluationViewModel) {
    val state by viewModel.uiState.collectAsState()

    if (state.isLoading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = EvaluationDesign.accent)
        }
        return
    }

    if (state.error != null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            OrganicGlassCard(modifier = Modifier.width(400.dp)) {
                Column(Modifier.padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Error, null, tint = EvaluationDesign.danger, modifier = Modifier.size(64.dp))
                    Spacer(Modifier.height(16.dp))
                    Text(state.error!!, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(24.dp))
                    Button(onClick = { Navigator.goBack() }, colors = ButtonDefaults.buttonColors(containerColor = EvaluationDesign.accent)) {
                        Text("Volver")
                    }
                }
            }
        }
        return
    }

    val rubricDetail = state.rubricDetail ?: return

    MeshBackground {
        Column(modifier = Modifier.fillMaxSize().padding(EvaluationDesign.screenPadding)) {
            BulkEvaluationHeader(
                rubricName = rubricDetail.rubric.name,
                className = "Evaluación Masiva",
                isSaving = state.isSaving,
                onSave = { viewModel.saveAll() },
                onBack = { Navigator.goBack() }
            )

            Spacer(modifier = Modifier.height(EvaluationDesign.sectionSpacing))

            Row(modifier = Modifier.weight(1f)) {
                // Main Evaluation Card
                OrganicGlassCard(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    backgroundColor = Color.White.copy(alpha = 0.92f),
                    cornerRadius = EvaluationDesign.cardRadius
                ) {
                    Column(modifier = Modifier.padding(24.dp)) {
                        // Stats Chips
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(EvaluationDesign.itemSpacing)) {
                            EvaluationChip(
                                label = "${state.students.count()} alumnos",
                                icon = Icons.Default.People
                            )
                            EvaluationChip(
                                label = "${rubricDetail.criteria.count()} criterios",
                                icon = Icons.Default.Checklist
                            )
                            if (state.injuredStudents.isNotEmpty()) {
                                EvaluationChip(
                                    label = "${state.injuredStudents.count()} lesionados",
                                    icon = Icons.Default.MedicalServices,
                                    tint = EvaluationDesign.danger,
                                    isDestructive = true
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(24.dp))

                        // Matrix with Sticky Header
                        Box(modifier = Modifier.fillMaxSize()) {
                            val horizontalScrollState = rememberScrollState()
                            
                            Column(modifier = Modifier.fillMaxSize().horizontalScroll(horizontalScrollState)) {
                                MatrixHeaderRow(rubricDetail.criteria)
                                
                                Spacer(modifier = Modifier.height(12.dp))
                                
                                LazyColumn(
                                    modifier = Modifier.fillMaxSize(),
                                    verticalArrangement = Arrangement.spacedBy(EvaluationDesign.itemSpacing),
                                    contentPadding = PaddingValues(bottom = 24.dp, end = 4.dp)
                                ) {
                                    state.groupedStudents.forEach { groupSection ->
                                        val group = groupSection.group
                                        if (!groupSection.isUngrouped && group != null) {
                                            stickyHeader(key = "group_${group.id}") {
                                                GroupHeader(group.name)
                                            }
                                        } else if (state.groupedStudents.size > 1) {
                                            stickyHeader(key = "group_ungrouped") {
                                                GroupHeader("Sin Grupo")
                                            }
                                        }

                                        items(groupSection.students, key = { it.id }) { student ->
                                            StudentEvaluationRow(
                                                student = student,
                                                criteria = rubricDetail.criteria,
                                                selectedLevels = state.assessments[student.id] ?: emptyMap(),
                                                score = state.scores[student.id],
                                                onLevelSelected = { critId, lvlId ->
                                                    viewModel.selectLevel(student.id, critId, lvlId)
                                                },
                                                onCopy = { viewModel.copyAssessment(student.id) },
                                                onPaste = { viewModel.pasteAssessment(student.id) },
                                                onToggleInjured = { viewModel.toggleInjuredStatus(student.id) },
                                                isPasteEnabled = state.copiedAssessment != null
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.width(EvaluationDesign.sectionSpacing))

                // Sidebar
                InjuredSidebar(state.injuredStudents)
            }
        }
    }
}

@Composable
private fun GroupHeader(name: String) {
    Surface(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        color = Color.White.copy(alpha = 0.95f),
        shape = RoundedCornerShape(8.dp),
        shadowElevation = 2.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.Groups,
                null,
                modifier = Modifier.size(16.dp),
                tint = EvaluationDesign.accent
            )
            Spacer(Modifier.width(8.dp))
            Text(
                text = name.uppercase(),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Black,
                color = EvaluationDesign.primary,
                letterSpacing = 1.sp
            )
        }
    }
}

@Composable
private fun BulkEvaluationHeader(
    rubricName: String,
    className: String,
    isSaving: Boolean,
    onSave: () -> Unit,
    onBack: () -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
        IconButton(
            onClick = onBack,
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.5f))
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver", tint = EvaluationDesign.primary.copy(alpha = 0.8f))
        }

        Spacer(Modifier.width(24.dp))

        Column {
            Text(
                "Pulsar para volver",
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = EvaluationDesign.secondary.copy(alpha = 0.7f),
                letterSpacing = 0.5.sp
            )
            Text(
                text = className,
                fontSize = 28.sp,
                fontWeight = FontWeight.Black,
                color = EvaluationDesign.primary
            )
            Text(
                text = rubricName,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = EvaluationDesign.secondary
            )
        }

        Spacer(Modifier.weight(1f))

        VStack(alignment = Alignment.End, spacing = 4.dp) {
            Button(
                onClick = onSave,
                enabled = !isSaving,
                colors = ButtonDefaults.buttonColors(containerColor = EvaluationDesign.accent),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.width(180.dp).height(48.dp),
                elevation = ButtonDefaults.buttonElevation(defaultElevation = 2.dp)
            ) {
                if (isSaving) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
                } else {
                    Icon(Icons.Default.Save, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Guardar Todo", fontWeight = FontWeight.Bold)
                }
            }
            Text(
                text = if (isSaving) "Guardando cambios..." else "Auto-guardado activo",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = if (isSaving) EvaluationDesign.accent else EvaluationDesign.secondary.copy(alpha = 0.6f)
            )
        }
    }
}

@Composable
private fun MatrixHeaderRow(criteria: List<RubricCriterionWithLevels>) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "ESTUDIANTE",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Black,
            color = EvaluationDesign.secondary,
            modifier = Modifier.width(EvaluationDesign.studentColumnWidth),
            letterSpacing = 1.sp
        )

        criteria.forEach { crit ->
            Box(
                modifier = Modifier.width(EvaluationDesign.criterionColumnWidth),
                contentAlignment = Alignment.CenterStart
            ) {
                Text(
                    text = crit.criterion.description.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = EvaluationDesign.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    letterSpacing = 0.5.sp
                )
            }
        }

        Box(
            modifier = Modifier.width(EvaluationDesign.scoreColumnWidth),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "NOTA",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Black,
                color = EvaluationDesign.secondary,
                letterSpacing = 1.sp
            )
        }

        Box(
            modifier = Modifier.width(EvaluationDesign.actionsColumnWidth),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "ACCIONES",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Black,
                color = EvaluationDesign.secondary,
                letterSpacing = 1.sp
            )
        }
    }
}

@Composable
private fun StudentEvaluationRow(
    student: Student,
    criteria: List<RubricCriterionWithLevels>,
    selectedLevels: Map<Long, Long>,
    score: Double?,
    onLevelSelected: (Long, Long) -> Unit,
    onCopy: () -> Unit,
    onPaste: () -> Unit,
    onToggleInjured: () -> Unit,
    isPasteEnabled: Boolean
) {
    val isInjured = student.isInjured
    
    OrganicGlassCard(
        modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
        backgroundColor = Color.White,
        borderColor = if (isInjured) EvaluationDesign.danger.copy(alpha = 0.08f) else EvaluationDesign.border,
        borderWidth = 1.dp,
        cornerRadius = EvaluationDesign.innerRadius,
        elevation = 4.dp
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Student Info
            Row(modifier = Modifier.width(EvaluationDesign.studentColumnWidth), verticalAlignment = Alignment.CenterVertically) {
                EvaluationAvatar(
                    initials = student.firstName.take(1) + student.lastName.take(1),
                    tint = if (isInjured) EvaluationDesign.danger else EvaluationDesign.accent
                )
                
                Spacer(Modifier.width(16.dp))
                
                Column {
                    Text(
                        student.fullName,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = EvaluationDesign.primary
                    )
                    Text(
                        text = if (isInjured) "Lesionado" else "Disponible",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isInjured) EvaluationDesign.danger else EvaluationDesign.success.copy(alpha = 0.8f)
                    )
                }

                Spacer(Modifier.weight(1f))

                IconButton(
                    onClick = onToggleInjured,
                    modifier = Modifier.size(32.dp).clip(CircleShape).background(if (isInjured) EvaluationDesign.danger.copy(alpha = 0.1f) else Color.Transparent)
                ) {
                    Icon(
                        Icons.Default.MedicalServices,
                        contentDescription = "Estado médico",
                        tint = if (isInjured) EvaluationDesign.danger else EvaluationDesign.secondary.copy(alpha = 0.4f),
                        modifier = Modifier.size(16.dp)
                    )
                }
                Spacer(Modifier.width(8.dp))
            }

            // Criteria Selectors
            criteria.forEach { critWithLvl ->
                val selectedId = selectedLevels[critWithLvl.criterion.id]
                CriterionSelector(
                    criterionId = critWithLvl.criterion.id,
                    levels = critWithLvl.levels,
                    selectedLevelId = selectedId,
                    onLevelSelected = { onLevelSelected(critWithLvl.criterion.id, it) },
                    modifier = Modifier.width(EvaluationDesign.criterionColumnWidth).padding(horizontal = 4.dp)
                )
            }

            // Score Pill
            ScorePill(score = score, modifier = Modifier.width(EvaluationDesign.scoreColumnWidth))

            // Actions
            Row(modifier = Modifier.width(EvaluationDesign.actionsColumnWidth), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                RowActionButton(
                    icon = Icons.Default.ContentCopy,
                    tint = EvaluationDesign.accent,
                    onClick = onCopy,
                    enabled = true
                )
                Spacer(Modifier.width(8.dp))
                RowActionButton(
                    icon = Icons.Default.ContentPaste,
                    tint = EvaluationDesign.success,
                    onClick = onPaste,
                    enabled = isPasteEnabled
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CriterionSelector(
    criterionId: Long,
    levels: List<RubricLevel>,
    selectedLevelId: Long?,
    onLevelSelected: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(EvaluationDesign.secondary.copy(alpha = 0.05f))
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        levels.forEach { level ->
            val isSelected = level.id == selectedLevelId
            
            TooltipArea(
                tooltip = {
                    OrganicGlassCard(
                        modifier = Modifier.width(250.dp).padding(4.dp),
                        backgroundColor = Color.White.copy(alpha = 0.95f),
                        elevation = 8.dp
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text(level.name, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text("${level.points.toInt()} puntos", color = EvaluationDesign.accent, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                            if (!level.description.isNullOrBlank()) {
                                Spacer(Modifier.height(8.dp))
                                Text(level.description!!, fontSize = 12.sp, color = EvaluationDesign.secondary)
                            }
                        }
                    }
                },
                modifier = Modifier.weight(1f)
            ) {
                Surface(
                    onClick = { onLevelSelected(level.id) },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = RoundedCornerShape(12.dp),
                    color = if (isSelected) EvaluationDesign.accent else Color.Transparent
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                        modifier = Modifier.padding(2.dp)
                    ) {
                        Text(
                            text = level.name,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isSelected) Color.White else EvaluationDesign.primary.copy(alpha = 0.8f),
                            textAlign = TextAlign.Center,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (level.points > 0) {
                            Text(
                                text = "${level.points.toInt()} pts",
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White.copy(alpha = 0.8f) else EvaluationDesign.secondary.copy(alpha = 0.6f)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScorePill(score: Double?, modifier: Modifier = Modifier) {
    val tint = when {
        score == null -> EvaluationDesign.secondary.copy(alpha = 0.2f)
        score >= 5.0 -> EvaluationDesign.success
        else -> EvaluationDesign.danger
    }
    
    Column(modifier = modifier, horizontalAlignment = Alignment.Start) {
        Text("Nota", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = EvaluationDesign.secondary)
        Spacer(Modifier.height(4.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(tint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = score?.let { "%.1f".format(it) } ?: "—",
                fontSize = 18.sp,
                fontWeight = FontWeight.Black,
                color = if (score != null) tint else EvaluationDesign.secondary
            )
        }
    }
}

@Composable
private fun RowActionButton(
    icon: ImageVector,
    tint: Color,
    onClick: () -> Unit,
    enabled: Boolean
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(if (enabled) tint.copy(alpha = 0.12f) else EvaluationDesign.secondary.copy(alpha = 0.1f))
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
            tint = if (enabled) tint else EvaluationDesign.secondary.copy(alpha = 0.35f)
        )
    }
}

@Composable
private fun InjuredSidebar(injuredStudents: List<Student>) {
    OrganicGlassCard(
        modifier = Modifier.width(320.dp).fillMaxHeight(),
        backgroundColor = Color.White.copy(alpha = 0.9f),
        cornerRadius = 32.dp
    ) {
        Column(modifier = Modifier.padding(24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                EvaluationChip(
                    label = "Lesionados",
                    icon = Icons.Default.MedicalServices,
                    tint = EvaluationDesign.danger,
                    isDestructive = true
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = "${injuredStudents.size}",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Black,
                    color = EvaluationDesign.danger
                )
            }

            Spacer(Modifier.height(24.dp))

            if (injuredStudents.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        Icons.Default.CheckCircleOutline,
                        null,
                        modifier = Modifier.size(48.dp),
                        tint = EvaluationDesign.secondary.copy(alpha = 0.4f)
                    )
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "No hay alumnos lesionados",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = EvaluationDesign.secondary,
                        textAlign = TextAlign.Center
                    )
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(injuredStudents) { student ->
                        OrganicGlassCard(
                            modifier = Modifier.fillMaxWidth(),
                            backgroundColor = Color.White,
                            borderColor = EvaluationDesign.danger.copy(alpha = 0.1f),
                            cornerRadius = EvaluationDesign.innerRadius,
                            elevation = 2.dp
                        ) {
                            Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                EvaluationAvatar(
                                    initials = student.firstName.take(1) + student.lastName.take(1),
                                    tint = EvaluationDesign.danger
                                )
                                Spacer(Modifier.width(12.dp))
                                Column {
                                    Text(
                                        student.fullName,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = EvaluationDesign.primary
                                    )
                                    Text(
                                        "Necesita revisión",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = EvaluationDesign.secondary
                                    )
                                }
                                Spacer(Modifier.weight(1f))
                                Icon(Icons.Default.HistoryEdu, null, tint = EvaluationDesign.danger.copy(alpha = 0.6f))
                            }
                        }
                    }
                }
            }
        }
    }
}

// Helper for vertical stacking
@Composable
private fun VStack(
    alignment: Alignment.Horizontal = Alignment.Start,
    spacing: androidx.compose.ui.unit.Dp = 0.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(horizontalAlignment = alignment, verticalArrangement = Arrangement.spacedBy(spacing), content = content)
}
