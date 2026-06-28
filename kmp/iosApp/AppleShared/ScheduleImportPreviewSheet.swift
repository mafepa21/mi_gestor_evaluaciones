import SwiftUI

struct ScheduleImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: ScheduleImportPreview
    let knownGroupNames: [String: String]
    let isImporting: Bool
    let onConfirm: (ScheduleEmptySlotImportMode) -> Void

    @State private var emptySlotMode: ScheduleEmptySlotImportMode = .skip

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                importPreviewContent
                .padding(24)
            }

            Divider()
            footer
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 620)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder
    private var importPreviewContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    emptySlotControl
                    diagnostics
                }
                .frame(width: 304, alignment: .topLeading)

                slotsByDay
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 688, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 18) {
                summary
                emptySlotControl
                diagnostics
                slotsByDay
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
                .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Importación de horario")
                    .font(.title2.weight(.bold))
                Text(preview.sourceName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            metricGrid

            flowLine(title: "Grupos", values: preview.groupCodes.map { knownGroupNames[$0] ?? groupDisplayName(for: $0) })
            flowLine(title: "Materias", values: preview.subjectNames)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var metricGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                metric("Sesiones", "\(preview.teachingSlots.count)")
                metric("Tutorías", "\(preview.tutoringSlots.count)")
                metric("Recreos", "\(preview.breakSlots.count)")
                metric("Huecos vacíos", "\(preview.emptyCandidates.count)")
                metric("Grupos", "\(preview.groupCodes.count)")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], alignment: .leading, spacing: 12) {
                metric("Sesiones", "\(preview.teachingSlots.count)")
                metric("Tutorías", "\(preview.tutoringSlots.count)")
                metric("Recreos", "\(preview.breakSlots.count)")
                metric("Huecos vacíos", "\(preview.emptyCandidates.count)")
                metric("Grupos", "\(preview.groupCodes.count)")
            }
        }
    }

    private var emptySlotControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Huecos vacíos")
                .font(.headline)
            Text("Huecos vacíos detectados: \(preview.emptyCandidates.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Qué hacer con los huecos vacíos", selection: $emptySlotMode) {
                ForEach(ScheduleEmptySlotImportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(emptySlotMode == .skip ? "Los huecos vacíos y recreos quedarán fuera del guardado." : "La previsualización los clasifica, pero esta versión solo persiste franjas vinculadas a grupo.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var diagnostics: some View {
        if !preview.conflicts.isEmpty || !preview.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !preview.conflicts.isEmpty {
                    Label("Conflictos", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(preview.conflicts, id: \.self) { conflict in
                        Text(conflict)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !preview.warnings.isEmpty {
                    Label("Avisos", systemImage: "info.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    ForEach(preview.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var slotsByDay: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedDays, id: \.weekday) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(weekdayLabel(day.weekday))
                        .font(.headline)

                    ForEach(day.slots) { slot in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(slot.startTime)-\(slot.endTime)")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 104, alignment: .leading)

                            Text(slot.kind.label)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(kindTint(slot.kind).opacity(0.12), in: Capsule(style: .continuous))
                                .foregroundStyle(kindTint(slot.kind))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(slot.displayTitle)
                                    .font(.callout.weight(.semibold))
                                let groups = slot.groupCodes.map { knownGroupNames[$0] ?? groupDisplayName(for: $0) }
                                if !groups.isEmpty {
                                    Text(groups.joined(separator: " + "))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else if slot.rawText.isEmpty {
                                    Text("Sin texto en el Excel")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("\(preview.persistableSlots.count) bloque(s) lectivos listos para guardar.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                onConfirm(emptySlotMode)
            } label: {
                Label(isImporting ? "Importando..." : "Importar horario", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isImporting || preview.persistableSlots.isEmpty || !preview.conflicts.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var groupedDays: [(weekday: Int, slots: [ImportedScheduleSlot])] {
        Dictionary(grouping: preview.slots, by: \.weekday)
            .map { (weekday: $0.key, slots: $0.value.sorted { ($0.startMinute, $0.endMinute) < ($1.startMinute, $1.endMinute) }) }
            .sorted { $0.weekday < $1.weekday }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .frame(minWidth: 92, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func flowLine(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(values.isEmpty ? "Sin datos" : values.joined(separator: " · "))
                .font(.callout.weight(.semibold))
        }
    }

    private func groupDisplayName(for code: String) -> String {
        guard code.count >= 5 else { return code }
        let course = code.prefix(1)
        let suffix = code.suffix(1)
        return "\(course)º ESO \(suffix)"
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        case 6: return "Sábado"
        case 7: return "Domingo"
        default: return "Día \(weekday)"
        }
    }

    private func kindTint(_ kind: ImportedScheduleSlotKind) -> Color {
        switch kind {
        case .teaching:
            return .green
        case .tutoring:
            return .blue
        case .breakTime:
            return .purple
        case .empty:
            return .secondary
        }
    }
}
