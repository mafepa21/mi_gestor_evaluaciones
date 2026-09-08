import SwiftUI
import MiGestorKit

enum NotebookKeypadAdvanceMode: String, CaseIterable, Identifiable {
    case immediate = "inmediato"
    case withDelay = "pausa"
    case manual = "manual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediate: return "Inmediato"
        case .withDelay: return "Pausa (0.4s)"
        case .manual: return "Manual"
        }
    }

    var icon: String {
        switch self {
        case .immediate: return "bolt.fill"
        case .withDelay: return "timer"
        case .manual: return "hand.tap"
        }
    }
}

enum NotebookKeypadDirection: String, CaseIterable, Identifiable {
    case down = "down"
    case right = "right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .down: return "↓ Abajo (alumnos)"
        case .right: return "→ Derecha (columnas)"
        }
    }

    var shortTitle: String {
        switch self {
        case .down: return "↓ Alumnos"
        case .right: return "→ Columnas"
        }
    }

    var systemImage: String {
        switch self {
        case .down: return "arrow.down"
        case .right: return "arrow.right"
        }
    }

    var navigationDirection: NotebookNavigationDirection {
        switch self {
        case .down: return .down
        case .right: return .right
        }
    }
}

struct NotebookQuickKeypadDock: View {
    let studentName: String?
    let studentInitials: String?
    let studentIndex: Int?
    let totalStudents: Int?
    let columnTitle: String?
    let columnSystemIcon: String?
    let categoryTint: Color?
    let currentValue: String
    let isEditable: Bool
    let hasActiveSelection: Bool
    @Binding var advanceMode: NotebookKeypadAdvanceMode
    @Binding var direction: NotebookKeypadDirection
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let onApplyGrade: (String) -> Void
    let onApplyModifier: (Double) -> Void
    let onApplyDecimalFraction: (String) -> Void
    let onClear: () -> Void
    let onBackspace: () -> Void
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onStartAtFirstStudent: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let numberKeys = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    private let decimalFractions = [".25", ".50", ".75"]

