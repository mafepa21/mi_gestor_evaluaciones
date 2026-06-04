import SwiftUI
import AppKit
import MiGestorKit

struct MacAttendanceDayRow: View {
    private enum RevealedSide {
        case primary
        case incident
    }

    let row: MacAttendanceEntryRow
    let isSelected: Bool
    let isSaving: Bool
    let onSelect: () -> Void
    let onPickStatus: (MacAttendanceStatusOption) -> Void
    let onMarkInjury: () -> Void

    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var revealedSide: RevealedSide?
    @GestureState private var liveTranslation: CGFloat = 0
    @State private var trackpadTranslation: CGFloat = 0

    private let revealedOffset: CGFloat = 232
    private let fullSwipeThreshold: CGFloat = 264

    var body: some View {
        ZStack {
            swipeActionBackground

            rowContent
                .offset(x: displayedOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        .gesture(horizontalSwipeGesture)
        .macTrackpadSwipe { delta in
            trackpadTranslation = delta
        } onEnded: { delta in
            let finalOffset = settledOffset + delta

            if finalOffset >= fullSwipeThreshold {
                performStatus("PRESENTE")
            } else if finalOffset <= -fullSwipeThreshold {
                performStatus("SIN_MATERIAL")
            } else {
                withAnimation(uiFeatureFlags.interactionAnimation) {
                    if let side = revealedSide {
                        if side == .primary && delta < -44 {
                            revealedSide = nil
                        } else if side == .incident && delta > 44 {
                            revealedSide = nil
                        } else {
                            revealedSide = side
                        }
                    } else {
                        if delta > 44 {
                            revealedSide = .primary
                        } else if delta < -44 {
                            revealedSide = .incident
                        } else {
                            revealedSide = nil
                        }
                    }
                }
            }
            trackpadTranslation = 0
        }
    }

    private var rowContent: some View {
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
                        HStack(spacing: 6) {
                            Text(row.record.map { statusLabel($0.status) } ?? "Sin pasar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if row.isInjured {
                                Label("Lesión", systemImage: "bandage.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
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
    }

    @ViewBuilder
    private var swipeActionBackground: some View {
        HStack(spacing: 6) {
            if displayedOffset > 0 {
                swipeButton("Presente", systemImage: "checkmark", tint: .green) {
                    performStatus("PRESENTE")
                }
                swipeButton("Ausente", systemImage: "xmark", tint: .red) {
                    performStatus("AUSENTE")
                }
                swipeButton("Retraso", systemImage: "clock", tint: .orange) {
                    performStatus("TARDE")
                }
            }

            Spacer(minLength: 0)

            if displayedOffset < 0 {
                swipeButton("Material", systemImage: "backpack", tint: .brown) {
                    performStatus("SIN_MATERIAL")
                }
                swipeButton("Justificada", systemImage: "doc.text", tint: .gray) {
                    performStatus("JUSTIFICADO")
                }
                swipeButton("Lesión", systemImage: "bandage", tint: .orange) {
                    onMarkInjury()
                    closeActions()
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppStyle.cardBackground.opacity(0.65))
    }

    private func swipeButton(
        _ label: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(width: 68, height: 42)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var settledOffset: CGFloat {
        switch revealedSide {
        case .primary: return revealedOffset
        case .incident: return -revealedOffset
        case nil: return 0
        }
    }

    private var displayedOffset: CGFloat {
        let activeTranslation = trackpadTranslation != 0 ? trackpadTranslation : liveTranslation
        return min(max(settledOffset + activeTranslation, -fullSwipeThreshold - 16), fullSwipeThreshold + 16)
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($liveTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let finalOffset = settledOffset + value.translation.width

                if finalOffset >= fullSwipeThreshold {
                    performStatus("PRESENTE")
                } else if finalOffset <= -fullSwipeThreshold {
                    performStatus("SIN_MATERIAL")
                } else {
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        if let side = revealedSide {
                            if side == .primary && value.translation.width < -44 {
                                revealedSide = nil
                            } else if side == .incident && value.translation.width > 44 {
                                revealedSide = nil
                            } else {
                                revealedSide = side
                            }
                        } else {
                            if value.translation.width > 44 {
                                revealedSide = .primary
                            } else if value.translation.width < -44 {
                                revealedSide = .incident
                            } else {
                                revealedSide = nil
                            }
                        }
                    }
                }
            }
    }

    private var currentOption: MacAttendanceStatusOption? {
        MacAttendanceStatusOption.option(for: row.record?.status)
    }

    private func statusLabel(_ status: String) -> String {
        MacAttendanceStatusOption.option(for: status)?.label ?? status
    }

    private func performStatus(_ id: String) {
        guard let option = MacAttendanceStatusOption.option(for: id) else { return }
        onPickStatus(option)
        closeActions()
    }

    private func closeActions() {
        withAnimation(uiFeatureFlags.interactionAnimation) {
            revealedSide = nil
        }
    }
}
