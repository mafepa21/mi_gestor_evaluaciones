import SwiftUI
import MiGestorKit

// MARK: - Layout Presets

enum SeatingLayoutPreset: String, CaseIterable, Identifiable {
    case rows = "Filas tradicionales"
    case pairs = "Mesas dobles / Parejas"
    case horseshoe = "Herradura en U"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rows: return "square.grid.3x3"
        case .pairs: return "rectangle.split.2x1"
        case .horseshoe: return "arrow.turn.down.right"
        }
    }
}

// MARK: - Attendance Helper

enum SeatingAttendanceKind {
    case present
    case absent
    case late
    case unrecorded

    init(rawText: String) {
        let upper = rawText.uppercased()
        if upper.contains("PRES") {
            self = .present
        } else if upper.contains("AUS") {
            self = .absent
        } else if upper.contains("TARD") || upper.contains("RETRA") {
            self = .late
        } else {
            self = .unrecorded
        }
    }

    var ringColor: Color {
        switch self {
        case .present: return EvaluationDesign.success
        case .absent: return EvaluationDesign.danger
        case .late: return .orange
        case .unrecorded: return Color.secondary.opacity(0.25)
        }
    }

    var label: String {
        switch self {
        case .present: return "Presente"
        case .absent: return "Ausente"
        case .late: return "Retraso"
        case .unrecorded: return "Sin registrar"
        }
    }
}

// MARK: - NotebookSeatingPlanView