    var body: some View {
        VStack(spacing: 8) {
            if hasActiveSelection {
                contextHeader
                if isEditable {
                    keypadBody
                } else {
                    nonEditableNotice
                }
            } else {
                emptySelectionPrompt
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NotebookGridStyle.gridLine, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
            radius: 12,
            x: 0,
            y: 4
        )
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        HStack(spacing: 10) {
            // Student identity
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(EvaluationDesign.accent.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Text(studentInitials ?? "—")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(EvaluationDesign.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(studentName ?? "Alumno")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let studentIndex, let totalStudents {
                        Text("Alumno \(studentIndex) de \(totalStudents)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Column badge
            if let columnTitle {
                HStack(spacing: 5) {
                    Image(systemName: columnSystemIcon ?? "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(categoryTint ?? EvaluationDesign.accent)

                    Text(columnTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(categoryTint?.opacity(0.12) ?? Color.secondary.opacity(0.10))
                )
            }

            Spacer(minLength: 8)

            // Current Grade Preview
            HStack(spacing: 4) {
                Text("Nota:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(currentValue.isEmpty ? "—" : currentValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(currentValue.isEmpty ? Color.secondary : EvaluationDesign.accent)
                    .contentTransition(.numericText())
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(EvaluationDesign.accent.opacity(0.08))
            )

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cerrar teclado rápido")
            .accessibilityLabel("Cerrar teclado rápido")
        }
    }

    // MARK: - Keypad Body

    private var keypadBody: some View {
        VStack(spacing: 8) {
            // Row 1: Direct Number Keys (0 - 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(numberKeys, id: \.self) { number in
                        numberButton(number)
                    }
                }
                .padding(.vertical, 1)
            }

            // Row 2: Modifiers, Actions & Navigation
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Quick fractions (.25, .50, .75)
                    HStack(spacing: 4) {
                        ForEach(decimalFractions, id: \.self) { fraction in
                            modifierButton(fraction) {
                                onApplyDecimalFraction(fraction)
                            }
                        }
                    }

                    Divider().frame(height: 20)

                    // Step modifiers (+0.5, -0.5)
                    HStack(spacing: 4) {
                        modifierButton("+0.5") {
                            onApplyModifier(0.5)
                        }
                        modifierButton("-0.5") {
                            onApplyModifier(-0.5)
                        }
                    }

                    Divider().frame(height: 20)

                    // Pedagogical Status Keys
                    statusButton(label: "NP", title: "No Presentado", tint: Color.orange) {
                        onApplyGrade("NP")
                    }
                    statusButton(label: "Falta", title: "Falta Justificada/Injustificada", tint: Color.red) {
                        onApplyGrade("Falta")
                    }

                    Divider().frame(height: 20)

                    // Clear & Backspace
                    actionIconButton(systemImage: "delete.left", title: "Borrar carácter", action: onBackspace)
                    actionIconButton(systemImage: "trash", title: "Limpiar celda", action: onClear)

                    Divider().frame(height: 20)

                    // Navigation Arrows
                    HStack(spacing: 4) {
                        actionIconButton(
                            systemImage: "arrow.up",
                            title: "Alumno anterior",
                            isEnabled: canNavigatePrevious
                        ) {
                            onNavigate(.up)
                        }
                        actionIconButton(
                            systemImage: "arrow.down",
                            title: "Alumno siguiente",
                            isEnabled: canNavigateNext
                        ) {
                            onNavigate(.down)
                        }
                    }

                    Divider().frame(height: 20)

                    // Auto-advance Settings
                    autoAdvanceControlMenu
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Keypad Buttons

    private func numberButton(_ number: Int) -> some View {
        let isCurrent = currentValue == "\(number)"

        return Button {
            onApplyGrade("\(number)")
        } label: {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .frame(minWidth: 42, maxWidth: 58, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? EvaluationDesign.accent : Color.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isCurrent ? EvaluationDesign.accent : Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .accessibilityLabel("Nota \(number)")
    }

    private func modifierButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .accessibilityLabel("Modificador \(label)")
    }

    private func statusButton(label: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        let isCurrent = currentValue.localizedCaseInsensitiveCompare(label) == .orderedSame

        return Button(action: action) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(isCurrent ? Color.white : tint)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(
                    Capsule()
                        .fill(isCurrent ? tint : tint.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(isCurrent ? 1.0 : 0.25), lineWidth: 1)
                )
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    private func actionIconButton(
        systemImage: String,
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(isEnabled ? 0.08 : 0.03))
                )
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .disabled(!isEnabled)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - Auto-advance Control Menu

    private var autoAdvanceControlMenu: some View {
        Menu {
            Section("Modo de avance") {
                ForEach(NotebookKeypadAdvanceMode.allCases) { mode in
                    Button {
                        advanceMode = mode
                    } label: {
                        Label(mode.title, systemImage: mode.icon)
                    }
                }
            }

            Section("Dirección de avance") {
                ForEach(NotebookKeypadDirection.allCases) { dir in
                    Button {
                        direction = dir
                    } label: {
                        Label(dir.title, systemImage: dir.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: advanceMode.icon)
                    .font(.caption2.weight(.bold))
                Image(systemName: direction.systemImage)
                    .font(.caption2.weight(.bold))
                Text(advanceMode.title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configuración de avance automático")
    }

    // MARK: - Notices & Prompts

    private var nonEditableNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Esta columna se calcula automáticamente o no admite calificación numérica directa.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var emptySelectionPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap.fill")
                .font(.title3)
                .foregroundStyle(EvaluationDesign.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Dock táctil de calificación rápida activo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Toca una celda en el cuaderno o pulsa iniciar para calificar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Iniciar en primer alumno", action: onStartAtFirstStudent)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(EvaluationDesign.accent)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
