//
//  NotebookModuleGradeReports.swift
//  MiGestorKMP
//
//  Entrada del Cuaderno a «Enviar notas al alumnado».
//

import SwiftUI
import MiGestorKit

/// Petición de abrir la hoja con los datos del Cuaderno congelados en ese momento.
struct NotebookGradeReportRequest: Identifiable {
    let id = UUID()
    let data: NotebookUiStateData
}

extension NotebookModuleView {
    func gradeReportSheet(data: NotebookUiStateData) -> some View {
        GradeReportDispatchSheet(
            className: currentClass?.name ?? "Grupo",
            periodName: activeNotebookTab(data: data)?.title ?? "Evaluación",
            loadReports: {
                await bridge.buildStudentGradeReports(data: data)
            },
            saveStudentEmail: { studentId, email in
                guard let student = data.sheet.rows.first(where: { $0.student.id == studentId })?.student else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try await bridge.updateMacStudent(
                    student: student,
                    firstName: student.firstName,
                    lastName: student.lastName,
                    email: email,
                    isInjured: student.isInjured
                )
            }
        )
#if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
#endif
    }
}
