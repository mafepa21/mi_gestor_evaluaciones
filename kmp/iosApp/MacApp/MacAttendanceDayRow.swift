import SwiftUI
import AppKit
import MiGestorKit

/// Fila de asistencia para macOS. Delega en `AttendanceCompactRow` de `AppleShared`
/// para garantizar consistencia visual y ergonomía de pase de lista relámpago (<15s).
struct MacAttendanceDayRow: View {
    let row: AttendanceEntryRow
    let isSelected: Bool
    let isSaving: Bool
    let onSelect: () -> Void
    let onPickStatus: (AttendanceStatusOption) -> Void
    var onClearStatus: (() -> Void)? = nil
    let onMarkInjury: () -> Void

    var body: some View {
        AttendanceCompactRow(
            row: row,
            isSelected: isSelected,
            isSaving: isSaving,
            onPickStatus: onPickStatus,
            onClearStatus: onClearStatus,
            onSelect: onSelect,
            onToggleInjury: onMarkInjury
        )
    }
}
