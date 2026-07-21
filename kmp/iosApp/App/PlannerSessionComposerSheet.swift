import SwiftUI
import MiGestorKit

struct PlannerSessionComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacPopupActionBar(
                title: vm.composerDraft.sessionId == 0 ? "Nueva sesión" : "Editar sesión",
                subtitle: "Planificación",
                saveTitle: vm.composerSaveState == .saving ? "Guardando..." : "Guardar",
                canSave: canSave,
                onClose: { dismiss() },
                onSave: saveAndDismiss
            )
            .frame(maxWidth: .infinity)
            .zIndex(2)

            composerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 10) {
                        PlannerSaveStateInlineStatus(state: vm.composerSaveState)
                        Spacer()
                        Button("Cancelar") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)

                        Button("Guardar") {
                            saveAndDismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .keyboardShortcut("s", modifiers: [.command])
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(MacAppStyle.divider.opacity(0.7))
                            .frame(height: 0.5)
                    }
                }
        }
        .frame(minWidth: 920, minHeight: 720)
        .task {
            await vm.refreshComposerContext()
        }
        .appOnChange(of: vm.composerDraft.groupId) { _ in
            vm.composerDraft.teachingUnitId = nil
            Task { await vm.refreshComposerContext() }
        }
        .appOnChange(of: vm.composerDraft.teachingUnitId) { newValue in
            if let newValue,
               let unit = vm.composerTeachingUnits.first(where: { $0.id == newValue }) {
                vm.composerDraft.unitTitle = unit.name
            }
            Task { await vm.refreshComposerContext() }
        }
        #else
        NavigationStack {
            composerContent
            .navigationTitle(vm.composerDraft.sessionId == 0 ? "Nueva sesión" : "Editar sesión")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            if await vm.saveComposer() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.composerDraft.groupId == nil || vm.isSavingComposer)
                }
            }
            .task {
                await vm.refreshComposerContext()
            }
            .appOnChange(of: vm.composerDraft.groupId) { _ in
                vm.composerDraft.teachingUnitId = nil
                Task { await vm.refreshComposerContext() }
            }
            .appOnChange(of: vm.composerDraft.teachingUnitId) { newValue in
                if let newValue,
                   let unit = vm.composerTeachingUnits.first(where: { $0.id == newValue }) {
                    vm.composerDraft.unitTitle = unit.name
                }
                Task { await vm.refreshComposerContext() }
            }
        }
        #endif
    }

    private var canSave: Bool {
        vm.composerDraft.groupId != nil && !vm.isSavingComposer
    }

    private var composerContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                PremiumCard.section(title: vm.composerDraft.sessionId == 0 ? "Nueva sesión" : "Editar sesión", systemImage: "pencil.and.outline") {
                    VStack(alignment: .leading, spacing: 14) {
                        PlannerSaveStateInlineStatus(state: vm.composerSaveState)

                        Text("Redacta la sesión en formato largo y déjala ya planificada.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        Picker("Curso", selection: $vm.composerDraft.groupId) {
                            Text("Selecciona curso").tag(Optional<Int64>.none)
                            ForEach(vm.groups, id: \.id) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Unidad / SA existente", selection: $vm.composerDraft.teachingUnitId) {
                            Text("Crear o elegir después").tag(Optional<Int64>.none)
                            ForEach(vm.composerTeachingUnits, id: \.id) { unit in
                                Text(unit.name).tag(Optional(unit.id))
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("Nueva Unidad / SA", text: $vm.composerDraft.unitTitle, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Objetivos")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $vm.composerDraft.objectives)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resumen de la sesión")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $vm.composerDraft.activities)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }

                PremiumCard.section(title: "Instrumentos enlazados", systemImage: "doc.plaintext.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selecciona evaluaciones o rúbricas filtradas por el curso y la situación de aprendizaje.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        if !vm.composerContextError.isEmpty {
                            Text(vm.composerContextError)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        if vm.composerAvailableInstruments.isEmpty {
                            Text("No hay instrumentos disponibles para este curso todavía.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            PlannerInstrumentCompactPicker(vm: vm)
                        }
                    }
                }

                PremiumCard.section(title: "Dónde cae la sesión", systemImage: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Se guardará como planificada en la franja seleccionada.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        Picker("Día", selection: $vm.composerDraft.dayOfWeek) {
                            ForEach(vm.visibleWeekdays, id: \.self) { day in
                                Text(vm.dayLabel(for: day)).tag(day)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Franja", selection: $vm.composerDraft.period) {
                            ForEach(vm.visibleSlots, id: \.period) { slot in
                                Text(slot.label).tag(slot.period)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(IOSAppStyle.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveAndDismiss() {
        guard canSave else { return }
        Task {
            if await vm.saveComposer() {
                dismiss()
            }
        }
    }
}

private struct PlannerSaveStateInlineStatus: View {
    let state: PlannerSaveState

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                if state == .saving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: iconName)
                }
                Text(message)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
        }
    }

    private var message: String? {
        switch state {
        case .idle:
            return nil
        case .saving:
            return "Guardando..."
        case .saved:
            return "Guardado"
        case .failed(let text):
            return text
        }
    }

    private var iconName: String {
        switch state {
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .failed:
            return EvaluationDesign.danger
        case .saving:
            return EvaluationDesign.accent
        default:
            return EvaluationDesign.success
        }
    }
}

private extension SessionJournalMediaType {
    var title: String {
        switch self {
        case .photo: return "Foto"
        case .audio: return "Audio"
        case .transcript: return "Dictado"
        default: return "Media"
        }
    }
}

private extension SessionJournalLinkType {
    var title: String {
        switch self {
        case .notebook: return "Cuaderno"
        case .attendance: return "Asistencia"
        case .incident: return "Incidencia"
        case .family: return "Familias"
        default: return "Enlace"
        }
    }
}


