import SwiftUI
import MiGestorKit

// MARK: - Accesos Directos de la Estantería
enum NotebookShelfShortcut: String, CaseIterable, Identifiable {
    case notebook
    case seatingPlan
    case attendance
    case students

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notebook: return "Cuaderno"
        case .seatingPlan: return "Plano"
        case .attendance: return "Asistencia"
        case .students: return "Alumnado"
        }
    }

    var systemImage: String {
        switch self {
        case .notebook: return "tablecells"
        case .seatingPlan: return "rectangle.inset.filled.and.person.filled"
        case .attendance: return "calendar.badge.clock"
        case .students: return "person.2.fill"
        }
    }
}

// MARK: - Forma de la Cinta Marcapáginas
struct NotebookRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.40))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tema Cromático y Pedagógico de Portada
enum NotebookCoverTheme {
    static func theme(for schoolClass: SchoolClass) -> (primary: Color, accent: Color, lomo: Color, stageLabel: String, icon: String) {
        let nameLower = schoolClass.name.lowercased()
        let isBach = nameLower.contains("bach") || nameLower.contains("btx")
        let isPrimaria = nameLower.contains("prim") || nameLower.contains("pri")
        let isInfantil = nameLower.contains("inf")

        let stageLabel: String
        let primaryColor: Color
        let lomoColor: Color
        let accentColor: Color
        let iconName: String

        if isBach {
            if schoolClass.course == 1 {
                stageLabel = "1º BACH"
                primaryColor = Color(red: 0.72, green: 0.18, blue: 0.26) // Rubí
                lomoColor = Color(red: 0.50, green: 0.10, blue: 0.16)
                accentColor = Color(red: 0.95, green: 0.42, blue: 0.48)
            } else {
                stageLabel = "2º BACH"
                primaryColor = Color(red: 0.20, green: 0.24, blue: 0.58) // Azul marino
                lomoColor = Color(red: 0.12, green: 0.14, blue: 0.40)
                accentColor = Color(red: 0.45, green: 0.58, blue: 0.96)
            }
            iconName = "graduationcap.fill"
        } else if isPrimaria {
            stageLabel = "\(schoolClass.course)º PRIM"
            primaryColor = Color(red: 0.16, green: 0.58, blue: 0.72) // Turquesa
            lomoColor = Color(red: 0.08, green: 0.42, blue: 0.54)
            accentColor = Color(red: 0.40, green: 0.82, blue: 0.94)
            iconName = "backpack.fill"
        } else if isInfantil {
            stageLabel = "INFANTIL"
            primaryColor = Color(red: 0.88, green: 0.42, blue: 0.62) // Rosa
            lomoColor = Color(red: 0.68, green: 0.26, blue: 0.46)
            accentColor = Color(red: 0.98, green: 0.68, blue: 0.80)
            iconName = "paintpalette.fill"
        } else {
            // ESO por defecto (1º a 4º)
            switch schoolClass.course {
            case 1:
                stageLabel = "1º ESO"
                primaryColor = Color(red: 0.15, green: 0.42, blue: 0.82) // Azul Cobalto
                lomoColor = Color(red: 0.09, green: 0.28, blue: 0.60)
                accentColor = Color(red: 0.42, green: 0.72, blue: 0.98)
                iconName = "book.closed.fill"
            case 2:
                stageLabel = "2º ESO"
                primaryColor = Color(red: 0.14, green: 0.58, blue: 0.38) // Esmeralda
                lomoColor = Color(red: 0.08, green: 0.42, blue: 0.26)
                accentColor = Color(red: 0.38, green: 0.85, blue: 0.60)
                iconName = "leaf.fill"
            case 3:
                stageLabel = "3º ESO"
                primaryColor = Color(red: 0.48, green: 0.24, blue: 0.70) // Púrpura
                lomoColor = Color(red: 0.34, green: 0.14, blue: 0.52)
                accentColor = Color(red: 0.76, green: 0.52, blue: 0.95)
                iconName = "sparkles"
            case 4:
                stageLabel = "4º ESO"
                primaryColor = Color(red: 0.82, green: 0.44, blue: 0.14) // Ámbar Cálido
                lomoColor = Color(red: 0.62, green: 0.30, blue: 0.08)
                accentColor = Color(red: 0.98, green: 0.70, blue: 0.36)
                iconName = "flame.fill"
            default:
                stageLabel = "\(schoolClass.course)º"
                primaryColor = Color(red: 0.28, green: 0.36, blue: 0.48) // Pizarra
                lomoColor = Color(red: 0.18, green: 0.24, blue: 0.34)
                accentColor = Color(red: 0.54, green: 0.65, blue: 0.78)
                iconName = "folder.fill"
            }
        }

        let isEF = nameLower.contains("ef") || nameLower.contains("físic") || nameLower.contains("fisic") || nameLower.contains("educación física")
        let finalIcon = isEF ? "figure.run" : iconName

        return (primary: primaryColor, accent: accentColor, lomo: lomoColor, stageLabel: stageLabel, icon: finalIcon)
    }
}

