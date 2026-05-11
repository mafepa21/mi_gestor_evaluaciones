import SwiftUI
import PhotosUI
import MiGestorKit

extension NotebookModuleView {
    func syncInspectorDraft() {
        guard let selection = inspectorSelection,
              let data = bridge.notebookState as? NotebookUiStateData,
              let item = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }) else {
            inspectorState.resetDrafts()
            return
        }
        let persisted = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })
        inspectorNoteDraft = persisted?.annotation?.note ?? ""
        inspectorIconDraft = persisted?.annotation?.icon ?? persisted?.iconValue ?? ""
        inspectorAttachmentUris = persisted?.annotation?.attachmentUris ?? []
    }

    func refreshNotebookSignals() async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        do {
            let attendance = try await bridge.attendanceRecords(for: classId, on: Date())
            await MainActor.run {
                todayAttendanceByStudentId = Dictionary(
                    attendance.map { ($0.studentId, $0.status) },
                    uniquingKeysWith: { _, latest in latest }
                )
            }
        } catch {
            await MainActor.run { todayAttendanceByStudentId = [:] }
        }

        do {
            let incidents = try await bridge.incidents(for: classId)
            let counts = Dictionary(grouping: incidents.compactMap { $0.studentId?.int64Value }, by: { $0 }).mapValues(\.count)
            await MainActor.run {
                incidentCountByStudentId = counts
            }
        } catch {
            await MainActor.run { incidentCountByStudentId = [:] }
        }
    }

    func attendanceStatusText(for studentId: Int64) -> String {
        todayAttendanceByStudentId[studentId] ?? "Sin pasar"
    }

    func markAttendance(for studentId: Int64, status: String) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        let canonicalStatus = NotebookAttendanceStatus.canonical(status)
        do {
            try await bridge.saveAttendance(studentId: studentId, classId: classId, on: Date(), status: canonicalStatus)
            await refreshNotebookSignals()
        } catch {
        }
    }

    func requestMarkAllVisibleStudentsPresent(data: NotebookUiStateData) {
        let visibleRows = filteredRows(data: data)
        guard !visibleRows.isEmpty else { return }
        if visibleRows.count > 5 {
            isMarkAllPresentDialogPresented = true
        } else {
            markAllVisibleStudentsPresent(data: data)
        }
    }

    func markAllVisibleStudentsPresent(data: NotebookUiStateData) {
        let visibleRows = filteredRows(data: data)
        guard !visibleRows.isEmpty else { return }
        Task {
            for row in visibleRows {
                await markAttendance(for: row.student.id, status: NotebookAttendanceStatus.present)
            }
            await MainActor.run {
                showToast("\(visibleRows.count) alumnos marcados como presentes")
            }
        }
    }

    func recordCellUndo(studentId: Int64, column: NotebookColumnDefinition, previousValue: String, previousDisplayLabel: String?) {
        undoStack.append(
            NotebookCellUndoEntry(
                studentId: studentId,
                column: column,
                previousValue: previousValue,
                previousDisplayLabel: previousDisplayLabel
            )
        )
        if undoStack.count > 10 {
            undoStack.removeFirst(undoStack.count - 10)
        }
    }

    func undoLastCellChange() {
        guard let entry = undoStack.popLast() else {
            showToast("No hay cambios que deshacer", style: .warning)
            return
        }
        bridge.flushPendingColumnGradeSave(studentId: entry.studentId, columnId: entry.column.id)
        bridge.saveColumnGrade(studentId: entry.studentId, column: entry.column, value: entry.previousValue)
        cellReloadRevision += 1
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            inspectorSelection = NotebookInspectorSelection(studentId: entry.studentId, columnId: entry.column.id)
            focusedCellId = nil
            activeChoiceCellId = nil
        }
        let label = entry.previousDisplayLabel ?? entry.previousValue
        showToast(label.isEmpty ? "Cambio deshecho" : "Cambio deshecho: \(label)")
    }

    func createFollowUp(for student: Student) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        do {
            _ = try await bridge.createIncident(
                classId: classId,
                studentId: student.id,
                title: "Seguimiento desde plano",
                detail: "Marcado desde el plano de clase del cuaderno."
            )
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: classId,
                on: Date(),
                status: NotebookAttendanceStatus.canonical(todayAttendanceByStudentId[student.id] ?? NotebookAttendanceStatus.present),
                note: "Seguimiento abierto desde el plano.",
                hasIncident: true
            )
            await refreshNotebookSignals()
        } catch {
        }
    }

    func importSelectedAttachment(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value,
              let selection = inspectorSelection else { return }

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotebookEvidence", isDirectory: true)
            .appendingPathComponent("\(classId)", isDirectory: true)
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(selection.studentId)_\(selection.columnId)_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            await MainActor.run {
                inspectorAttachmentUris.append(url.path)
                selectedAttachmentPhoto = nil
            }
        } catch {
            await MainActor.run {
                selectedAttachmentPhoto = nil
            }
        }
    }

    func defaultSeatPositions(for rows: [NotebookTableRow]) -> [Int64: NotebookSeatPosition] {
        guard !rows.isEmpty else { return [:] }
        let columns = max(3, Int(ceil(sqrt(Double(rows.count)))))
        let horizontalStep = 0.76 / Double(max(columns - 1, 1))
        let verticalRows = Int(ceil(Double(rows.count) / Double(columns)))
        let verticalStep = 0.68 / Double(max(verticalRows - 1, 1))
        return Dictionary(uniqueKeysWithValues: rows.enumerated().map { index, item in
            let row = index / columns
            let column = index % columns
            let x = 0.12 + Double(column) * horizontalStep
            let y = 0.16 + Double(row) * verticalStep
            return (item.student.id, NotebookSeatPosition(x: x, y: y))
        })
    }

    func randomEligibleStudentId(from rows: [NotebookTableRow]) -> Int64? {
        let eligible = rows
            .map(\.student.id)
            .filter { !attendanceStatusText(for: $0).localizedCaseInsensitiveContains("aus") }
        return (eligible.isEmpty ? rows.map(\.student.id) : eligible).randomElement()
    }

    func seatStorageKey() -> String? {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return nil }
        return "notebook.seating.\(classId).\(bridge.selectedNotebookTabId ?? "all")"
    }

    func persistSeatPositions() {
        guard let key = seatStorageKey(),
              let encoded = try? JSONEncoder().encode(seatPositions) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    func restoreSeatPositions() {
        guard let key = seatStorageKey() else {
            seatPositions = [:]
            return
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Int64: NotebookSeatPosition].self, from: data) {
            seatPositions = decoded
        } else if let data = bridge.notebookState as? NotebookUiStateData {
            seatPositions = defaultSeatPositions(for: filteredRows(data: data))
        } else {
            seatPositions = [:]
        }
    }

}
