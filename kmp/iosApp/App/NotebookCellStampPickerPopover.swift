import SwiftUI
import MiGestorKit

struct NotebookCellStampPickerPopover: View {
    let studentName: String
    let studentInitials: String
    let studentIndex: Int?
    let totalStudents: Int?
    let columnTitle: String
    let columnSystemIcon: String?
    let categoryTint: Color?
    let currentValueText: String?
    let initialIcon: String?
    let initialNote: String?
    let canAdvance: Bool
    let onSave: (String?, String?) -> Void
    let onSaveAndAdvance: (String?, String?) -> Void
    let onClose: () -> Void

    @State private var selectedCategory: NotebookStampCategory = .excellence
    @State private var selectedStampId: String? = nil
    @State private var feedbackNote: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNoteFocused: Bool

    init(
        studentName: String,
        studentInitials: String,
        studentIndex: Int? = nil,
        totalStudents: Int? = nil,
        columnTitle: String,
        columnSystemIcon: String? = nil,
        categoryTint: Color? = nil,
        currentValueText: String? = nil,
        initialIcon: String? = nil,
        initialNote: String? = nil,
        canAdvance: Bool = false,
        onSave: @escaping (String?, String?) -> Void,
        onSaveAndAdvance: @escaping (String?, String?) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.studentName = studentName
        self.studentInitials = studentInitials
        self.studentIndex = studentIndex
        self.totalStudents = totalStudents
        self.columnTitle = columnTitle
        self.columnSystemIcon = columnSystemIcon
        self.categoryTint = categoryTint
        self.currentValueText = currentValueText
        self.initialIcon = initialIcon
        self.initialNote = initialNote
        self.canAdvance = canAdvance
        self.onSave = onSave
        self.onSaveAndAdvance = onSaveAndAdvance
        self.onClose = onClose

        _selectedStampId = State(initialValue: initialIcon)
        _feedbackNote = State(initialValue: initialNote ?? "")

        if let initialIcon, let existing = NotebookCellStampCatalog.item(for: initialIcon) {
            _selectedCategory = State(initialValue: existing.category)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header del alumno y columna
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider()

                // Contenido desplazable
                ScrollView {
                    VStack(spacing: 16) {
                        // Selector segmentado de categorías pedagógicas
                        categoryPicker
                            .padding(.top, 4)

                        // Cuadrícula de sellos
                        stampsGrid

                        // Nota de feedback formativo
                        noteInputSection
                    }
                    .padding(16)
                }

                Divider()

                // Barra inferior de acciones
                actionsFooter
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(sheetBackground)
            .navigationTitle("Sello Formativo")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 580)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(EvaluationDesign.accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Text(studentInitials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(EvaluationDesign.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(studentName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let studentIndex, let totalStudents {
                        Text("Alumno \(studentIndex) de \(totalStudents)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let currentValueText, !currentValueText.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Nota: \(currentValueText)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                    }
                }
            }

            Spacer(minLength: 8)

            // Columna activa
            HStack(spacing: 5) {
                Image(systemName: columnSystemIcon ?? "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(categoryTint ?? EvaluationDesign.accent)

                Text(columnTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(categoryTint?.opacity(0.12) ?? Color.secondary.opacity(0.10))
            )
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotebookStampCategory.allCases) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.systemIcon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? category.tintColor.opacity(0.20) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? category.tintColor : Color.clear, lineWidth: 1.5)
                        )
                        .foregroundStyle(isSelected ? category.tintColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var stampsGrid: some View {
        let stamps = NotebookCellStampCatalog.stamps(for: selectedCategory)
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(stamps) { stamp in
                let isSelected = selectedStampId == stamp.id || selectedStampId == stamp.symbol
                Button {
                    if isSelected {
                        selectedStampId = nil
                    } else {
                        selectedStampId = stamp.id
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .fill(stamp.tintColor.opacity(isSelected ? 0.28 : 0.12))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? stamp.tintColor : Color.clear, lineWidth: 2)
                                )

                            Image(systemName: stamp.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(stamp.tintColor)
                                .frame(width: 44, height: 44)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .background(Circle().fill(Color.white))
                                    .offset(x: 4, y: -4)
                            }
                        }

                        Text(stamp.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(stamp.meaningDescription)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(height: 22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? stamp.tintColor.opacity(0.08) : cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? stamp.tintColor.opacity(0.6) : NotebookGridStyle.gridLine, lineWidth: isSelected ? 1.5 : 0.8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(stamp.meaningDescription)
            }
        }
    }

    private var noteInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Observación formativa", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !feedbackNote.isEmpty {
                    Button("Borrar nota") {
                        feedbackNote = ""
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            TextField("Ej. Gran dominio de la técnica; revisar postura en saltos…", text: $feedbackNote, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isNoteFocused)
                .lineLimit(2...4)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(NotebookGridStyle.gridLine, lineWidth: 1)
                )
        }
    }

    private var actionsFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Quitar sello
                if initialIcon != nil || selectedStampId != nil {
                    Button(role: .destructive) {
                        selectedStampId = nil
                        feedbackNote = ""
                        onSave(nil, nil)
                        onClose()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("Quitar sello")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }

                Spacer()

                // Guardar sello
                Button {
                    onSave(selectedStampId, feedbackNote.trimmingCharacters(in: .whitespacesAndNewlines))
                    onClose()
                } label: {
                    Text("Guardar")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
            }

            // Botón de avance masivo
            if canAdvance {
                Button {
                    onSaveAndAdvance(selectedStampId, feedbackNote.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Guardar y siguiente alumno (↓)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(EvaluationDesign.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(EvaluationDesign.accent.opacity(0.35), lineWidth: 1)
                    )
                    .foregroundStyle(EvaluationDesign.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sheetBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    private var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
