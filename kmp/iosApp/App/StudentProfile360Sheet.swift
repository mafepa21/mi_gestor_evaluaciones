import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pestañas de la Ficha 360º

enum StudentProfile360Tab: String, CaseIterable, Identifiable {
    case academic = "academic"
    case attendance = "attendance"
    case tutoring = "tutoring"
    case diversityHealth = "diversityHealth"
    case aiInsights = "aiInsights"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .academic: return "Académico"
        case .attendance: return "Asistencia"
        case .tutoring: return "Tutoría"
        case .diversityHealth: return "Salud y Apoyo"
        case .aiInsights: return "Insights IA"
        }
    }

    var systemIcon: String {
        switch self {
        case .academic: return "graduationcap.fill"
        case .attendance: return "calendar.badge.clock"
        case .tutoring: return "person.2.fill"
        case .diversityHealth: return "heart.text.square.fill"
        case .aiInsights: return "sparkles"
        }
    }
}

// MARK: - Componente Principal: Ficha 360º del Alumno

struct StudentProfile360Sheet: View {
    let studentId: Int64
    let classId: Int64?
    let allStudents: [Student]
    let notebookColumns: [NotebookColumnDefinition]
    let studentRow: NotebookTableRow?
    let classAverageScore: Double?
    let bridge: KmpBridge
    let onNavigateToStudent: (Int64) -> Void
    let onClose: () -> Void

    @State private var selectedTab: StudentProfile360Tab = .academic
    @State private var profile: KmpBridge.StudentProfileSnapshot? = nil
    @State private var supportMeasures: [SupportMeasureRow] = []
    @State private var tutoringSessions: [TutoringSessionRow] = []
    @State private var educationalInsight: StudentInsightDraft? = nil
    @State private var isLoading = true
    @State private var isGeneratingInsight = false
    @State private var isTogglingInjury = false
    @State private var showCopiedAlert = false
    @State private var showTutoringSheet = false
    @State private var orchestrator = AppleAIOrchestrator()
    @Environment(\.colorScheme) private var colorScheme

    private var currentStudentIndex: Int? {
        allStudents.firstIndex(where: { $0.id == studentId })
    }

    private var canNavigatePrevious: Bool {
        guard let index = currentStudentIndex else { return false }
        return index > 0
    }

    private var canNavigateNext: Bool {
        guard let index = currentStudentIndex else { return false }
        return index < allStudents.count - 1
    }

