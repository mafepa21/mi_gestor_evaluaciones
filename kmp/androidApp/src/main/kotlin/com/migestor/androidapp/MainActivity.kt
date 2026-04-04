package com.migestor.androidapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.createAndroidDriver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = KmpContainer(createAndroidDriver(applicationContext))
        setContent {
            MaterialTheme {
                AppScreen(container)
            }
        }
    }
}

@Composable
private fun AppScreen(container: KmpContainer) {
    val scope = remember { CoroutineScope(Dispatchers.Main) }

    var className by remember { mutableStateOf("3 ESO A") }
    var classCourse by remember { mutableStateOf("3") }
    var classId by remember { mutableStateOf<Long?>(null) }

    var studentName by remember { mutableStateOf("Ana") }
    var studentLastName by remember { mutableStateOf("López") }
    var studentId by remember { mutableStateOf<Long?>(null) }

    var evalCode by remember { mutableStateOf("EX1") }
    var evalName by remember { mutableStateOf("Examen 1") }
    var evalType by remember { mutableStateOf("Examen") }
    var evalWeight by remember { mutableStateOf("1") }
    var evalId by remember { mutableStateOf<Long?>(null) }

    var gradeValue by remember { mutableStateOf("8.5") }
    var rows by remember { mutableStateOf(listOf<String>()) }
    var status by remember { mutableStateOf("Listo") }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("MiGestor KMP MVP", style = MaterialTheme.typography.headlineSmall)

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(className, { className = it }, label = { Text("Clase") }, modifier = Modifier.weight(1f))
            OutlinedTextField(classCourse, { classCourse = it }, label = { Text("Curso") }, modifier = Modifier.weight(1f))
        }
        Button(onClick = {
            scope.launch {
                runCatching {
                    classId = container.saveClass(name = className, course = classCourse.toInt(), description = null)
                }.onSuccess { status = "Clase creada id=$it" }
                    .onFailure { status = it.message ?: "Error creando clase" }
            }
        }) { Text("Guardar clase") }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(studentName, { studentName = it }, label = { Text("Nombre") }, modifier = Modifier.weight(1f))
            OutlinedTextField(studentLastName, { studentLastName = it }, label = { Text("Apellidos") }, modifier = Modifier.weight(1f))
        }
        Button(onClick = {
            scope.launch {
                runCatching {
                    studentId = container.saveStudent(firstName = studentName, lastName = studentLastName, email = null)
                }.onSuccess { status = "Alumno creado id=$it" }
                    .onFailure { status = it.message ?: "Error creando alumno" }
            }
        }) { Text("Guardar alumno") }

        Button(onClick = {
            scope.launch {
                val cId = classId
                val sId = studentId
                if (cId == null || sId == null) {
                    status = "Crea clase y alumno antes de vincular"
                    return@launch
                }
                runCatching { container.classesRepository.addStudentToClass(cId, sId) }
                    .onSuccess { status = "Alumno vinculado a clase" }
                    .onFailure { status = it.message ?: "Error vinculando" }
            }
        }) { Text("Vincular alumno a clase") }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(evalCode, { evalCode = it }, label = { Text("Código") }, modifier = Modifier.weight(1f))
            OutlinedTextField(evalName, { evalName = it }, label = { Text("Evaluación") }, modifier = Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(evalType, { evalType = it }, label = { Text("Tipo") }, modifier = Modifier.weight(1f))
            OutlinedTextField(evalWeight, { evalWeight = it }, label = { Text("Peso") }, modifier = Modifier.weight(1f))
        }
        Button(onClick = {
            scope.launch {
                val cId = classId
                if (cId == null) {
                    status = "Crea una clase primero"
                    return@launch
                }
                runCatching {
                    evalId = container.saveEvaluation(
                        classId = cId,
                        code = evalCode,
                        name = evalName,
                        type = evalType,
                        weight = evalWeight.toDouble(),
                        formula = null,
                    )
                }.onSuccess { status = "Evaluación creada id=$it" }
                    .onFailure { status = it.message ?: "Error creando evaluación" }
            }
        }) { Text("Guardar evaluación") }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(gradeValue, { gradeValue = it }, label = { Text("Nota") }, modifier = Modifier.weight(1f))
            Button(onClick = {
                scope.launch {
                    val sId = studentId
                    val eId = evalId
                    if (sId == null || eId == null) {
                        status = "Crea alumno y evaluación antes de calificar"
                        return@launch
                    }
                    runCatching {
                        container.recordGrade(studentId = sId, evaluationId = eId, value = gradeValue.toDouble(), evidence = null)
                    }.onSuccess { status = "Nota guardada" }
                        .onFailure { status = it.message ?: "Error guardando nota" }
                }
            }) { Text("Guardar nota") }
        }

        Button(onClick = {
            scope.launch {
                val cId = classId
                if (cId == null) {
                    status = "Crea una clase primero"
                    return@launch
                }
                runCatching {
                    container.getNotebook(cId).rows.map { row ->
                        "${row.student.lastName}, ${row.student.firstName} -> media ${row.weightedAverage ?: 0.0}"
                    }
                }.onSuccess {
                    rows = it
                    status = "Cuaderno cargado"
                }.onFailure {
                    status = it.message ?: "Error cargando cuaderno"
                }
            }
        }) { Text("Cargar cuaderno") }

        Text("Estado: $status")

        LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f, fill = false)) {
            items(rows) { row ->
                Text(row, modifier = Modifier.padding(vertical = 2.dp))
            }
        }
    }
}
