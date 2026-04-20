import SwiftUI
import MiGestorKit

struct MacStudentsView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?

    private var students: [Student] {
        selectedClassId == nil ? bridge.allStudents : bridge.studentsInClass
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack {
                Text("Alumnado")
                    .font(MacAppStyle.pageTitle)
                Spacer()
                if !bridge.classes.isEmpty {
                    Picker("Clase", selection: $selectedClassId) {
                        Text("Todas").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .frame(width: 220)
                }
            }

            if students.isEmpty {
                ContentUnavailableView(
                    "Sin alumnado",
                    systemImage: "person.3",
                    description: Text("No hay alumnos disponibles para la clase seleccionada.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Nombre")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Estado")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, MacAppStyle.innerPadding)
                    .padding(.vertical, 10)
                    .background(MacAppStyle.subtleFill)

                    ForEach(Array(students.enumerated()), id: \.element.id) { index, student in
                        HStack {
                            Text("\(student.firstName) \(student.lastName)")
                            Spacer()
                            MacStatusPill(
                                label: student.isInjured ? "Seguimiento" : "Normal",
                                isActive: student.isInjured,
                                tint: student.isInjured ? MacAppStyle.warningTint : MacAppStyle.successTint
                            )
                        }
                        .padding(.horizontal, MacAppStyle.innerPadding)
                        .padding(.vertical, 10)

                        if index < students.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
        .task {
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId
            }
        }
        .task(id: selectedClassId) {
            await bridge.selectStudentsClass(classId: selectedClassId)
        }
    }
}

struct MacRubricsView: View {
    @ObservedObject var bridge: KmpBridge

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Text("Rúbricas")
                .font(MacAppStyle.pageTitle)

            if bridge.rubrics.isEmpty {
                ContentUnavailableView(
                    "Sin rúbricas",
                    systemImage: "checklist",
                    description: Text("Aún no hay rúbricas cargadas en el bridge.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Nombre")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Criterios")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, MacAppStyle.innerPadding)
                    .padding(.vertical, 10)
                    .background(MacAppStyle.subtleFill)

                    ForEach(Array(bridge.rubrics.enumerated()), id: \.element.rubric.id) { index, rubric in
                        HStack {
                            Text(rubric.rubric.name)
                            Spacer()
                            Text("\(rubric.criteria.count)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, MacAppStyle.innerPadding)
                        .padding(.vertical, 10)

                        if index < bridge.rubrics.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
    }
}

struct MacReportsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var selectedClassId: Int64? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Text("Informes")
                .font(MacAppStyle.pageTitle)

            HStack {
                Picker("Grupo", selection: $selectedClassId) {
                    Text("Seleccionar grupo").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .frame(width: 220)
                Spacer()
            }

            if selectedClassId == nil {
                ContentUnavailableView(
                    "Selecciona un grupo",
                    systemImage: "doc.text",
                    description: Text("Elige un grupo para acceder a los informes disponibles.")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stub funcional listo")
                        .font(.headline)
                    Text("El grupo ya queda fijado en la shell Mac. La siguiente iteración podrá colgar aquí el workspace completo de informes sin reabrir el routing.")
                        .font(MacAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }
                .padding(MacAppStyle.innerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
    }
}

struct MacPlannerView: View {
    @ObservedObject var bridge: KmpBridge

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Text("Planificación")
                .font(MacAppStyle.pageTitle)

            if bridge.planning.isEmpty {
                ContentUnavailableView(
                    "Sin sesiones",
                    systemImage: "calendar",
                    description: Text("No hay sesiones planificadas todavía.")
                )
            } else {
                List(bridge.planning, id: \.period.id) { period in
                    Section(period.period.name) {
                        ForEach(period.units, id: \.unit.id) { unit in
                            Label(unit.unit.title, systemImage: "doc.text")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(MacAppStyle.pagePadding)
    }
}
