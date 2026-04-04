package com.migestor.shared.viewmodel

import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.StudentsRepository
import com.migestor.shared.usecase.XlsxImportPreview
import com.migestor.shared.usecase.XlsxStudentImporter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

data class StudentWithClasses(
    val student: Student,
    val assignedClasses: List<SchoolClass>
)

sealed interface StudentsUiState {
    data object Loading : StudentsUiState
    data class Data(
        val studentsWithClasses: List<StudentWithClasses>,
        val allClasses: List<SchoolClass>
    ) : StudentsUiState
    data class Error(val message: String) : StudentsUiState
}

class StudentsManagerViewModel(
    private val studentsRepository: StudentsRepository,
    private val classesRepository: ClassesRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    private val _state = MutableStateFlow<StudentsUiState>(StudentsUiState.Loading)
    val state: StateFlow<StudentsUiState> = _state.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _selectedIds = MutableStateFlow<Set<Long>>(emptySet())
    val selectedIds: StateFlow<Set<Long>> = _selectedIds.asStateFlow()

    private val _importPreview = MutableStateFlow<XlsxImportPreview?>(null)
    val importPreview: StateFlow<XlsxImportPreview?> = _importPreview.asStateFlow()

    private val _importSelectedIds = MutableStateFlow<Set<Int>>(emptySet())
    val importSelectedIds: StateFlow<Set<Int>> = _importSelectedIds.asStateFlow()

    private val xlsxImporter = XlsxStudentImporter()

    init {
        combine(
            studentsRepository.observeStudents(),
            classesRepository.observeClasses()
        ) { students, classes ->
            students to classes
        }
        .onEach { (students, classes) ->
            val studentsWithClasses = students.map { student ->
                val assigned = classes.filter { schoolClass ->
                    classesRepository.listStudentsInClass(schoolClass.id)
                        .any { it.id == student.id }
                }
                StudentWithClasses(student = student, assignedClasses = assigned)
            }
            _state.value = StudentsUiState.Data(
                studentsWithClasses = studentsWithClasses,
                allClasses = classes
            )
        }
        .catch { e -> _state.value = StudentsUiState.Error(e.message ?: "Error") }
        .launchIn(scope)
    }

    fun search(query: String) {
        _searchQuery.value = query
    }

    fun assignToClass(student: Student, schoolClass: SchoolClass) {
        scope.launch {
            classesRepository.addStudentToClass(schoolClass.id, student.id)
        }
    }

    fun removeFromClass(student: Student, schoolClass: SchoolClass) {
        scope.launch {
            classesRepository.removeStudentFromClass(schoolClass.id, student.id)
        }
    }

    fun deleteStudent(studentId: Long) {
        scope.launch {
            studentsRepository.deleteStudent(studentId)
        }
    }

    fun toggleSelection(studentId: Long) {
        _selectedIds.update { current ->
            if (current.contains(studentId)) current - studentId else current + studentId
        }
    }

    fun selectAll(ids: List<Long>) {
        _selectedIds.update { current ->
            if (current.containsAll(ids)) current - ids.toSet() else current + ids
        }
    }

    fun clearSelection() {
        _selectedIds.value = emptySet()
    }

    fun assignSelectedToClass(schoolClass: SchoolClass, onComplete: (Int) -> Unit) {
        val ids = _selectedIds.value
        scope.launch {
            ids.forEach { studentId ->
                classesRepository.addStudentToClass(schoolClass.id, studentId)
            }
            onComplete(ids.size)
            clearSelection()
        }
    }

    fun deleteSelected(onComplete: (Int) -> Unit) {
        val ids = _selectedIds.value
        scope.launch {
            ids.forEach { studentId ->
                studentsRepository.deleteStudent(studentId)
            }
            onComplete(ids.size)
            clearSelection()
        }
    }

    fun loadImportPreview(rows: List<List<String>>) {
        val preview = xlsxImporter.parse(rows)
        _importPreview.value = preview
        _importSelectedIds.value = preview.students.map { it.rowNumber }.toSet()
    }

    fun toggleImportStudent(rowNumber: Int) {
        _importSelectedIds.update { current ->
            if (current.contains(rowNumber)) current - rowNumber else current + rowNumber
        }
    }

    fun selectAllImport(select: Boolean) {
        val preview = _importPreview.value ?: return
        _importSelectedIds.value = if (select) preview.students.map { it.rowNumber }.toSet() else emptySet()
    }

    fun confirmImport(targetClassId: Long?, onDone: (Int) -> Unit) {
        val preview    = _importPreview.value ?: return
        val selectedNums = _importSelectedIds.value
        val toImport   = preview.students.filter { it.rowNumber in selectedNums }

        scope.launch {
            var count = 0
            for (student in toImport) {
                val studentId = studentsRepository.saveStudent(
                    firstName = student.firstName,
                    lastName  = student.lastName
                )
                if (targetClassId != null) {
                    classesRepository.addStudentToClass(targetClassId, studentId)
                }
                count++
            }
            _importPreview.value    = null
            _importSelectedIds.value = emptySet()
            onDone(count)
        }
    }

    fun clearImportPreview() {
        _importPreview.value     = null
        _importSelectedIds.value = emptySet()
    }

    fun addStudentManually(firstName: String, lastName: String, targetClassId: Long?, onDone: () -> Unit) {
        scope.launch {
            val studentId = studentsRepository.saveStudent(firstName = firstName, lastName = lastName)
            if (targetClassId != null) {
                classesRepository.addStudentToClass(targetClassId, studentId)
            }
            onDone()
        }
    }
}
