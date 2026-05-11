import SwiftUI
import AppKit
import MiGestorKit

enum MacStudentsPresentation {
    case full
    case content
    case inspector
}

struct MacStudentsView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    var presentation: MacStudentsPresentation = .full
    var reloadToken: Int = 0

    @State private var rows: [KmpBridge.MacStudentRowSnapshot] = []
    @State private var profile: KmpBridge.StudentProfileSnapshot?
    @State private var searchText = ""
    @State private var trackingFilter = "todos"
    @State private var workGroupFilter = "Todos"
    @State private var quickNoteText = ""
    @State private var isLoadingRows = false
    @State private var isSavingNote = false
    @State private var errorMessage: String?
    @State private var riskPack: TeachingEvidencePack?
    @FocusState private var isSearchFocused: Bool

    private var filteredRows: [KmpBridge.MacStudentRowSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            let matchesQuery = query.isEmpty ||
                row.student.fullName.localizedCaseInsensitiveContains(query) ||
                row.className.localizedCaseInsensitiveContains(query)
            let matchesTracking: Bool = {
                switch trackingFilter {
                case "seguimiento":
                    return row.isFollowUp
                case "lesionados":
                    return row.isInjured
                default:
                    return true
                }
            }()
            let matchesGroup = workGroupFilter == "Todos" || row.workGroupName == workGroupFilter
            return matchesQuery && matchesTracking && matchesGroup
        }
    }

    private var selectedRow: KmpBridge.MacStudentRowSnapshot? {
        guard let selectedStudentId else { return filteredRows.first }
        return rows.first(where: { $0.id == selectedStudentId }) ?? filteredRows.first
    }

    private var workGroupOptions: [String] {
        ["Todos"] + Array(Set(rows.map(\.workGroupName))).sorted()
    }

    var body: some View {
        Group {
            switch presentation {
            case .full:
                HSplitView {
                    studentsFilters
                        .frame(minWidth: 250, idealWidth: 270, maxWidth: 310)
                    studentsList
                        .frame(minWidth: 640)
                    studentInspector
                        .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)
                }
            case .content:
                HSplitView {
                    studentsFilters
                        .frame(minWidth: 250, idealWidth: 270, maxWidth: 310)
                    studentsList
                        .frame(minWidth: 560)
                }
            case .inspector:
                studentInspector
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430, maxHeight: .infinity)
            }
        }
        .background(MacAppStyle.pageBackground)
        .task {
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId
            }
            await reloadRows()
        }
        .task(id: selectedClassId) {
            await bridge.selectStudentsClass(classId: selectedClassId)
            await reloadRows()
        }
        .task(id: reloadToken) {
            guard reloadToken > 0 else { return }
            await reloadRows()
        }
        .appOnChange(of: selectedStudentId) { _, _ in
            Task { await reloadProfile() }
        }
        .appOnChange(of: filteredRows.map(\.id)) { _, visibleIds in
            guard !visibleIds.isEmpty else {
                selectedStudentId = nil
                return
            }
            if selectedStudentId == nil || !visibleIds.contains(selectedStudentId ?? -1) {
                selectedStudentId = visibleIds.first
            }
        }
        .onExitCommand {
            if !searchText.isEmpty {
                searchText = ""
            }
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)

            Button("") {
                openSelectedInNotebook()
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
        }
    }

    private var studentsList: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            studentsHeader
            studentsTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var studentsFilters: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Filtros")
                    .font(.title3.weight(.semibold))
                Text("\(filteredRows.count) de \(rows.count) alumnos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Clase", selection: $selectedClassId) {
                    Text("Todas").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Busqueda")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nombre o clase", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Seguimiento")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Seguimiento", selection: $trackingFilter) {
                    Text("Todos").tag("todos")
                    Text("Seguimiento").tag("seguimiento")
                    Text("Lesionados").tag("lesionados")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Grupo de trabajo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Grupo de trabajo", selection: $workGroupFilter) {
                    ForEach(workGroupOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
        .background(MacAppStyle.cardBackground)
    }

    private var studentsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Alumnado")
                    .font(MacAppStyle.pageTitle)
                Text("Tabla densa con seguimiento, asistencia, media e incidencias.")
                    .font(MacAppStyle.bodyText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingRows {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await reloadRows() }
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var studentsTable: some View {
        if rows.isEmpty && !isLoadingRows {
            ContentUnavailableView(
                "Sin alumnado",
                systemImage: "person.3",
                description: Text("No hay alumnos disponibles para la clase seleccionada.")
            )
        } else if filteredRows.isEmpty {
            ContentUnavailableView(
                "Sin coincidencias",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Ajusta la busqueda o los filtros de seguimiento.")
            )
        } else {
            Table(filteredRows, selection: $selectedStudentId) {
                TableColumn("Nombre") { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.system(size: 13, weight: .semibold))
                        if row.student.email?.isEmpty == false {
                            Text(row.student.email ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Clase") { row in
                    Text(row.className)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Seguimiento") { row in
                    MacStatusPill(
                        label: row.followUpLabel,
                        isActive: row.isFollowUp,
                        tint: row.isInjured ? MacAppStyle.warningTint : (row.isFollowUp ? MacAppStyle.infoTint : MacAppStyle.successTint)
                    )
                }
                .width(min: 112, ideal: 130)
                TableColumn("Asistencia reciente") { row in
                    Text(row.recentAttendanceLabel)
                        .font(.system(size: 12, weight: .medium))
                }
                .width(min: 130, ideal: 150)
                TableColumn("Media") { row in
                    Text(row.averageText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 82)
                TableColumn("Incidencias") { row in
                    Text("\(row.incidentCount)")
                        .font(.system(size: 12, weight: row.incidentCount > 0 ? .bold : .regular))
                        .foregroundStyle(row.incidentCount > 0 ? .red : .secondary)
                        .monospacedDigit()
                }
                .width(min: 82, ideal: 96)
                TableColumn("Última observación") { row in
                    Text(row.lastObservationText)
                        .font(.system(size: 12))
                        .foregroundStyle(row.lastObservationText == "Sin observaciones" ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private var studentInspector: some View {
        if let selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ficha del alumno")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedRow.student.fullName)
                            .font(.title2.weight(.semibold))
                        Text(selectedRow.className)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        MacStatusPill(
                            label: selectedRow.followUpLabel,
                            isActive: selectedRow.isFollowUp,
                            tint: selectedRow.isInjured ? MacAppStyle.warningTint : MacAppStyle.infoTint
                        )
                        MacStatusPill(
                            label: selectedRow.workGroupName,
                            isActive: selectedRow.workGroupName != "Sin grupo",
                            tint: MacAppStyle.successTint
                        )
                    }

                    if let profile {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MacMetricCard(label: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                            MacMetricCard(label: "Media", value: IosFormatting.decimal(profile.averageScore), systemImage: "sum")
                            MacMetricCard(label: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble")
                            MacMetricCard(label: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                        }

                        if let riskPack, let level = riskPack.riskLevel {
                            inspectorSection("Radar de riesgo") {
                                VStack(alignment: .leading, spacing: 10) {
                                    MacStatusPill(
                                        label: level.title,
                                        isActive: level != .seguimientoNormal,
                                        tint: level == .atencionPrioritaria ? MacAppStyle.dangerTint : (level == .atencionPuntual ? MacAppStyle.warningTint : MacAppStyle.successTint)
                                    )
                                    Text(riskPack.summary)
                                        .font(.system(size: 13, weight: .medium))
                                    ForEach(Array(riskPack.warningTexts.prefix(3)), id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(riskPack.recommendedActionTexts.prefix(2)), id: \.self) { action in
                                        Label(action, systemImage: "arrowshape.right.circle")
                                            .font(.caption)
                                    }
                                }
                            }
                        }

                        inspectorSection("Notas rápidas") {
                            TextEditor(text: $quickNoteText)
                                .frame(minHeight: 86)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            HStack {
                                Button {
                                    Task { await saveQuickNote() }
                                } label: {
                                    Label(isSavingNote ? "Guardando…" : "Guardar nota", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNote)
                                Spacer()
                            }
                        }

                        inspectorSection("Historial de incidencias") {
                            if profile.incidents.isEmpty {
                                Text("Sin incidencias registradas.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(profile.incidents.prefix(5), id: \.id) { incident in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(incident.title)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(incident.severity.capitalized)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(incident.detail ?? "Sin detalle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }

                        inspectorSection("Accesos") {
                            VStack(spacing: 8) {
                                Button {
                                    openSelectedInNotebook()
                                } label: {
                                    Label("Abrir en cuaderno", systemImage: "tablecells")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    onOpenModule(.attendance, selectedClassId, selectedRow.id)
                                } label: {
                                    Label("Abrir asistencia", systemImage: "checklist.checked")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    onOpenModule(.reports, selectedClassId, selectedRow.id)
                                } label: {
                                    Label("Abrir informes", systemImage: "doc.text")
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ProgressView("Cargando ficha…")
                    }
                }
                .padding(MacAppStyle.pagePadding)
            }
            .background(MacAppStyle.cardBackground)
        } else {
            VStack {
                ContentUnavailableView(
                    "Selecciona un alumno",
                    systemImage: "person.3",
                    description: Text("La ficha reunira notas, incidencias y accesos cruzados.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(MacAppStyle.cardBackground)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            content()
        }
    }

    @MainActor
    private func reloadRows() async {
        isLoadingRows = true
        errorMessage = nil
        defer { isLoadingRows = false }
        do {
            rows = try await bridge.loadMacStudentRows(classId: selectedClassId)
            if let selectedStudentId, rows.contains(where: { $0.id == selectedStudentId }) {
                await reloadProfile()
            } else {
                selectedStudentId = filteredRows.first?.id
                await reloadProfile()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reloadProfile() async {
        guard let selectedStudentId else {
            profile = nil
            riskPack = nil
            return
        }
        profile = try? await bridge.loadStudentProfile(studentId: selectedStudentId, classId: selectedClassId)
        riskPack = try? await StudentRiskEvidenceBuilder.build(bridge: bridge, classId: selectedClassId, studentId: selectedStudentId)
    }

    @MainActor
    private func saveQuickNote() async {
        guard let selectedStudentId else { return }
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            try await bridge.saveQuickStudentNote(studentId: selectedStudentId, classId: selectedClassId, note: quickNoteText)
            quickNoteText = ""
            await reloadRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSelectedInNotebook() {
        guard let selectedStudentId else { return }
        onOpenModule(.notebook, selectedClassId, selectedStudentId)
    }
}