    private var currentStudent: Student? {
        allStudents.first(where: { $0.id == studentId }) ?? profile?.student
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Cabecera de identidad y carrusel de navegación
                headerIdentityBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                Divider()

                // Barra segmentada de pestañas 360º
                tabPickerBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                Divider()

                // Contenido dinámico por pestaña
                if isLoading && profile == nil {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Cargando ficha 360º del alumno…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .academic:
                                academicSection
                            case .attendance:
                                attendanceSection
                            case .tutoring:
                                tutoringSection
                            case .diversityHealth:
                                diversityHealthSection
                            case .aiInsights:
                                aiInsightsSection
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(sheetBackground)
            .navigationTitle("Ficha 360º del Alumno")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onClose)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copy360Summary()
                    } label: {
                        Label("Copiar resumen", systemImage: showCopiedAlert ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(showCopiedAlert ? Color.green : Color.accentColor)
                    }
                    .help("Copiar informe estructurado al portapapeles")
                }
            }
        }
        .task(id: studentId) {
            educationalInsight = nil
            await loadProfileData()
        }
        .sheet(isPresented: $showTutoringSheet) {
            TutoringSessionFormSheet(studentId: studentId) {
                Task { await loadProfileData() }
            }
            .environmentObject(bridge)
        }
        #if os(macOS)
        .frame(width: 680, height: 740)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Header Identity Bar

    private var headerIdentityBar: some View {
        HStack(spacing: 14) {
            // Avatar con iniciales y anillo de estado
            ZStack {
                let isInjured = currentStudent?.isInjured ?? false
                let statusColor: Color = isInjured ? Color.red : (hasAlerts ? Color.orange : Color.green)

                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.6), lineWidth: 2)
                    )

                Text(studentInitials)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
            }

            // Datos del alumno
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(currentStudent?.fullName ?? "Alumno")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if currentStudent?.isInjured == true {
                        HStack(spacing: 3) {
                            Image(systemName: "bandage.fill")
                            Text("Lesionado")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                    }
                }

                HStack(spacing: 8) {
                    Text(profile?.schoolClass?.name ?? "Grupo activo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let index = currentStudentIndex {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("Alumno \(index + 1) de \(allStudents.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let cleanEmail = currentStudent?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !cleanEmail.isEmpty,
                       let emailUrl = URL(string: "mailto:\(cleanEmail)") ?? URL(string: "mailto:\(cleanEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Link(destination: emailUrl) {
                            HStack(spacing: 3) {
                                Image(systemName: "envelope.fill")
                                Text(cleanEmail)
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            // Controles de Carrusel (‹ Alumno anterior | Alumno siguiente ›)
            HStack(spacing: 8) {
                Button {
                    navigatePrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(NotebookGridStyle.gridLine, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigatePrevious)
                .opacity(canNavigatePrevious ? 1.0 : 0.4)
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .help("Alumno anterior (⌘←)")

                Button {
                    navigateNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(NotebookGridStyle.gridLine, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigateNext)
                .opacity(canNavigateNext ? 1.0 : 0.4)
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .help("Alumno siguiente (⌘→)")
            }
        }
    }

    private var tabPickerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudentProfile360Tab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.systemIcon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 1. Académico & Cuaderno

    private var academicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tarjetas métricas superiores
            HStack(spacing: 12) {
                // Media actual del alumno
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nota media actual")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    let score = resolvedAverageScore
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(IosFormatting.decimal(from: score))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeBandColor(for: score))

                        Text("/ 10")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(lomloeGradeText(for: score))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(gradeBandColor(for: score).opacity(0.14))
                            .foregroundStyle(gradeBandColor(for: score))
                            .clipShape(Capsule())
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))

                // Comparativa con la clase
                if let classAvg = classAverageScore {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Media de la clase")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(IosFormatting.decimal(from: classAvg))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            let diff = resolvedAverageScore - classAvg
                            let isPositive = diff >= 0
                            HStack(spacing: 2) {
                                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                Text(String(format: "%@%.1f", isPositive ? "+" : "", diff).replacingOccurrences(of: ".", with: ","))
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isPositive ? Color.green : Color.orange)
                        }

                        // Barra comparativa visual
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * CGFloat(classAvg / 10.0))), height: 6)

                                Capsule()
                                    .fill(gradeBandColor(for: resolvedAverageScore))
                                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * CGFloat(resolvedAverageScore / 10.0))), height: 6)
                            }
                        }
                        .frame(height: 8)
                        .padding(.top, 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
                }
            }

            // Colección de Sellos Formativos recibidos
            let stamps = studentStamps
            if !stamps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Sellos formativos recibidos (\(stamps.count))", systemImage: "seal.fill")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(stamps, id: \.columnId) { item in
                            HStack(spacing: 10) {
                                NotebookCellStampBadge(
                                    iconValue: item.icon,
                                    note: item.note,
                                    attachmentCount: 0,
                                    fallbackTint: Color.accentColor,
                                    studentName: currentStudent?.fullName
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.columnTitle)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if let note = item.note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 0.8))
                        }
                    }
                }
                .padding(16)
                .background(cardBackground.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
            }

            // Desglose de Calificaciones del Cuaderno
            VStack(alignment: .leading, spacing: 12) {
                Label("Calificaciones por Columna", systemImage: "tablecells")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if academicColumns.isEmpty {
                    Text("No hay calificaciones registradas en este grupo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(academicColumns, id: \.column.id) { colItem in
                            HStack(spacing: 12) {
                                Image(systemName: columnSystemIcon(colItem.column))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 26, height: 26)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(colItem.column.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text(columnTypeBadge(colItem.column))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let stampIcon = colItem.stampIcon {
                                    NotebookCellStampBadge(
                                        iconValue: stampIcon,
                                        note: colItem.note,
                                        attachmentCount: 0,
                                        fallbackTint: Color.accentColor,
                                        studentName: currentStudent?.fullName
                                    )
                                }

                                Text(colItem.valueText.isEmpty ? "—" : colItem.valueText)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(colItem.valueText.isEmpty ? Color.secondary : gradeColor(for: colItem.valueText))
                                    .monospacedDigit()
                                    .frame(minWidth: 42, alignment: .trailing)
                            }
                            .padding(10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 0.8))
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
        }
    }

    // MARK: - 2. Asistencia & Puntualidad

    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Resumen grande
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasa de asistencia global")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        let rate = profile?.attendanceRate ?? 100
                        Text("\(rate)%")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(rate >= 90 ? Color.green : (rate >= 80 ? Color.orange : Color.red))

                        Text(rate >= 90 ? "Regular" : (rate >= 80 ? "Atención" : "Alerta absentismo"))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((rate >= 90 ? Color.green : (rate >= 80 ? Color.orange : Color.red)).opacity(0.14))
                            .foregroundStyle(rate >= 90 ? Color.green : (rate >= 80 ? Color.orange : Color.red))
                            .clipShape(Capsule())
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
            }

            // Historial reciente de asistencia
            VStack(alignment: .leading, spacing: 12) {
                Label("Registros recientes de asistencia", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.primary)

                let recent = profile?.recentAttendance ?? []
                if recent.isEmpty {
                    Text("No hay registros de asistencia en el historial reciente.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(recent, id: \.id) { att in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(attendanceColor(for: att.status).opacity(0.18))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: attendanceSystemIcon(for: att.status))
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(attendanceColor(for: att.status))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(att.status)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.primary)

                                    if !att.note.isEmpty {
                                        Text(att.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text(att.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 0.8))
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
        }
    }

    // MARK: - 3. Tutoría, Conducta & Observaciones

    private var tutoringSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Incidencias de conducta
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Incidencias disciplinarias", systemImage: "exclamationmark.bubble.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    let count = profile?.incidents.count ?? 0
                    Text(count == 0 ? "Sin incidencias" : "\(count) incidencia\(count == 1 ? "" : "s")")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((count == 0 ? Color.green : Color.red).opacity(0.14))
                        .foregroundStyle(count == 0 ? Color.green : Color.red)
                        .clipShape(Capsule())
                }

                let incidents = profile?.incidents ?? []
                if incidents.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.green)
                        Text("Conducta impecable: sin incidencias registradas.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(incidents, id: \.id) { inc in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.orange)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inc.title)
                                        .font(.subheadline.weight(.bold))
                                    if let detail = inc.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))

            // Entrevistas de Tutoría con Familias
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Entrevistas con Familias", systemImage: "person.2.wave.2.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        showTutoringSheet = true
                    } label: {
                        Label("Añadir", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                    .foregroundStyle(Color.accentColor)
                }

                if tutoringSessions.isEmpty {
                    Text("No hay entrevistas de tutoría registradas con la familia.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(tutoringSessions) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: session.channel.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    Text(session.dateDisplay)
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(session.channel.displayName)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                if !session.topics.isEmpty {
                                    Text("Temas: \(session.topics)")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }

                                if !session.agreements.isEmpty {
                                    Text("Acuerdos: \(session.agreements)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
        }
    }

    // MARK: - 4. Diversidad & Salud (Educación Física)

    private var diversityHealthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tarjeta interactiva de Lesión / Aptitud Física
            let isInjured = currentStudent?.isInjured ?? false
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Aptitud y Salud en Educación Física", systemImage: "figure.run")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        toggleInjury()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isInjured ? "heart.fill" : "bandage")
                            Text(isInjured ? "Retirar lesión" : "Marcar lesión")
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isInjured ? Color.green.opacity(0.15) : Color.red.opacity(0.12))
                        .foregroundStyle(isInjured ? Color.green : Color.red)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                    .disabled(isTogglingInjury)
                }

                if isInjured {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.red)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Alumno marcado actualmente en seguimiento de lesión o limitación motriz.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Requiere adaptación de tareas prácticas y registro en actas de evaluación continua.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("Apto para la práctica física normal sin limitaciones declaradas.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))

            // Medidas de Apoyo a la Diversidad
            VStack(alignment: .leading, spacing: 12) {
                Label("Medidas de Apoyo Educativo (NEAE)", systemImage: "person.text.rectangle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if supportMeasures.isEmpty {
                    Text("Sin medidas de apoyo registradas.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(supportMeasures) { measure in
                            let title = "\(measure.level.displayName) · \(measure.measureType.displayName)"
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(title)
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(measure.isActive ? "Activa" : "Retirada")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((measure.isActive ? Color.indigo : Color.secondary).opacity(0.14))
                                        .foregroundStyle(measure.isActive ? Color.indigo : Color.secondary)
                                        .clipShape(Capsule())
                                }

                                if !measure.followUpNotes.isEmpty {
                                    Text(measure.followUpNotes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
        }
    }

    // MARK: - 5. Insights IA (Apple Intelligence)

    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Resumen de Apple Intelligence", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)

                    Spacer()

                    Button {
                        Task { await generateInsight() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Regenerar")
                        }
                        .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                if let insight = educationalInsight {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(insight.summary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        if !insight.recommendations.isEmpty {
                            Divider()
                            Text("Recomendaciones para tutoría:")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            ForEach(insight.recommendations, id: \.self) { rec in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    Text(rec)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.accentColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                } else if isGeneratingInsight {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Analizando perfil con Apple Intelligence local…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Evaluando notas, asistencia, incidencias y medidas de apoyo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    VStack(spacing: 12) {
                        Text("Pulsa «Generar análisis» para obtener un resumen pedagógico local de su evolución, alertas tempranas y puntos fuertes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            Task { await generateInsight() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "apple.intelligence")
                                Text("Generar análisis con IA local")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
            .padding(16)
            .background(cardBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NotebookGridStyle.gridLine, lineWidth: 1))
        }
    }

    // MARK: - Helpers & Data

    private var hasAlerts: Bool {
        (profile?.incidentCount ?? 0) > 0 || (profile?.attendanceRate ?? 100) < 85
    }

    private var studentInitials: String {
        let first = currentStudent?.firstName.prefix(1) ?? ""
        let last = currentStudent?.lastName.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    private var resolvedAverageScore: Double {
        if let avg = studentRow?.row.weightedAverage {
            return avg.doubleValue
        }
        return profile?.averageScore ?? 0.0
    }

    private struct StampItemDisplay {
        let columnId: String
        let columnTitle: String
        let icon: String
        let note: String?
    }

    private var studentStamps: [StampItemDisplay] {
        guard let studentRow else { return [] }
        var result: [StampItemDisplay] = []
        for cell in studentRow.row.persistedCells {
            let icon = cell.annotation?.icon ?? cell.iconValue
            if let icon, !icon.isEmpty {
                let colTitle = notebookColumns.first(where: { $0.id == cell.columnId })?.title ?? "Columna"
                result.append(StampItemDisplay(
                    columnId: cell.columnId,
                    columnTitle: colTitle,
                    icon: icon,
                    note: cell.annotation?.note
                ))
            }
        }
        return result
    }

    private struct ColumnAcademicDisplay {
        let column: NotebookColumnDefinition
        let valueText: String
        let stampIcon: String?
        let note: String?
    }

    private var academicColumns: [ColumnAcademicDisplay] {
        guard let studentRow else { return [] }
        return notebookColumns
            .filter { $0.isVisibleInGrid && $0.type != .attendance }
            .compactMap { col in
                let cell = studentRow.row.persistedCells.first(where: { $0.columnId == col.id })
                let val = cell?.displayValue ?? cell?.textValue ?? ""
                let stamp = cell?.annotation?.icon ?? cell?.iconValue
                let note = cell?.annotation?.note
                return ColumnAcademicDisplay(
                    column: col,
                    valueText: val,
                    stampIcon: stamp,
                    note: note
                )
            }
    }

    private func navigatePrevious() {
        guard let index = currentStudentIndex, index > 0 else { return }
        let prevStudent = allStudents[index - 1]
        onNavigateToStudent(prevStudent.id)
    }

    private func navigateNext() {
        guard let index = currentStudentIndex, index < allStudents.count - 1 else { return }
        let nextStudent = allStudents[index + 1]
        onNavigateToStudent(nextStudent.id)
    }

    private func toggleInjury() {
        guard let student = currentStudent, !isTogglingInjury else { return }
        isTogglingInjury = true
        Task { @MainActor in
            try? await bridge.updateStudentInjuryStatus(
                studentId: student.id,
                isInjured: !student.isInjured,
                classId: classId
            )
            await loadProfileData()
            isTogglingInjury = false
        }
    }

    private func loadProfileData() async {
        isLoading = true
        profile = try? await bridge.loadStudentProfile(studentId: studentId, classId: classId)
        supportMeasures = ((try? await bridge.supportMeasures(for: studentId)) ?? []).map(\.asRow)
        tutoringSessions = ((try? await bridge.tutoringSessions(for: studentId)) ?? []).map(\.asRow)
        isLoading = false
    }

    private func generateInsight() async {
        guard let profile, !isGeneratingInsight else { return }
        isGeneratingInsight = true
        defer { isGeneratingInsight = false }
        let avgVal = studentRow?.row.weightedAverage?.doubleValue ?? profile.averageScore
        let avgText = String(format: "%.1f", avgVal)
        let evidence = StudentInsightEvidence(
            studentId: profile.student.id,
            studentName: "\(profile.student.firstName) \(profile.student.lastName)",
            averageText: avgText,
            averageScore: avgVal,
            attendanceStatus: profile.latestAttendanceStatus,
            followUpCount: profile.followUpCount,
            incidentCount: profile.incidentCount,
            evidenceCount: profile.evidenceCount,
            competencyLabels: [],
            observations: [],
            rubricSummaries: [],
            averageExplanation: studentRow?.row.averageExplanation,
            trends: nil
        )
        do {
            let gen = try await orchestrator.generateWithTrace(
                capability: .studentInsight,
                input: .student(evidence),
                dataSource: "Ficha 360",
                includedEvidence: evidence.evidenceLines
            )
            if case .studentInsight(let draft) = gen.result {
                educationalInsight = draft
            }
        } catch { }
    }

    private func copy360Summary() {
        let name = currentStudent?.fullName ?? "Alumno"
        let group = profile?.schoolClass?.name ?? "Grupo"
        let avg = IosFormatting.decimal(from: resolvedAverageScore)
        let lomloe = lomloeGradeText(for: resolvedAverageScore)
        let attRate = profile?.attendanceRate ?? 100
        let incidents = profile?.incidents.count ?? 0

        let text = """
        ==================================================
        FICHA 360º DEL ALUMNO: \(name)
        Grupo: \(group) · Fecha: \(Date().formatted(date: .abbreviated, time: .omitted))
        ==================================================
        ACADÉMICO:
        - Nota media actual: \(avg) (\(lomloe))
        \(classAverageScore != nil ? "- Media de la clase: \(IosFormatting.decimal(from: classAverageScore!))" : "")
        - Calificaciones evaluadas: \(academicColumns.filter { !$0.valueText.isEmpty }.count)

        ASISTENCIA Y PUNTUALIDAD:
        - Tasa de asistencia global: \(attRate)%
        - Último estado registrado: \(profile?.latestAttendanceStatus ?? "Normal")

        TUTORÍA Y CONDUCTA:
        - Incidencias disciplinarias: \(incidents)
        - Entrevistas con familias: \(tutoringSessions.count)

        SALUD Y ATENCIÓN A LA DIVERSIDAD:
        - Aptitud física / Lesión: \(currentStudent?.isInjured == true ? "Lesión activa declarada" : "Disponible")
        - Medidas de apoyo activas: \(supportMeasures.filter(\.isActive).count)
        ==================================================
        """

        #if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        showCopiedAlert = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showCopiedAlert = false
        }
    }

    private func lomloeGradeText(for score: Double) -> String {
        switch score {
        case 9.0...10.0: return "Sobresaliente"
        case 7.0..<9.0: return "Notable"
        case 6.0..<7.0: return "Bien"
        case 5.0..<6.0: return "Suficiente"
        default: return "Insuficiente"
        }
    }

    private func gradeBandColor(for score: Double) -> Color {
        switch score {
        case 9.0...10.0: return Color(red: 0.14, green: 0.62, blue: 0.40)
        case 7.0..<9.0: return Color(red: 0.16, green: 0.46, blue: 0.88)
        case 6.0..<7.0: return Color(red: 0.16, green: 0.64, blue: 0.74)
        case 5.0..<6.0: return Color(red: 0.86, green: 0.52, blue: 0.16)
        default: return Color(red: 0.84, green: 0.24, blue: 0.28)
        }
    }

    private func gradeColor(for value: String) -> Color {
        let clean = value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if let score = Double(clean) {
            return gradeBandColor(for: score)
        }
        return .primary
    }

    private func attendanceColor(for status: String) -> Color {
        let up = status.uppercased()
        if up.contains("PRES") { return Color.green }
        if up.contains("RET") { return Color.orange }
        if up.contains("JUST") { return Color.blue }
        if up.contains("AUS") || up.contains("FALT") { return Color.red }
        return Color.secondary
    }

    private func attendanceSystemIcon(for status: String) -> String {
        let up = status.uppercased()
        if up.contains("PRES") { return "checkmark" }
        if up.contains("RET") { return "clock.badge.exclamationmark" }
        if up.contains("JUST") { return "checkmark.shield" }
        if up.contains("AUS") || up.contains("FALT") { return "xmark" }
        return "calendar"
    }

    private func columnSystemIcon(_ col: NotebookColumnDefinition) -> String {
        if let icon = col.iconName, !icon.isEmpty { return icon }
        switch col.type {
        case .rubric: return "sparkles"
        case .calculated: return "function"
        case .check: return "checkmark.square"
        default: return "doc.text"
        }
    }

    private func columnTypeBadge(_ col: NotebookColumnDefinition) -> String {
        switch col.type {
        case .rubric: return "Rúbrica"
        case .calculated: return "Fórmula"
        case .check: return "Lista de control"
        default: return "Numérica"
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