struct NotebookSeatingPlanView: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    let rows: [NotebookTableRow]
    let averageText: (NotebookTableRow) -> String
    let attendanceText: (Int64) -> String
    let incidentCount: (Int64) -> Int
    let selectedStudentId: Int64?
    let highlightedStudentId: Int64?
    @Binding var seatPositions: [Int64: NotebookSeatPosition]
    let gradableColumns: [NotebookColumnDefinition]
    @Binding var gradingColumnId: String?
    let gradeText: (Int64) -> String
    let onAdjustGrade: (Int64, Double) -> Void
    let onHighlightRandomStudent: () -> Void
    let onResetSeats: () -> Void
    let onPersistSeats: () -> Void
    let onOpenStudent: (Int64) -> Void
    let onMarkPresent: (Int64) -> Void
    let onMarkAbsent: (Int64) -> Void
    let onMarkLate: (Int64) -> Void
    let onFollowUp: (Student) -> Void

    @State private var draggingStudentId: Int64?
    @State private var hoveredStudentId: Int64?
    @State private var isBannerDismissed = false

    private let gradeStepSize: Double = 0.25

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            seatingCanvas
        }
        .appOnChange(of: highlightedStudentId) { _ in
            isBannerDismissed = false
            AppleInteractionFeedback.play(.success)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Plano de clase")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                attendanceStatsBadge
            }

            Spacer()

            if !gradableColumns.isEmpty {
                Menu {
                    Button("Sin calificar (Modo asistencia)") {
                        gradingColumnId = nil
                    }
                    Divider()
                    ForEach(gradableColumns, id: \.id) { column in
                        Button {
                            gradingColumnId = column.id
                        } label: {
                            Label(column.title, systemImage: gradingColumnId == column.id ? "checkmark" : "number")
                        }
                    }
                } label: {
                    Label(
                        gradableColumns.first(where: { $0.id == gradingColumnId })?.title ?? "Calificar en el plano",
                        systemImage: "checklist"
                    )
                }
                .buttonStyle(.bordered)
            }

            Menu {
                Section("Organización del aula") {
                    ForEach(SeatingLayoutPreset.allCases) { preset in
                        Button {
                            applyLayoutPreset(preset)
                        } label: {
                            Label(preset.rawValue, systemImage: preset.icon)
                        }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onResetSeats()
                } label: {
                    Label("Restablecer por defecto", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Label("Disposición", systemImage: "rectangle.3.group")
            }
            .buttonStyle(.bordered)

            Button {
                isBannerDismissed = false
                onHighlightRandomStudent()
            } label: {
                Label("Alumno aleatorio", systemImage: "dice.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Seleccionar un alumno al azar (⌘R)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(NotebookStyle.surface.opacity(0.92))
    }

    private var attendanceStatsBadge: some View {
        let stats = attendanceStats
        return HStack(spacing: 6) {
            HStack(spacing: 3) {
                Circle().fill(EvaluationDesign.success).frame(width: 6, height: 6)
                Text("\(stats.present) P")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            if stats.absent > 0 {
                HStack(spacing: 3) {
                    Circle().fill(EvaluationDesign.danger).frame(width: 6, height: 6)
                    Text("\(stats.absent) A")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
            if stats.late > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("\(stats.late) R")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
    }

    private var attendanceStats: (present: Int, absent: Int, late: Int) {
        var p = 0, a = 0, l = 0
        for row in rows {
            let kind = SeatingAttendanceKind(rawText: attendanceText(row.student.id))
            switch kind {
            case .present: p += 1
            case .absent: a += 1
            case .late: l += 1
            case .unrecorded: break
            }
        }
        return (p, a, l)
    }

    // MARK: - Seating Canvas

    private var seatingCanvas: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Background
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                NotebookStyle.surfaceMuted.opacity(0.96),
                                NotebookStyle.surface.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .padding(18)

                // Chalkboard / Front of class indicator
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 11, weight: .bold))
                    Text("PIZARRA · FRENTE DEL AULA")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.4)
                }
                .foregroundStyle(.secondary.opacity(0.75))
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                )
                .padding(.top, 24)

                // Dragging guide overlay
                if draggingStudentId != nil {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(NotebookStyle.primaryTint.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [7, 7]))
                        .padding(26)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                // Student desk cards
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    let position = resolvedSeatPosition(for: item.student.id, index: index, total: rows.count)
                    let isDragging = draggingStudentId == item.student.id
                    NotebookSeatCard(
                        student: item.student,
                        averageText: averageText(item),
                        attendanceText: attendanceText(item.student.id),
                        incidentCount: incidentCount(item.student.id),
                        isHighlighted: highlightedStudentId == item.student.id,
                        isSelected: selectedStudentId == item.student.id,
                        isDragging: isDragging,
                        isHovering: hoveredStudentId == item.student.id,
                        gradeText: gradingColumnId != nil ? gradeText(item.student.id) : nil,
                        onTap: {
                            onOpenStudent(item.student.id)
                        },
                        onIncrementGrade: {
                            onAdjustGrade(item.student.id, gradeStepSize)
                        },
                        onDecrementGrade: {
                            onAdjustGrade(item.student.id, -gradeStepSize)
                        },
                        onMarkPresent: {
                            onMarkPresent(item.student.id)
                        },
                        onMarkAbsent: {
                            onMarkAbsent(item.student.id)
                        },
                        onMarkLate: {
                            onMarkLate(item.student.id)
                        },
                        onFollowUp: {
                            onFollowUp(item.student)
                        }
                    )
                    .position(
                        x: max(96, min(proxy.size.width - 96, CGFloat(position.x) * proxy.size.width)),
                        y: max(96, min(proxy.size.height - 96, CGFloat(position.y) * proxy.size.height))
                    )
                    .zIndex(isDragging ? 2 : (highlightedStudentId == item.student.id ? 1 : 0))
                    #if os(macOS)
                    .onHover { isHovering in
                        hoveredStudentId = isHovering ? item.student.id : nil
                    }
                    #endif
                    .gesture(
                        DragGesture(coordinateSpace: .named("seatingCanvas"))
                            .onChanged { value in
                                if draggingStudentId != item.student.id {
                                    draggingStudentId = item.student.id
                                }
                                let rawX = value.location.x / max(proxy.size.width, 1)
                                let rawY = value.location.y / max(proxy.size.height, 1)
                                seatPositions[item.student.id] = NotebookSeatPosition(
                                    x: min(max(rawX, 0.10), 0.90),
                                    y: min(max(rawY, 0.18), 0.88)
                                )
                            }
                            .onEnded { _ in
                                if let current = seatPositions[item.student.id] {
                                    let snapped = applyMagneticSnap(to: current, studentId: item.student.id)
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        seatPositions[item.student.id] = snapped
                                    }
                                }
                                onPersistSeats()
                                AppleInteractionFeedback.play(.success)
                                withAnimation(uiFeatureFlags.interactionAnimation) {
                                    draggingStudentId = nil
                                }
                            }
                    )
                }

                // Active Student Floating Banner
                if let highlightedStudentId,
                   !isBannerDismissed,
                   let activeRow = rows.first(where: { $0.student.id == highlightedStudentId }) {
                    activeStudentBanner(activeRow)
                        .padding(.top, 56)
                        .zIndex(10)
                }
            }
            .padding(20)
            .coordinateSpace(name: "seatingCanvas")
        }
    }

    // MARK: - Active Student Banner

    private func activeStudentBanner(_ row: NotebookTableRow) -> some View {
        let student = row.student
        let attendance = attendanceText(student.id)
        let attendanceKind = SeatingAttendanceKind(rawText: attendance)
        let initials = String(student.firstName.prefix(1)) + String(student.lastName.prefix(1))

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(attendanceKind.ringColor, lineWidth: 2.5)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(NotebookStyle.primaryTint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Text(initials)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(NotebookStyle.primaryTint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(student.fullName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    Text("Alumno activo")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(EvaluationDesign.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(EvaluationDesign.accent.opacity(0.14)))
                }

                HStack(spacing: 8) {
                    Text(attendanceKind.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(attendanceKind.ringColor)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text("Media \(averageText(row))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    if gradingColumnId != nil {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("Nota: \(gradeText(student.id))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(NotebookStyle.primaryTint)
                    }
                }
            }

            Spacer(minLength: 12)

            Button {
                onOpenStudent(student.id)
            } label: {
                Label("Abrir ficha", systemImage: "person.text.rectangle")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .buttonStyle(.bordered)

            Button {
                isBannerDismissed = false
                onHighlightRandomStudent()
            } label: {
                Label("Siguiente al azar", systemImage: "dice.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .buttonStyle(.borderedProminent)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isBannerDismissed = true
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar aviso de alumno activo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(EvaluationDesign.accent.opacity(0.35), lineWidth: 1.5)
        )
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Layout Algorithms & Snap

    private func applyLayoutPreset(_ preset: SeatingLayoutPreset) {
        let total = rows.count
        guard total > 0 else { return }

        var newPositions: [Int64: NotebookSeatPosition] = [:]

        switch preset {
        case .rows:
            let columns = max(3, Int(ceil(sqrt(Double(total)))))
            let totalRows = Int(ceil(Double(total) / Double(columns)))
            let horizontalStep = 0.76 / Double(max(columns - 1, 1))
            let verticalStep = 0.65 / Double(max(totalRows - 1, 1))

            for (index, item) in rows.enumerated() {
                let row = index / columns
                let col = index % columns
                let x = 0.12 + Double(col) * horizontalStep
                let y = 0.20 + Double(row) * verticalStep
                newPositions[item.student.id] = NotebookSeatPosition(x: x, y: y)
            }

        case .pairs:
            let pairColumns = max(2, Int(ceil(sqrt(Double(total) / 2.0))))
            let pairColStep = 0.74 / Double(max(pairColumns - 1, 1))
            let totalPairs = Int(ceil(Double(total) / 2.0))
            let pairRows = Int(ceil(Double(totalPairs) / Double(pairColumns)))
            let verticalStep = 0.65 / Double(max(pairRows - 1, 1))

            for (index, item) in rows.enumerated() {
                let pairIdx = index / 2
                let side = index % 2
                let pRow = pairIdx / pairColumns
                let pCol = pairIdx % pairColumns

                let baseX = 0.13 + Double(pCol) * pairColStep
                let deskOffset = (side == 0) ? -0.038 : 0.038
                let x = min(max(baseX + deskOffset, 0.08), 0.92)
                let y = 0.20 + Double(pRow) * verticalStep
                newPositions[item.student.id] = NotebookSeatPosition(x: x, y: y)
            }

        case .horseshoe:
            let leftCount = max(1, (total - 2) / 3)
            let rightCount = leftCount
            let bottomCount = max(1, total - leftCount - rightCount)

            for (index, item) in rows.enumerated() {
                let x: Double
                let y: Double

                if index < leftCount {
                    x = 0.12
                    let step = 0.62 / Double(max(leftCount, 1))
                    y = 0.22 + Double(index) * step
                } else if index < leftCount + bottomCount {
                    let bIndex = index - leftCount
                    let step = 0.76 / Double(max(bottomCount + 1, 1))
                    x = 0.12 + Double(bIndex + 1) * step
                    y = 0.84
                } else {
                    let rIndex = index - (leftCount + bottomCount)
                    x = 0.88
                    let step = 0.62 / Double(max(rightCount, 1))
                    y = 0.84 - Double(rIndex + 1) * step
                }

                newPositions[item.student.id] = NotebookSeatPosition(x: x, y: y)
            }
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            seatPositions = newPositions
        }
        onPersistSeats()
        AppleInteractionFeedback.play(.selection)
    }

    private func applyMagneticSnap(to pos: NotebookSeatPosition, studentId: Int64) -> NotebookSeatPosition {
        var x = pos.x
        var y = pos.y

        let snapThresholdX = 0.025
        let snapThresholdY = 0.03

        var snappedX = false
        var snappedY = false

        for (id, other) in seatPositions where id != studentId {
            if !snappedX && abs(other.x - x) < snapThresholdX {
                x = other.x
                snappedX = true
            }
            if !snappedY && abs(other.y - y) < snapThresholdY {
                y = other.y
                snappedY = true
            }
            if snappedX && snappedY { break }
        }

        if !snappedX {
            let stepX = 0.04
            x = (x / stepX).rounded() * stepX
        }
        if !snappedY {
            let stepY = 0.05
            y = (y / stepY).rounded() * stepY
        }

        let clampedX = min(max(x, 0.10), 0.90)
        let clampedY = min(max(y, 0.18), 0.88)
        return NotebookSeatPosition(x: clampedX, y: clampedY)
    }

    private func resolvedSeatPosition(for studentId: Int64, index: Int, total: Int) -> NotebookSeatPosition {
        if let existing = seatPositions[studentId] {
            return existing
        }
        let columns = max(3, Int(ceil(sqrt(Double(max(total, 1))))))
        let row = index / columns
        let column = index % columns
        let horizontalStep = 0.76 / Double(max(columns - 1, 1))
        let verticalRows = Int(ceil(Double(max(total, 1)) / Double(columns)))
        let verticalStep = 0.65 / Double(max(verticalRows - 1, 1))
        return NotebookSeatPosition(
            x: 0.12 + Double(column) * horizontalStep,
            y: 0.20 + Double(row) * verticalStep
        )
    }
}

private struct NotebookSeatCard: View {
    let student: Student
    let averageText: String
    let attendanceText: String
    let incidentCount: Int
    let isHighlighted: Bool
    let isSelected: Bool
    let isDragging: Bool
    let isHovering: Bool
    let gradeText: String?
    let onTap: () -> Void
    let onIncrementGrade: () -> Void
    let onDecrementGrade: () -> Void
    let onMarkPresent: () -> Void
    let onMarkAbsent: () -> Void
    let onMarkLate: () -> Void
    let onFollowUp: () -> Void

    private var attendanceKind: SeatingAttendanceKind {
        SeatingAttendanceKind(rawText: attendanceText)
    }

    private var initials: String {
        String(student.firstName.prefix(1)) + String(student.lastName.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Avatar + Names + Incident Badge
            HStack(alignment: .top, spacing: 8) {
                // Avatar with attendance ring
                ZStack {
                    Circle()
                        .stroke(attendanceKind.ringColor, lineWidth: 2.5)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(NotebookStyle.primaryTint.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Text(initials)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(student.fullName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 4) {
                        Text(attendanceKind.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(attendanceKind.ringColor)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(averageText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if incidentCount > 0 {
                    Text("\(incidentCount)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }

            Spacer(minLength: 0)

            // Bottom action row: Grade adjustment OR Attendance quick buttons
            if let gradeText {
                HStack(spacing: 6) {
                    Button(action: {
                        AppleInteractionFeedback.play(.selection)
                        onDecrementGrade()
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotebookStyle.warningTint)
                            .frame(width: 42, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(NotebookStyle.warningTint.opacity(0.12))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(NotebookScaleButtonStyle())
                    .accessibilityLabel("Bajar nota")

                    // Grade pill with semantic color
                    gradePill(gradeText)
                        .frame(maxWidth: .infinity)

                    Button(action: {
                        AppleInteractionFeedback.play(.selection)
                        onIncrementGrade()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotebookStyle.successTint)
                            .frame(width: 42, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(NotebookStyle.successTint.opacity(0.12))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(NotebookScaleButtonStyle())
                    .accessibilityLabel("Subir nota")
                }
                .opacity(isDragging ? 0.42 : 1)
            } else {
                HStack(spacing: 5) {
                    attendanceButton(
                        symbol: "checkmark",
                        text: "P",
                        tint: EvaluationDesign.success,
                        isActive: attendanceKind == .present,
                        accessibilityTitle: "Presente",
                        action: onMarkPresent
                    )
                    attendanceButton(
                        symbol: "xmark",
                        text: "A",
                        tint: EvaluationDesign.danger,
                        isActive: attendanceKind == .absent,
                        accessibilityTitle: "Ausente",
                        action: onMarkAbsent
                    )
                    attendanceButton(
                        symbol: "clock.fill",
                        text: "R",
                        tint: .orange,
                        isActive: attendanceKind == .late,
                        accessibilityTitle: "Retraso",
                        action: onMarkLate
                    )
                    followUpButton(action: onFollowUp)
                }
                .opacity(isDragging ? 0.42 : 1)
            }
        }
        .padding(12)
        .frame(width: 172, height: 142)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    isHighlighted
                        ? EvaluationDesign.accent.opacity(0.14)
                        : (isDragging ? NotebookStyle.primaryTint.opacity(0.16) : NotebookStyle.surface)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isHighlighted
                        ? EvaluationDesign.accent
                        : (isSelected || isDragging || isHovering ? NotebookStyle.primaryTint : Color.white.opacity(0.12)),
                    lineWidth: isHighlighted ? 2.5 : (isSelected || isDragging ? 2 : 1)
                )
        )
        .shadow(
            color: isHighlighted
                ? EvaluationDesign.accent.opacity(0.35)
                : (Color.black.opacity(isDragging ? 0.20 : 0.08)),
            radius: isHighlighted ? 14 : (isDragging ? 18 : 10),
            x: 0,
            y: isHighlighted ? 4 : (isDragging ? 12 : 5)
        )
        .scaleEffect(isHighlighted ? 1.04 : (isDragging ? 1.03 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHighlighted)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private func gradePill(_ text: String) -> some View {
        let num = Double(text.replacingOccurrences(of: ",", with: "."))
        let color: Color = {
            if let num {
                return RubricsStyle.gradeColor(forScoreOutOfTen: num)
            }
            return NotebookStyle.primaryTint
        }()

        return Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func attendanceButton(
        symbol: String,
        text: String,
        tint: Color,
        isActive: Bool,
        accessibilityTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppleInteractionFeedback.play(.selection)
            action()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            .foregroundStyle(isActive ? contrastingTextColor(for: tint) : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? tint : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? tint : tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .accessibilityLabel(accessibilityTitle)
    }

    private func followUpButton(action: @escaping () -> Void) -> some View {
        Button {
            AppleInteractionFeedback.play(.selection)
            action()
        } label: {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.purple.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .accessibilityLabel("Registrar seguimiento o estrella")
    }
}