// MARK: - Tarjeta de Portada de Libreta (NotebookClassCoverCard)
struct NotebookClassCoverCard: View {
    let schoolClass: SchoolClass
    let isSelected: Bool
    let subjectName: String?
    let studentCount: Int?
    let onSelect: () -> Void
    var onShortcut: ((NotebookShelfShortcut) -> Void)? = nil

    @State private var isHovering = false

    private var theme: (primary: Color, accent: Color, lomo: Color, stageLabel: String, icon: String) {
        NotebookCoverTheme.theme(for: schoolClass)
    }

    private var studentCountText: String {
        if let studentCount {
            return "\(studentCount) al."
        }
        return "— al."
    }

    private var plaqueBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Superficie principal de la libreta
            HStack(spacing: 0) {
                // Lomo de encuadernación lateral (Spine)
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [theme.lomo, theme.lomo.opacity(0.88)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    // Pespunte de costura vertical punteada
                    Rectangle()
                        .stroke(
                            Color.white.opacity(0.30),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3])
                        )
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
                .frame(width: 18)
                .overlay(
                    // Separador sutil con sombra entre lomo y portada
                    Rectangle()
                        .fill(Color.black.opacity(0.32))
                        .frame(width: 1),
                    alignment: .trailing
                )

                // Área frontal de la portada
                VStack(spacing: 6) {
                    Spacer(minLength: 4)

                    // Placa de título central en relieve (Embossed Plaque)
                    VStack(spacing: 3) {
                        // Píldora de etapa o curso
                        HStack(spacing: 4) {
                            Image(systemName: theme.icon)
                                .font(.system(size: 9, weight: .bold))
                            Text(theme.stageLabel)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(theme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(theme.primary.opacity(0.12))
                        )

                        // Nombre del grupo
                        Text(schoolClass.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)

                        // Asignatura asociada si existe
                        if let subject = subjectName, !subject.isEmpty {
                            Text(subject)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }

                        // Cápsula de alumnos integrada en la placa
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(studentCountText)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                        .padding(.top, 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(plaqueBackground.opacity(0.94))
                            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )

                    Spacer(minLength: 4)

                    // Banda inferior con accesos rápidos de un toque
                    if let onShortcut {
                        HStack(spacing: 6) {
                            shortcutIconButton(
                                icon: "tablecells",
                                tooltip: "Abrir Cuaderno"
                            ) {
                                onShortcut(.notebook)
                            }

                            shortcutIconButton(
                                icon: "rectangle.inset.filled.and.person.filled",
                                tooltip: "Abrir Plano de Clase"
                            ) {
                                onShortcut(.seatingPlan)
                            }

                            shortcutIconButton(
                                icon: "calendar.badge.clock",
                                tooltip: "Abrir Asistencia"
                            ) {
                                onShortcut(.attendance)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .frame(width: 156, height: 212)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [theme.primary, theme.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Brillo satinado superior
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? EvaluationDesign.accent : Color.white.opacity(0.20),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? EvaluationDesign.accent.opacity(0.40)
                    : Color.black.opacity(isHovering ? 0.22 : 0.15),
                radius: isSelected ? 12 : (isHovering ? 8 : 4),
                x: 0,
                y: isSelected ? 5 : (isHovering ? 4 : 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                AppleInteractionFeedback.play(.selection)
                onSelect()
            }

            // Cinta marcapáginas dorada de cuaderno activo
            if isSelected {
                ZStack(alignment: .top) {
                    NotebookRibbonShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.82, blue: 0.28),
                                    Color(red: 0.90, green: 0.68, blue: 0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 16, height: 28)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 2)

                    Capsule()
                        .fill(Color.white.opacity(0.40))
                        .frame(width: 2, height: 16)
                        .padding(.top, 2)
                }
                .offset(x: -16, y: -2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovering)
        #if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
        #endif
        .accessibilityLabel("Cuaderno de \(schoolClass.name), \(theme.stageLabel)")
    }

    private func shortcutIconButton(
        icon: String,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppleInteractionFeedback.play(.selection)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                )
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .help(tooltip)
    }
}

// MARK: - Estantería y Selector Visual de Cuadernos (NotebookClassPickerPopover 2.0)
struct NotebookClassPickerPopover: View {
    let classes: [SchoolClass]
    let selectedClassId: Int64?
    var bridge: KmpBridge? = nil
    let onSelectClass: (Int64) -> Void
    var onSelectShortcut: ((Int64, NotebookShelfShortcut) -> Void)? = nil
    let onClose: () -> Void

    @State private var selectedCourseFilter: Int32? = nil
    @State private var searchText = ""
    @State private var studentCounts: [Int64: Int] = [:]

    private var availableCourses: [Int32] {
        Array(Set(classes.map(\.course))).sorted()
    }

    private var filteredClasses: [SchoolClass] {
        classes.filter { item in
            let matchesCourse = selectedCourseFilter == nil || item.course == selectedCourseFilter
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            return matchesCourse && matchesSearch
        }
    }

    private func coursePillLabel(for course: Int32) -> String {
        let matchingClasses = classes.filter { $0.course == course }
        let hasBach = matchingClasses.contains {
            let name = $0.name.lowercased()
            return name.contains("bach") || name.contains("btx")
        }
        if hasBach {
            return "\(course)º Bach"
        }
        let hasPrimaria = matchingClasses.contains {
            let name = $0.name.lowercased()
            return name.contains("prim") || name.contains("pri")
        }
        if hasPrimaria {
            return "\(course)º Prim"
        }
        return "\(course)º ESO"
    }

    private func subjectName(for schoolClass: SchoolClass) -> String? {
        guard let subjectId = schoolClass.subjectId?.int64Value else { return nil }
        return bridge?.subjects.first(where: { $0.id == subjectId })?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cabecera de la Estantería
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(NotebookStyle.primaryTint)
                    .frame(width: 38, height: 38)
                    .background(NotebookStyle.primaryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Estantería de Cuadernos")
                        .font(.headline.weight(.bold))
                    Text("\(classes.count) clases disponibles · Toca para abrir")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar estantería")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // Barra de filtros por curso y buscador
            VStack(spacing: 8) {
                if availableCourses.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            courseFilterChip(title: "Todos", course: nil)

                            ForEach(availableCourses, id: \.self) { course in
                                courseFilterChip(title: coursePillLabel(for: course), course: course)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if classes.count > 5 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Buscar clase o grupo...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 12)

            Divider()

            // Cuadrícula de Cuadernos
            ScrollView {
                if filteredClasses.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("Sin cuadernos que coincidan")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Prueba con otro filtro o término de búsqueda.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 152, maximum: 175), spacing: 16)],
                        spacing: 18
                    ) {
                        ForEach(filteredClasses, id: \.id) { schoolClass in
                            NotebookClassCoverCard(
                                schoolClass: schoolClass,
                                isSelected: selectedClassId == schoolClass.id,
                                subjectName: subjectName(for: schoolClass),
                                studentCount: studentCounts[schoolClass.id],
                                onSelect: {
                                    onSelectClass(schoolClass.id)
                                    onClose()
                                },
                                onShortcut: onSelectShortcut != nil ? { shortcut in
                                    onSelectShortcut?(schoolClass.id, shortcut)
                                    onClose()
                                } : nil
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 620)
        .frame(minHeight: 460, idealHeight: 520, maxHeight: 580)
        .background(popoverBackground)
        .task {
            await loadStudentCounts()
        }
    }

    private var popoverBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    private func courseFilterChip(title: String, course: Int32?) -> some View {
        let isSelected = selectedCourseFilter == course
        return Button {
            AppleInteractionFeedback.play(.selection)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedCourseFilter = course
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? EvaluationDesign.accent : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadStudentCounts() async {
        guard let bridge else { return }
        for schoolClass in classes {
            if let students = try? await bridge.students(forClassId: schoolClass.id) {
                studentCounts[schoolClass.id] = students.count
            }
        }
    }
}

// MARK: - Simple Scrollable Class List Popover (Compatibilidad con vistas heredadas)
struct SimpleClassPickerPopover: View {
    let classes: [SchoolClass]
    let selectedClassId: Int64?
    let onSelectClass: (Int64) -> Void
    let onClose: () -> Void

    var body: some View {
        NotebookClassPickerPopover(
            classes: classes,
            selectedClassId: selectedClassId,
            onSelectClass: onSelectClass,
            onClose: onClose
        )
    }
}

