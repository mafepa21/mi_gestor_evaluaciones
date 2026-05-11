import SwiftUI
import MiGestorKit

struct NotebookSeatingPlanView: View {
    let rows: [NotebookTableRow]
    let averageText: (NotebookTableRow) -> String
    let attendanceText: (Int64) -> String
    let incidentCount: (Int64) -> Int
    let selectedStudentId: Int64?
    let highlightedStudentId: Int64?
    @Binding var seatPositions: [Int64: NotebookSeatPosition]
    let onHighlightRandomStudent: () -> Void
    let onResetSeats: () -> Void
    let onPersistSeats: () -> Void
    let onOpenStudent: (Int64) -> Void
    let onMarkPresent: (Int64) -> Void
    let onMarkAbsent: (Int64) -> Void
    let onMarkLate: (Int64) -> Void
    let onFollowUp: (Student) -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            seatingCanvas
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Plano de clase")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Spacer()

            Button {
                onHighlightRandomStudent()
            } label: {
                Label("Alumno aleatorio", systemImage: "dice")
            }
            .buttonStyle(.borderedProminent)

            Button {
                onResetSeats()
            } label: {
                Label("Reordenar", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(NotebookStyle.surface.opacity(0.92))
    }

    private var seatingCanvas: some View {
        GeometryReader { proxy in
            ZStack {
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

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    let position = resolvedSeatPosition(for: item.student.id, index: index, total: rows.count)
                    NotebookSeatCard(
                        student: item.student,
                        averageText: averageText(item),
                        attendanceText: attendanceText(item.student.id),
                        incidentCount: incidentCount(item.student.id),
                        isHighlighted: highlightedStudentId == item.student.id,
                        isSelected: selectedStudentId == item.student.id,
                        onTap: {
                            onOpenStudent(item.student.id)
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
                    .frame(width: 166, height: 138)
                    .position(
                        x: max(96, min(proxy.size.width - 96, CGFloat(position.x) * proxy.size.width)),
                        y: max(86, min(proxy.size.height - 86, CGFloat(position.y) * proxy.size.height))
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let clampedX = min(max(value.location.x / max(proxy.size.width, 1), 0.12), 0.88)
                                let clampedY = min(max(value.location.y / max(proxy.size.height, 1), 0.12), 0.88)
                                seatPositions[item.student.id] = NotebookSeatPosition(x: clampedX, y: clampedY)
                            }
                            .onEnded { _ in
                                onPersistSeats()
                            }
                    )
                }
            }
            .padding(20)
        }
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
        let verticalStep = 0.68 / Double(max(verticalRows - 1, 1))
        return NotebookSeatPosition(
            x: 0.12 + Double(column) * horizontalStep,
            y: 0.16 + Double(row) * verticalStep
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
    let onTap: () -> Void
    let onMarkPresent: () -> Void
    let onMarkAbsent: () -> Void
    let onMarkLate: () -> Void
    let onFollowUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(NotebookStyle.primaryTint.opacity(0.16))
                    Text(String(student.firstName.prefix(1)) + String(student.lastName.prefix(1)))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(student.fullName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text(attendanceText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Media \(averageText)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if incidentCount > 0 {
                    Text("\(incidentCount)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }

            HStack(spacing: 6) {
                quickAction("P", tint: NotebookStyle.successTint, action: onMarkPresent)
                quickAction("A", tint: .red, action: onMarkAbsent)
                quickAction("R", tint: NotebookStyle.warningTint, action: onMarkLate)
                quickAction("Seg", tint: .orange, action: onFollowUp)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isHighlighted ? NotebookStyle.primaryTint.opacity(0.18) : NotebookStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder((isSelected ? NotebookStyle.primaryTint : Color.white.opacity(0.10)), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private func quickAction(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}
