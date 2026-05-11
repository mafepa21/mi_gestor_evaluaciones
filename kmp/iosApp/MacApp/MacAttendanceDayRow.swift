import SwiftUI
import AppKit
import MiGestorKit

struct MacAttendanceDayRow: View {
    let row: MacAttendanceEntryRow
    let isSelected: Bool
    let isSaving: Bool
    let onSelect: () -> Void
    let onPickStatus: (MacAttendanceStatusOption) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(currentOption?.color.opacity(0.18) ?? Color.secondary.opacity(0.10))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Text(currentOption?.shortLabel ?? "·")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(currentOption?.color ?? .secondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(row.record.map { statusLabel($0.status) } ?? "Sin pasar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isSaving {
                ProgressView()
                    .scaleEffect(0.7)
            }

            HStack(spacing: 6) {
                ForEach(MacAttendanceStatusOption.all) { option in
                    Button {
                        onPickStatus(option)
                    } label: {
                        Text(option.shortLabel)
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .background(option.color.opacity(row.record?.status == option.id ? 0.22 : 0.08))
                    .foregroundStyle(option.color)
                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
                    .help(option.label)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.08) : MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : MacAppStyle.cardBorder, lineWidth: isSelected ? 1 : 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var currentOption: MacAttendanceStatusOption? {
        MacAttendanceStatusOption.option(for: row.record?.status)
    }

    private func statusLabel(_ status: String) -> String {
        MacAttendanceStatusOption.option(for: status)?.label ?? status
    }
}
