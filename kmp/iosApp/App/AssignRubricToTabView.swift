import SwiftUI
import MiGestorKit

struct AssignRubricToTabView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var dialog: AssignRubricDialogState? {
        bridge.rubricsUiState?.assignDialogState
    }

    var body: some View {
#if os(macOS)
        content
            .frame(width: 720, height: 560)
            .background(sheetBackground)
#else
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sheetBackground)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.18)

            Group {
                if let state = dialog {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            rubricSummaryCard(state)
                            classSelectionCard(state)

                            if state.selectedClassId != nil {
                                destinationCard(state)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparando asignación...")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
                .opacity(0.18)

            footer
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))

                Image(systemName: "checklist.checked")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Asignar rúbrica")
                    .font(.title2.weight(.bold))

                Text("Vincula esta rúbrica a una clase y decide en qué pestaña del cuaderno se creará.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                closeSheet()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private func rubricSummaryCard(_ state: AssignRubricDialogState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Rúbrica")

            HStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 36, height: 36)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(state.rubricName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Label("Evaluación vinculada", systemImage: "link")
                        Label("Cuaderno", systemImage: "tablecells")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(cardStroke(cornerRadius: 12))
    }

    private func classSelectionCard(_ state: AssignRubricDialogState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Clase")

            Picker(
                "Selecciona clase",
                selection: Binding<Int64>(
                    get: { state.selectedClassId?.int64Value ?? 0 },
                    set: { bridge.onAssignClassSelected($0) }
                )
            ) {
                Text("Elige una clase").tag(Int64(0))

                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(schoolClass.name).tag(schoolClass.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .controlSize(.large)

            Text("La rúbrica quedará disponible para evaluar a este grupo desde el Cuaderno.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(cardStroke(cornerRadius: 12))
    }

    private func destinationCard(_ state: AssignRubricDialogState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                sectionLabel("Destino en el cuaderno")
                Spacer()

                Toggle(
                    "Crear pestaña nueva",
                    isOn: Binding(
                        get: { state.createNewTab },
                        set: { bridge.onToggleCreateNewTab($0) }
                    )
                )
                .toggleStyle(.switch)
            }

            if state.createNewTab {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nueva pestaña")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    TextField(
                        "Nombre de pestaña",
                        text: Binding(
                            get: { state.newTabName },
                            set: { bridge.onNewTabNameChanged($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pestaña existente")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Pestaña",
                        selection: Binding<String>(
                            get: { state.selectedTab ?? state.availableTabs.first ?? "" },
                            set: { bridge.onAssignTabSelected($0) }
                        )
                    ) {
                        ForEach(state.availableTabs, id: \.self) { tab in
                            Text(tab).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                }
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(cardStroke(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(canAssign ? "Listo para guardar" : "Completa los datos para continuar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(canAssign ? .green : .secondary)

                Text(footerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cerrar") {
                closeSheet()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            Button {
                bridge.confirmAssignRubric()
                dismiss()
            } label: {
                Label("Guardar asignación", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAssign)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(footerBackground)
    }

    private var canAssign: Bool {
        guard let state = dialog, state.selectedClassId != nil else { return false }
        if state.createNewTab {
            return !state.newTabName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return state.selectedTab != nil || !state.availableTabs.isEmpty
    }

    private var footerHint: String {
        guard let state = dialog else { return "Cargando información de la rúbrica." }

        if state.selectedClassId == nil {
            return "Selecciona primero la clase de destino."
        }

        if state.createNewTab &&
            state.newTabName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Introduce el nombre de la nueva pestaña."
        }

        return "Se creará el vínculo de rúbrica en el cuaderno."
    }

    private func closeSheet() {
        bridge.dismissAssignRubricDialog()
        dismiss()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private var sheetBackground: some View {
        appPageBackground(for: colorScheme)
    }

    private var cardBackground: some ShapeStyle {
        AnyShapeStyle(appCardBackground(for: colorScheme).opacity(0.92))
    }

    private func cardStroke(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.secondary.opacity(0.16), lineWidth: 1)
    }

    private var footerBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}
