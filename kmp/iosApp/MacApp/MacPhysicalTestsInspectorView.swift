import SwiftUI
import MiGestorKit

struct MacPhysicalTestsInspectorView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var inspectorState: PhysicalTestsMacInspectorState
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Label("Inspector", systemImage: "sidebar.right")
                .font(.headline)

            Divider()

            if let selectedTest = inspectorState.selectedTest {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedTest.evaluation.name)
                        .font(.title3.weight(.semibold))
                    Text(selectedTest.evaluation.type)
                        .foregroundStyle(.secondary)
                    MacStatusPill(label: "\(selectedTest.recordedCount) registros", isActive: selectedTest.recordedCount > 0, tint: .orange)
                }

                Divider()

                InspectorLine(title: "Media", value: PhysicalTestsFormatting.decimal(selectedTest.average))
                InspectorLine(title: "Mejor marca", value: selectedTest.best.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                InspectorLine(title: "Alumnos", value: "\(selectedTest.results.count)")

                Button {
                    inspectorState.selectedSection = .capture
                } label: {
                    Label("Abrir captura", systemImage: "tablecells")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onOpenModule(.notebook, selectedClassId, selectedStudentId)
                } label: {
                    Label("Abrir cuaderno", systemImage: "book.closed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Selecciona o crea una prueba física para ver detalles.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(MacAppStyle.pagePadding)
    }
}

private struct InspectorLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }
}
