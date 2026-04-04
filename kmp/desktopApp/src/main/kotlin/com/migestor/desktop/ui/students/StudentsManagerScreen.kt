package com.migestor.desktop.ui.students

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.usecase.XlsxImportPreview
import com.migestor.shared.viewmodel.StudentWithClasses
import com.migestor.shared.viewmodel.StudentsManagerViewModel
import com.migestor.shared.viewmodel.StudentsUiState
import java.io.FileInputStream
import java.io.FilenameFilter
import java.awt.FileDialog
import java.awt.Frame
import org.apache.poi.ss.usermodel.DataFormatter
import org.apache.poi.ss.usermodel.Row
import org.apache.poi.xssf.usermodel.XSSFWorkbook

@Composable
fun StudentsManagerScreen(
    container: KmpContainer,
    onStatus: (String) -> Unit
) {
    val viewModel = remember(container) {
        StudentsManagerViewModel(
            studentsRepository = container.studentsRepository,
            classesRepository  = container.classesRepository
        )
    }

    val uiState     by viewModel.state.collectAsState()
    val searchQuery by viewModel.searchQuery.collectAsState()
    val selectedIds by viewModel.selectedIds.collectAsState()

    val importPreview    by viewModel.importPreview.collectAsState()
    val importSelectedIds by viewModel.importSelectedIds.collectAsState()

    var showBulkAssignDialog by remember { mutableStateOf(false) }
    var showAddManualDialog  by remember { mutableStateOf(false) }
    var showBulkDeleteDialog by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {

        // ── Toolbar principal ─────────────────────────────
        Surface(tonalElevation = 2.dp) {
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedTextField(
                        value         = searchQuery,
                        onValueChange = { viewModel.search(it) },
                        placeholder   = { Text("Buscar alumno...") },
                        leadingIcon   = { Icon(Icons.Default.Search, null) },
                        singleLine    = true,
                        shape         = RoundedCornerShape(12.dp),
                        modifier      = Modifier.width(300.dp)
                    )

                    Spacer(Modifier.weight(1f))

                    // Botón Añadir Manual
                    Button(
                        onClick = { showAddManualDialog = true },
                        shape   = RoundedCornerShape(10.dp),
                        colors  = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Icon(Icons.Default.PersonAdd, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Añadir Alumno")
                    }

                    // Botón Importar Excel
                    Button(
                        onClick = {
                            try {
                                val dialog = FileDialog(
                                    null as Frame?,
                                    "Seleccionar Excel de alumnos",
                                    FileDialog.LOAD
                                ).apply {
                                    // FIX: en macOS, file = "*.xlsx" lanza "Char sequence is empty"
                                    // Usar FilenameFilter en su lugar
                                    filenameFilter = FilenameFilter { _, name ->
                                        name.endsWith(".xlsx", ignoreCase = true) ||
                                        name.endsWith(".xls", ignoreCase = true)
                                    }
                                    isVisible = true
                                }

                                val directory = dialog.directory ?: return@Button
                                val file      = dialog.file      ?: return@Button
                                val path      = directory + file

                                val workbook  = XSSFWorkbook(FileInputStream(path))
                                // FIX: DataFormatter maneja celdas vacías, numéricas y de fórmula sin lanzar excepciones
                                val formatter = DataFormatter()
                                val sheet     = workbook.getSheetAt(0)

                                val rows = sheet.map { row ->
                                    (0..1).map { colIdx ->
                                        val cell = row.getCell(
                                            colIdx,
                                            // FIX: RETURN_BLANK_AS_NULL evita NPE en celdas inexistentes
                                            Row.MissingCellPolicy.RETURN_BLANK_AS_NULL
                                        )
                                        if (cell == null) "" else formatter.formatCellValue(cell).trim()
                                    }
                                }
                                workbook.close()
                                viewModel.loadImportPreview(rows)
                            } catch (e: Exception) {
                                onStatus("Error al leer el archivo: ${e.message}")
                            }
                        },
                        shape          = RoundedCornerShape(10.dp),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Icon(Icons.Default.FileUpload, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Importar Excel")
                    }

                    val totalCount = (uiState as? StudentsUiState.Data)?.studentsWithClasses?.size ?: 0
                    Text("$totalCount alumnos en total",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline)
                }

                // ── Barra de selección — solo visible si hay algo seleccionado
                if (selectedIds.isNotEmpty()) {
                    Surface(
                        color  = MaterialTheme.colorScheme.primaryContainer,
                        shape  = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Icon(Icons.Default.CheckCircle, null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp))
                            Text(
                                "${selectedIds.size} alumno${if (selectedIds.size > 1) "s" else ""} seleccionado${if (selectedIds.size > 1) "s" else ""}",
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer
                            )

                            Spacer(Modifier.weight(1f))

                            // Asignar seleccionados a clase
                            Button(
                                onClick = { showBulkAssignDialog = true },
                                shape   = RoundedCornerShape(10.dp),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                Icon(Icons.Default.Group, null, Modifier.size(16.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Asignar a clase")
                            }

                            // Eliminar seleccionados
                            Button(
                                onClick = { showBulkDeleteDialog = true },
                                shape   = RoundedCornerShape(10.dp),
                                colors  = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                Icon(Icons.Default.Delete, null, Modifier.size(16.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Eliminar")
                            }

                            // Limpiar selección
                            OutlinedButton(
                                onClick = { viewModel.clearSelection() },
                                shape   = RoundedCornerShape(10.dp),
                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
                            ) {
                                Icon(Icons.Default.Close, null, Modifier.size(16.dp))
                                Spacer(Modifier.width(4.dp))
                                Text("Limpiar")
                            }
                        }
                    }
                }
            }
        }

        // ── Lista de alumnos ──────────────────────────────
        when (val state = uiState) {
            is StudentsUiState.Loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            is StudentsUiState.Error -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Error: ${state.message}", color = MaterialTheme.colorScheme.error)
                }
            }
            is StudentsUiState.Data -> {
                val filtered = state.studentsWithClasses.filter { swc ->
                    searchQuery.isBlank() ||
                    swc.student.firstName.contains(searchQuery, ignoreCase = true) ||
                    swc.student.lastName.contains(searchQuery, ignoreCase = true)
                }

                val filteredIds    = filtered.map { it.student.id }
                val allSelected    = filteredIds.isNotEmpty() && selectedIds.containsAll(filteredIds)
                val someSelected   = selectedIds.isNotEmpty() && !allSelected

                Column(modifier = Modifier.fillMaxSize()) {

                    // ── Fila de cabecera con "Seleccionar todos" ──
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            .padding(horizontal = 20.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // Checkbox "seleccionar todos"
                        TriStateCheckbox(
                            state   = when {
                                allSelected  -> ToggleableState.On
                                someSelected -> ToggleableState.Indeterminate
                                else         -> ToggleableState.Off
                            },
                            onClick = { viewModel.selectAll(filteredIds) }
                        )
                        Text(
                            if (allSelected) "Deseleccionar todos" else "Seleccionar todos (${filtered.size})",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    HorizontalDivider()

                    // ── Filas de alumnos ──────────────────────────
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        items(filtered, key = { it.student.id }) { swc ->
                            val isSelected = selectedIds.contains(swc.student.id)
                            StudentCard(
                                studentWithClasses = swc,
                                allClasses         = state.allClasses,
                                isSelected         = isSelected,
                                onToggleSelect     = { viewModel.toggleSelection(swc.student.id) },
                                onAssign           = { schoolClass ->
                                    viewModel.assignToClass(swc.student, schoolClass)
                                    onStatus("${swc.student.firstName} asignado a ${schoolClass.name}")
                                },
                                onRemove           = { schoolClass ->
                                    viewModel.removeFromClass(swc.student, schoolClass)
                                    onStatus("${swc.student.firstName} eliminado de ${schoolClass.name}")
                                },
                                onDelete           = {
                                    viewModel.deleteStudent(swc.student.id)
                                    onStatus("Alumno eliminado")
                                }
                            )
                        }
                    }
                }

                // ── Dialog asignación en bloque ───────────────
                if (showBulkAssignDialog) {
                    BulkAssignDialog(
                        allClasses    = state.allClasses,
                        selectedCount = selectedIds.size,
                        onDismiss     = { showBulkAssignDialog = false },
                        onConfirm     = { schoolClass ->
                            viewModel.assignSelectedToClass(schoolClass) { count ->
                                onStatus("$count alumnos asignados a ${schoolClass.name}")
                            }
                            showBulkAssignDialog = false
                        }
                    )
                }

                // ── Dialog de importación ─────────────────────
                if (importPreview != null) {
                    ImportPreviewDialog(
                        preview           = importPreview!!,
                        allClasses        = (uiState as? StudentsUiState.Data)?.allClasses ?: emptyList(),
                        selectedRowNums   = importSelectedIds,
                        onToggle          = { viewModel.toggleImportStudent(it) },
                        onSelectAll       = { viewModel.selectAllImport(it) },
                        onDismiss         = { viewModel.clearImportPreview() },
                        onConfirm         = { classId ->
                            viewModel.confirmImport(classId) { count ->
                                onStatus("$count alumnos importados correctamente")
                            }
                        }
                    )
                }

                // ── Dialog de añadir manual ───────────────────
                if (showAddManualDialog) {
                    AddStudentManualDialog(
                        allClasses = (uiState as? StudentsUiState.Data)?.allClasses ?: emptyList(),
                        onDismiss  = { showAddManualDialog = false },
                        onConfirm  = { first, last, classId ->
                            viewModel.addStudentManually(first, last, classId) {
                                onStatus("Alumno añadido correctamente")
                            }
                            showAddManualDialog = false
                        }
                    )
                }

                // ── Dialog de borrado en bloque ───────────────
                if (showBulkDeleteDialog) {
                    AlertDialog(
                        onDismissRequest = { showBulkDeleteDialog = false },
                        title = { Text("Eliminar alumnos") },
                        text  = { Text("¿Estás seguro de que quieres eliminar a los ${selectedIds.size} alumnos seleccionados? Esta acción no se puede deshacer.") },
                        confirmButton = {
                            Button(
                                onClick = {
                                    viewModel.deleteSelected { count ->
                                        onStatus("$count alumnos eliminados")
                                    }
                                    showBulkDeleteDialog = false
                                },
                                colors  = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                            ) { Text("Eliminar") }
                        },
                        dismissButton = {
                            TextButton(onClick = { showBulkDeleteDialog = false }) { Text("Cancelar") }
                        }
                    )
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────
// Dialog añadir alumno manualmente
// ─────────────────────────────────────────────────────────

@Composable
private fun AddStudentManualDialog(
    allClasses: List<SchoolClass>,
    onDismiss: () -> Unit,
    onConfirm: (String, String, Long?) -> Unit
) {
    var firstName by remember { mutableStateOf("") }
    var lastName  by remember { mutableStateOf("") }
    var selectedClassId by remember { mutableStateOf<Long?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Añadir Alumno Manualmente") },
        text  = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value         = firstName,
                    onValueChange = { firstName = it },
                    label         = { Text("Nombre") },
                    modifier      = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value         = lastName,
                    onValueChange = { lastName = it },
                    label         = { Text("Apellidos") },
                    modifier      = Modifier.fillMaxWidth()
                )

                Text("Asignar a clase (opcional):", style = MaterialTheme.typography.labelMedium)

                var expanded by remember { mutableStateOf(false) }
                Box {
                    OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
                        Text(allClasses.find { it.id == selectedClassId }?.let { "${it.course}º ${it.name}" } ?: "Sin clase")
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Default.ArrowDropDown, null)
                    }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        DropdownMenuItem(text = { Text("Sin clase") }, onClick = { selectedClassId = null; expanded = false })
                        allClasses.forEach { c ->
                            DropdownMenuItem(text = { Text("${c.course}º ${c.name}") }, onClick = { selectedClassId = c.id; expanded = false })
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(firstName, lastName, selectedClassId) },
                enabled = firstName.isNotBlank() && lastName.isNotBlank()
            ) { Text("Guardar") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancelar") }
        }
    )
}

// ─────────────────────────────────────────────────────────
// Dialog vista previa importación
// ─────────────────────────────────────────────────────────

@Composable
private fun ImportPreviewDialog(
    preview: XlsxImportPreview,
    allClasses: List<SchoolClass>,
    selectedRowNums: Set<Int>,
    onToggle: (Int) -> Unit,
    onSelectAll: (Boolean) -> Unit,
    onDismiss: () -> Unit,
    onConfirm: (Long?) -> Unit
) {
    var selectedClassId by remember { mutableStateOf<Long?>(null) }
    val allSelected = selectedRowNums.size == preview.students.size

    AlertDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.width(560.dp),
        title = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.FileUpload, null, tint = MaterialTheme.colorScheme.primary)
                    Text("Vista previa de importación", fontWeight = FontWeight.Bold)
                }
                if (preview.className != null) {
                    Text("Clase detectada: ${preview.className}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline)
                }
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {

                // Selector de clase destino
                Text("Asignar a clase (opcional):",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary)

                var classExpanded by remember { mutableStateOf(false) }
                Box {
                    OutlinedButton(
                        onClick = { classExpanded = true },
                        shape   = RoundedCornerShape(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(allClasses.find { it.id == selectedClassId }
                            ?.let { "${it.course}º - ${it.name}" }
                            ?: "Sin asignar a clase (solo crear alumnos)")
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Default.ArrowDropDown, null)
                    }
                    DropdownMenu(expanded = classExpanded, onDismissRequest = { classExpanded = false }) {
                        DropdownMenuItem(
                            text    = { Text("Sin asignar a clase") },
                            onClick = { selectedClassId = null; classExpanded = false }
                        )
                        allClasses.forEach { schoolClass ->
                            DropdownMenuItem(
                                text    = { Text("${schoolClass.course}º - ${schoolClass.name}") },
                                onClick = { selectedClassId = schoolClass.id; classExpanded = false }
                            )
                        }
                    }
                }

                HorizontalDivider()

                // Cabecera con "seleccionar todos"
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked         = allSelected,
                        onCheckedChange = { onSelectAll(it) }
                    )
                    Text("${selectedRowNums.size} de ${preview.students.size} alumnos seleccionados",
                        style = MaterialTheme.typography.labelMedium)
                }

                // Lista de alumnos detectados
                LazyColumn(
                    modifier = Modifier.heightIn(max = 320.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    items(preview.students, key = { it.rowNumber }) { student ->
                        val isSelected = selectedRowNums.contains(student.rowNumber)
                        Surface(
                            onClick  = { onToggle(student.rowNumber) },
                            shape    = RoundedCornerShape(10.dp),
                            color    = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
                                       else MaterialTheme.colorScheme.surfaceVariant,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                Checkbox(
                                    checked         = isSelected,
                                    onCheckedChange = { onToggle(student.rowNumber) }
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(student.fullName,
                                        fontWeight = FontWeight.SemiBold,
                                        fontSize   = 13.sp)
                                    Text("Nombre: ${student.firstName}  ·  Apellidos: ${student.lastName}",
                                        fontSize = 11.sp,
                                        color    = MaterialTheme.colorScheme.outline)
                                }
                                Text("${student.rowNumber}",
                                    fontSize = 11.sp,
                                    color    = MaterialTheme.colorScheme.outline)
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick  = { onConfirm(selectedClassId) },
                enabled  = selectedRowNums.isNotEmpty(),
                shape    = RoundedCornerShape(10.dp)
            ) {
                Icon(Icons.Default.Check, null, Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("Importar ${selectedRowNums.size} alumnos")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancelar") }
        }
    )
}

// ─────────────────────────────────────────────────────────
// Dialog asignación en bloque
// ─────────────────────────────────────────────────────────

@Composable
private fun BulkAssignDialog(
    allClasses: List<SchoolClass>,
    selectedCount: Int,
    onDismiss: () -> Unit,
    onConfirm: (SchoolClass) -> Unit
) {
    var pickedClass by remember { mutableStateOf<SchoolClass?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.Group, null, tint = MaterialTheme.colorScheme.primary)
                Text("Asignar $selectedCount alumno${if (selectedCount > 1) "s" else ""} a clase")
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Selecciona la clase de destino:",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                allClasses.forEach { schoolClass ->
                    val selected = pickedClass?.id == schoolClass.id
                    Surface(
                        onClick  = { pickedClass = schoolClass },
                        shape    = RoundedCornerShape(12.dp),
                        color    = if (selected) MaterialTheme.colorScheme.primaryContainer
                                   else MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            RadioButton(selected = selected, onClick = { pickedClass = schoolClass })
                            Column {
                                Text("${schoolClass.course}º - ${schoolClass.name}",
                                    fontWeight = FontWeight.Bold,
                                    color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer
                                            else MaterialTheme.colorScheme.onSurfaceVariant)
                                schoolClass.description?.let {
                                    Text(it, fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.outline)
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick  = { pickedClass?.let { onConfirm(it) } },
                enabled  = pickedClass != null,
                shape    = RoundedCornerShape(10.dp)
            ) {
                Icon(Icons.Default.Check, null, Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("Asignar")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancelar") }
        }
    )
}

// ─────────────────────────────────────────────────────────
// Card individual de alumno
// ─────────────────────────────────────────────────────────

@Composable
private fun StudentCard(
    studentWithClasses: StudentWithClasses,
    allClasses: List<SchoolClass>,
    isSelected: Boolean,
    onToggleSelect: () -> Unit,
    onAssign: (SchoolClass) -> Unit,
    onRemove: (SchoolClass) -> Unit,
    onDelete: () -> Unit
) {
    val student         = studentWithClasses.student
    val assignedClasses = studentWithClasses.assignedClasses
    var showClassPicker by remember { mutableStateOf(false) }
    var confirmDelete   by remember { mutableStateOf(false) }

    Surface(
        shape    = RoundedCornerShape(14.dp),
        color    = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
                   else MaterialTheme.colorScheme.surface,
        modifier = Modifier
            .fillMaxWidth()
            .border(
                width = if (isSelected) 2.dp else 1.dp,
                color = if (isSelected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.outlineVariant,
                shape = RoundedCornerShape(14.dp)
            )
            .clickable { onToggleSelect() }
    ) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Checkbox de selección
            Checkbox(
                checked         = isSelected,
                onCheckedChange = { onToggleSelect() }
            )

            // Avatar con iniciales
            Surface(
                shape    = RoundedCornerShape(50),
                color    = if (isSelected) MaterialTheme.colorScheme.primary
                           else MaterialTheme.colorScheme.primaryContainer,
                modifier = Modifier.size(44.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        "${student.firstName.firstOrNull() ?: '?'}${student.lastName.firstOrNull() ?: '?'}".uppercase(),
                        fontWeight = FontWeight.Bold,
                        fontSize   = 15.sp,
                        color      = if (isSelected) MaterialTheme.colorScheme.onPrimary
                                     else MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }

            // Nombre + chips de clases
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "${student.lastName}, ${student.firstName}",
                    fontWeight = FontWeight.SemiBold,
                    fontSize   = 14.sp
                )
                Spacer(Modifier.height(4.dp))
                if (assignedClasses.isEmpty()) {
                    Text("Sin clase asignada",
                        fontSize = 12.sp,
                        color    = MaterialTheme.colorScheme.error.copy(alpha = 0.8f))
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        assignedClasses.forEach { schoolClass ->
                            ClassChip(
                                label    = "${schoolClass.course}º ${schoolClass.name}",
                                onRemove = { onRemove(schoolClass) }
                            )
                        }
                    }
                }
            }

            // Botón asignar clase individual
            OutlinedButton(
                onClick        = { showClassPicker = true },
                shape          = RoundedCornerShape(10.dp),
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)
            ) {
                Icon(Icons.Default.Add, null, Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text("Clase", fontSize = 12.sp)
            }

            // Botón eliminar
            IconButton(onClick = { confirmDelete = true }) {
                Icon(Icons.Default.Delete, null,
                    tint     = MaterialTheme.colorScheme.error.copy(alpha = 0.5f),
                    modifier = Modifier.size(20.dp))
            }
        }
    }

    // ── Picker de clase individual ────────────────────────
    if (showClassPicker) {
        val unassigned = allClasses.filter { c -> assignedClasses.none { it.id == c.id } }
        AlertDialog(
            onDismissRequest = { showClassPicker = false },
            title = { Text("Asignar a clase") },
            text  = {
                if (unassigned.isEmpty()) {
                    Text("El alumno ya está en todas las clases disponibles.")
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        unassigned.forEach { schoolClass ->
                            Surface(
                                onClick = { onAssign(schoolClass); showClassPicker = false },
                                shape   = RoundedCornerShape(10.dp),
                                color   = MaterialTheme.colorScheme.surfaceVariant,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier.padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Icon(Icons.Default.Class, null,
                                        Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.primary)
                                    Text("${schoolClass.course}º - ${schoolClass.name}",
                                        fontWeight = FontWeight.Medium)
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showClassPicker = false }) { Text("Cancelar") }
            }
        )
    }

    // ── Confirmar borrado ─────────────────────────────────
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Eliminar alumno") },
            text  = { Text("¿Eliminar a ${student.firstName} ${student.lastName}? Esta acción no se puede deshacer.") },
            confirmButton = {
                Button(
                    onClick = { onDelete(); confirmDelete = false },
                    colors  = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) { Text("Eliminar") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancelar") }
            }
        )
    }
}

// ─────────────────────────────────────────────────────────
// Chip de clase con botón quitar
// ─────────────────────────────────────────────────────────

@Composable
private fun ClassChip(label: String, onRemove: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.secondaryContainer
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier          = Modifier.padding(start = 10.dp, end = 4.dp, top = 3.dp, bottom = 3.dp)
        ) {
            Text(label,
                fontSize   = 11.sp,
                fontWeight = FontWeight.Medium,
                color      = MaterialTheme.colorScheme.onSecondaryContainer)
            Spacer(Modifier.width(2.dp))
            IconButton(onClick = onRemove, modifier = Modifier.size(18.dp)) {
                Icon(Icons.Default.Close, null,
                    Modifier.size(11.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.6f))
            }
        }
    }
}
