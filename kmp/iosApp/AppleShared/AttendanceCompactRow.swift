import SwiftUI
import MiGestorKit

/// Fila compacta y disciplinada de asistencia (52pt) según Jobs Design Philosophy y Apple HIG.
/// Sustituye a las tarjetas sobredimensionadas anteriores de 180pt, permitiendo visualizar
/// más de 12-16 alumnos de un vistazo en iPad y pasar lista en menos de 15 segundos.
struct AttendanceCompactRow: View {
    @Environment(\.colorScheme) var colorScheme
    let row: AttendanceEntryRow
    var index: Int? = nil
    let isSelected: Bool
    let isSaving: Bool
    let onPickStatus: (AttendanceStatusOption) -> Void
    var onClearStatus: (() -> Void)? = nil
    let onSelect: () -> Void
    var onToggleInjury: (() -> Void)? = nil
    var onQuickNote: (() -> Void)? = nil

    private var currentOption: AttendanceStatusOption? {
        AttendanceStatusOption.all.first(where: { $0.id == row.record?.status })
    }

    var body: some View {
        HStack(spacing: 10) {
            // Zona 1: Identidad del alumno (tap abre inspector)
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    if let index {
                        Text("\(index)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)
                    }

                    // Avatar con halo semántico del estado
                    Circle()
                        .fill(currentOption?.color.opacity(0.18) ?? Color.secondary.opacity(0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(currentOption?.color.opacity(0.4) ?? Color.clear, lineWidth: 1.5)
                        )
                        .overlay(
                            Text(row.student.initials)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(currentOption?.color ?? .secondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // Badges de alerta rápida (Educación Física y seguimiento)
                        HStack(spacing: 6) {
                            if row.isInjured {
                                Label("Lesión", systemImage: "bandage.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                            }
                            if row.record?.hasIncident == true {
                                Label("Incidencia", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(EvaluationDesign.danger)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(EvaluationDesign.danger.opacity(0.14), in: Capsule())
                            }
                            if let note = row.record?.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "text.bubble")
                                    Text(note)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            }
                            if !row.isInjured && row.record?.hasIncident != true && (row.record?.note ?? "").isEmpty {
                                Text(currentOption?.label ?? "Sin pasar")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSaving {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
                    .padding(.trailing, 2)
            }

            // Zona 2: Segmented Control Inline de Alta Velocidad (P | A | R | M)
            HStack(spacing: 2) {
                ForEach(AttendanceStatusOption.primaryOptions) { option in
                    let isCurrent = row.record?.status == option.id
                    Button {
                        AppleInteractionFeedback.play(.selection)
                        if isCurrent {
                            onClearStatus?()
                        } else {
                            onPickStatus(option)
                        }
                    } label: {
                        Text(option.shortLabel)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(isCurrent ? option.accessibleTextColor : Color.secondary)
                            .frame(width: 34, height: 30)
                            .background(
                                isCurrent ? option.color : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            // Touch target invisible ampliado a 44x44pt según Apple HIG
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCurrent ? "\(option.label) (activo, pulsar para desmarcar)" : option.label)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
            .padding(2)
            .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            // Zona 3: Acciones secundarias y opciones extendidas
            Menu {
                Section("Otros estados") {
                    ForEach(AttendanceStatusOption.secondaryOptions) { option in
                        let isCurrent = row.record?.status == option.id
                        Button {
                            AppleInteractionFeedback.play(.selection)
                            if isCurrent {
                                onClearStatus?()
                            } else {
                                onPickStatus(option)
                            }
                        } label: {
                            Label(
                                isCurrent ? "\(option.label) (Desmarcar)" : option.label,
                                systemImage: option.id == "JUSTIFICADO" ? "checkmark.seal" : "person.badge.shield.checkmark"
                            )
                        }
                    }
                }

                Section("Acciones") {
                    if let status = row.record?.status, !status.isEmpty {
                        Button {
                            AppleInteractionFeedback.play(.selection)
                            onClearStatus?()
                        } label: {
                            Label("Desmarcar asistencia", systemImage: "arrow.counterclockwise")
                        }
                    }
                    Button(action: onSelect) {
                        Label("Abrir ficha completa", systemImage: "person.crop.circle")
                    }
                    if let onToggleInjury {
                        Button(action: onToggleInjury) {
                            Label(row.isInjured ? "Desmarcar lesión" : "Marcar lesión activa", systemImage: "cross.case")
                        }
                    }
                    if let onQuickNote {
                        Button(action: onQuickNote) {
                            Label("Nota rápida de sesión", systemImage: "square.and.pencil")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.04), in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Más opciones de asistencia para \(row.student.fullName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.09)
                : (colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                AppleInteractionFeedback.play(.selection)
                if let p = AttendanceStatusOption.all.first(where: { $0.id == "PRESENTE" }) {
                    onPickStatus(p)
                }
            } label: {
                Label("Presente", systemImage: "checkmark")
            }
            .tint(AppleDesignSystem.success)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                AppleInteractionFeedback.play(.selection)
                if let a = AttendanceStatusOption.all.first(where: { $0.id == "AUSENTE" }) {
                    onPickStatus(a)
                }
            } label: {
                Label("Ausente", systemImage: "xmark")
            }
            .tint(AppleDesignSystem.danger)

            Button {
                AppleInteractionFeedback.play(.selection)
                if let r = AttendanceStatusOption.all.first(where: { $0.id == "TARDE" }) {
                    onPickStatus(r)
                }
            } label: {
                Label("Retraso", systemImage: "clock")
            }
            .tint(AppleDesignSystem.warning)

            Button {
                AppleInteractionFeedback.play(.selection)
                if let m = AttendanceStatusOption.all.first(where: { $0.id == "SIN_MATERIAL" }) {
                    onPickStatus(m)
                }
            } label: {
                Label("Sin material", systemImage: "tshirt")
            }
            .tint(.purple)
        }
        #endif
    }
}
