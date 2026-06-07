import SwiftUI
import MiGestorKit

struct LibraryWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State var templates: [ConfigTemplate] = []
    @State var versions: [ConfigTemplateVersion] = []
    @State var selectedTemplateId: Int64?
    @State var selectedKindFilter = "Todas"
    @State var searchText = ""
    @AppStorage("teacher.enabledSubjectProfiles.v1")
    private var enabledSubjectProfilesRaw: String = TeacherSubjectProfile.general.rawValue

    var selectedTemplate: ConfigTemplate? {
        filteredTemplates.first(where: { $0.id == selectedTemplateId }) ?? templates.first(where: { $0.id == selectedTemplateId })
    }

    var availableKinds: [String] {
        ["Todas"] + Array(Set(templates.map { templateKindLabel($0.kind) })).sorted()
    }

    var filteredTemplates: [ConfigTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return templates.filter { template in
            let matchesKind = selectedKindFilter == "Todas" || templateKindLabel(template.kind) == selectedKindFilter
            let matchesQuery = query.isEmpty || template.name.lowercased().contains(query)
            return matchesKind && matchesQuery
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedTemplateVersions: [ConfigTemplateVersion] {
        versions.sorted { $0.versionNumber > $1.versionNumber }
    }

    var templateMetrics: (total: Int, kinds: Int, versions: Int) {
        (filteredTemplates.count, max(availableKinds.count - 1, 0), versions.count)
    }

    var subjectTemplates: [SubjectTemplateDescriptor] {
        SubjectTemplateRegistry.templates(for: TeacherSubjectProfile.decodeSet(enabledSubjectProfilesRaw))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar plantilla…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 10) {
                        Picker("Tipo", selection: $selectedKindFilter) {
                            ForEach(availableKinds, id: \.self) { kind in
                                Text(kind).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Activos", value: "\(templateMetrics.total)", tint: .blue)
                        WorkspaceCompactStat(title: "Tipos", value: "\(templateMetrics.kinds)", tint: .orange)
                        WorkspaceCompactStat(title: "Versiones", value: "\(templateMetrics.versions)", tint: .green)
                    }
                }
                .padding(16)

                List {
                    Section("Por asignatura") {
                        ForEach(subjectTemplates) { template in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(template.title, systemImage: template.systemImage)
                                    .font(.headline)
                                Text(template.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("Plantillas") {
                        ForEach(filteredTemplates, id: \.id) { template in
                            Button {
                                selectedTemplateId = template.id
                                Task { await reloadVersions(templateId: template.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name).font(.headline)
                                    Text(templateKindLabel(template.kind)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if let selectedTemplate {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkspaceInspectorHero(title: selectedTemplate.name, subtitle: templateKindLabel(selectedTemplate.kind))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Versiones", value: "\(versions.count)", systemImage: "square.stack.3d.up.fill")
                                WorkspaceMetricCard(
                                    title: "Última versión",
                                    value: selectedTemplateVersions.first.map { "v\($0.versionNumber)" } ?? "Sin histórico",
                                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                                )
                                WorkspaceMetricCard(
                                    title: "Ámbito",
                                    value: selectedClassId == nil ? "Global" : "Clase activa",
                                    systemImage: "rectangle.3.group"
                                )
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Uso recomendado")
                                    .font(.headline)
                                WorkspaceDetailBlock(title: "Tipo", content: templateUsageDescription(selectedTemplate.kind))
                                WorkspaceDetailBlock(title: "Clase activa", content: selectedClassId == nil ? "La plantilla se muestra sin una clase concreta seleccionada." : "Puedes reutilizar esta configuración desde el contexto actual del grupo.")
                            }

                            HStack(spacing: 12) {
                                Button(templatePrimaryActionTitle(selectedTemplate.kind)) {
                                    onOpenModule(templatePrimaryModule(selectedTemplate.kind), selectedClassId, nil)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Abrir biblioteca relacionada") {
                                    onOpenModule(.library, selectedClassId, nil)
                                }
                                .buttonStyle(.bordered)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Histórico")
                                    .font(.headline)
                                if selectedTemplateVersions.isEmpty {
                                    Text("Sin versiones registradas todavía.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(selectedTemplateVersions, id: \.id) { version in
                                        templateVersionCard(version)
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Biblioteca de configuración",
                        subtitle: "Aquí centralizamos plantillas de cuaderno, rúbricas y futuras configuraciones reutilizables."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reloadTemplates() }
        .appOnChange(of: selectedKindFilter) { _ in
            if selectedTemplateId == nil || !filteredTemplates.contains(where: { $0.id == selectedTemplateId }) {
                selectedTemplateId = filteredTemplates.first?.id
            }
        }
        .appOnChange(of: searchText) { _ in
            if selectedTemplateId == nil || !filteredTemplates.contains(where: { $0.id == selectedTemplateId }) {
                selectedTemplateId = filteredTemplates.first?.id
            }
        }
    }

    @MainActor
    func reloadTemplates() async {
        templates = (try? await bridge.loadTemplates()) ?? []
        if selectedTemplateId == nil {
            selectedTemplateId = filteredTemplates.first?.id
        }
        if let selectedTemplateId {
            await reloadVersions(templateId: selectedTemplateId)
        }
    }

    @MainActor
    func reloadVersions(templateId: Int64) async {
        versions = (try? await bridge.loadTemplateVersions(templateId: templateId)) ?? []
    }

    func templateKindLabel(_ kind: ConfigTemplateKind) -> String {
        switch kind {
        case .notebookColumns:
            return "Columnas de cuaderno"
        case .rubric:
            return "Rúbricas"
        case .unitTemplate:
            return "Unidades"
        case .classStructure:
            return "Estructura de clase"
        default:
            return kind.name
        }
    }

    func templateUsageDescription(_ kind: ConfigTemplateKind) -> String {
        switch kind {
        case .notebookColumns:
            return "Reutiliza configuraciones de columnas, pesos y estructura del cuaderno."
        case .rubric:
            return "Banco de valoración reutilizable para evaluación continua o EF."
        case .unitTemplate:
            return "Base para secuencias didácticas y sesiones derivadas."
        case .classStructure:
            return "Plantilla operativa para preparar grupos, pestañas y configuración docente."
        default:
            return "Plantilla reutilizable dentro de la biblioteca."
        }
    }

    func templatePrimaryModule(_ kind: ConfigTemplateKind) -> AppWorkspaceModule {
        switch kind {
        case .notebookColumns:
            return .notebook
        case .rubric:
            return .rubrics
        case .unitTemplate:
            return .diary
        case .classStructure:
            return .courses
        default:
            return .library
        }
    }

    func templatePrimaryActionTitle(_ kind: ConfigTemplateKind) -> String {
        switch kind {
        case .notebookColumns:
            return "Abrir cuaderno"
        case .rubric:
            return "Abrir rúbricas"
        case .unitTemplate:
            return "Abrir diario"
        case .classStructure:
            return "Abrir cursos"
        default:
            return "Abrir módulo"
        }
    }

    func templateVersionCard(_ version: ConfigTemplateVersion) -> some View {
        let background = appCardBackground(for: colorScheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Versión \(version.versionNumber)")
                .font(.subheadline.weight(.bold))
            Text(version.payloadJson)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EFIncidentsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State var incidents: [Incident] = []
    @State var searchText = ""
    @State var selectedFilter = "Todas"
    @State var selectedIncidentId: Int64?
    @State var metadata: [PEIncidentMetadata] = storedItems(forKey: peIncidentMetadataStorageKey, as: PEIncidentMetadata.self)
    @State var showingCreateSheet = false

    var availableFilters: [String] {
        ["Todas", "Lesión", "Seguridad", "Conducta", "Material", "Equipación", "Críticas"]
    }

    var selectedIncident: Incident? {
        filteredIncidents.first(where: { $0.id == selectedIncidentId }) ?? incidents.first(where: { $0.id == selectedIncidentId })
    }

    var selectedMetadata: PEIncidentMetadata? {
        guard let selectedIncidentId else { return nil }
        return metadata.first(where: { $0.id == selectedIncidentId })
    }

    var filteredIncidents: [Incident] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return incidents.filter { incident in
            let matchesFilter: Bool = {
                switch selectedFilter {
                case "Críticas":
                    return isCritical(incident)
                case "Todas":
                    return true
                default:
                    return incidentCategory(for: incident) == selectedFilter
                }
            }()

            let haystack = [
                incident.title,
                incident.detail ?? "",
                incident.severity
            ]
            .joined(separator: " ")
            .lowercased()

            return matchesFilter && (query.isEmpty || haystack.contains(query))
        }
        .sorted { lhs, rhs in
            lhs.date.epochSeconds > rhs.date.epochSeconds
        }
    }

    var metrics: (total: Int, critical: Int, followUp: Int) {
        (
            filteredIncidents.count,
            filteredIncidents.filter(isCritical).count,
            filteredIncidents.filter { $0.studentId != nil }.count
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar incidencia, detalle o severidad…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 10) {
                        Picker("Filtro", selection: $selectedFilter) {
                            ForEach(availableFilters, id: \.self) { filter in
                                Text(filter).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nueva incidencia", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Total", value: "\(metrics.total)", tint: .blue)
                        WorkspaceCompactStat(title: "Críticas", value: "\(metrics.critical)", tint: .pink)
                        WorkspaceCompactStat(title: "Con alumno", value: "\(metrics.followUp)", tint: .orange)
                    }
                }
                .padding(16)

                List(filteredIncidents, id: \.id) { incident in
                    Button {
                        selectedIncidentId = incident.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(incident.title)
                                    .font(.headline)
                                Spacer()
                                Text(incident.severity.capitalized)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(severityColor(incident.severity))
                            }
                            Text("\(incidentCategory(for: incident)) · \(incidentDateLabel(incident))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 380)

            Divider().opacity(0.2)

            Group {
                if let incident = selectedIncident {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(
                                title: incident.title,
                                subtitle: "\(incidentCategory(for: incident)) · \(incident.severity.capitalized)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(
                                    title: "Severidad",
                                    value: incident.severity.capitalized,
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                WorkspaceMetricCard(
                                    title: "Alumno",
                                    value: incidentStudentName(incident) ?? "Sin alumno",
                                    systemImage: "person.fill"
                                )
                                WorkspaceMetricCard(
                                    title: "Fecha",
                                    value: incidentDateLabel(incident),
                                    systemImage: "calendar"
                                )
                                WorkspaceMetricCard(
                                    title: "Estado",
                                    value: selectedMetadata?.workflowState.rawValue ?? "Abierta",
                                    systemImage: "flag.fill"
                                )
                            }

                            WorkspaceDetailBlock(
                                title: "Detalle",
                                content: fallback(incident.detail ?? "", empty: "Sin detalle adicional")
                            )

                            WorkspaceDetailBlock(
                                title: "Seguimiento",
                                content: fallback(selectedMetadata?.followUpNote ?? "", empty: "Sin notas de seguimiento todavía")
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Clasificación EF")
                                    .font(.headline)
                                WorkspaceFlowLayout(spacing: 10) {
                                    WorkspaceTag(text: selectedMetadata?.category ?? incidentCategory(for: incident), systemImage: categoryIcon(for: incident))
                                    if isCritical(incident) {
                                        WorkspaceTag(text: "Revisión prioritaria", systemImage: "flame.fill")
                                    }
                                    if incident.studentId != nil {
                                        WorkspaceTag(text: "Seguimiento individual", systemImage: "person.crop.circle.badge.checkmark")
                                    }
                                    WorkspaceTag(text: selectedMetadata?.workflowState.rawValue ?? "Abierta", systemImage: "flag.fill")
                                }
                            }

                            if let incidentId = selectedIncidentId {
                                let activeWorkflowState = selectedMetadata?.workflowState ?? .open
                                HStack(spacing: 10) {
                                    workflowButton(title: PEIncidentWorkflowState.open.rawValue, incidentId: incidentId, targetState: .open, activeState: activeWorkflowState)
                                    workflowButton(title: PEIncidentWorkflowState.followUp.rawValue, incidentId: incidentId, targetState: .followUp, activeState: activeWorkflowState)
                                    workflowButton(title: PEIncidentWorkflowState.closed.rawValue, incidentId: incidentId, targetState: .closed, activeState: activeWorkflowState)
                                }
                            }

                            HStack(spacing: 12) {
                                if let studentId = incident.studentId?.int64Value {
                                    Button("Abrir alumno") {
                                        onOpenModule(.students, selectedClassId, studentId)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                Button("Abrir diario") {
                                    onOpenModule(.diary, selectedClassId, incident.studentId?.int64Value)
                                }
                                .buttonStyle(.bordered)

                                Button("Abrir asistencia") {
                                    onOpenModule(.attendance, selectedClassId, incident.studentId?.int64Value)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona una incidencia EF",
                        subtitle: "Aquí agrupamos lesiones, seguridad, equipación, material y conducta con accesos cruzados a diario, asistencia y alumnado."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePEIncidentSheet(defaultClassId: selectedClassId) { incidentId, category, workflowState, sessionId, note in
                let entry = PEIncidentMetadata(
                    id: incidentId,
                    category: category,
                    workflowState: workflowState,
                    sessionId: sessionId,
                    followUpNote: note
                )
                metadata.removeAll { $0.id == incidentId }
                metadata.append(entry)
                persistItems(metadata, forKey: peIncidentMetadataStorageKey)
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .appOnChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
        .appOnChange(of: selectedFilter) { _ in
            if selectedIncidentId == nil || !filteredIncidents.contains(where: { $0.id == selectedIncidentId }) {
                selectedIncidentId = filteredIncidents.first?.id
            }
        }
        .appOnChange(of: searchText) { _ in
            if selectedIncidentId == nil || !filteredIncidents.contains(where: { $0.id == selectedIncidentId }) {
                selectedIncidentId = filteredIncidents.first?.id
            }
        }
    }

    @MainActor
    func reload() async {
        guard let selectedClassId else {
            incidents = []
            selectedIncidentId = nil
            return
        }
        incidents = (try? await bridge.incidents(for: selectedClassId)) ?? []
        if selectedIncidentId == nil || !incidents.contains(where: { $0.id == selectedIncidentId }) {
            selectedIncidentId = filteredIncidents.first?.id ?? incidents.first?.id
        }
    }

    func incidentCategory(for incident: Incident) -> String {
        let text = "\(incident.title) \(incident.detail ?? "")".lowercased()
        if text.contains("les") || text.contains("injur") || text.contains("dolor") || text.contains("golpe") {
            return "Lesión"
        }
        if text.contains("segur") || text.contains("riesgo") || text.contains("caída") || text.contains("choque") {
            return "Seguridad"
        }
        if text.contains("material") || text.contains("balón") || text.contains("cono") || text.contains("raqueta") {
            return "Material"
        }
        if text.contains("equip") || text.contains("ropa") || text.contains("zapat") {
            return "Equipación"
        }
        if text.contains("conduct") || text.contains("comport") || text.contains("disciplina") {
            return "Conducta"
        }
        return "Seguridad"
    }

    func categoryIcon(for incident: Incident) -> String {
        switch incidentCategory(for: incident) {
        case "Lesión": return "cross.case.fill"
        case "Seguridad": return "shield.fill"
        case "Material": return "shippingbox.fill"
        case "Equipación": return "tshirt.fill"
        case "Conducta": return "person.crop.circle.badge.exclamationmark"
        default: return "exclamationmark.triangle.fill"
        }
    }

    func isCritical(_ incident: Incident) -> Bool {
        let severity = incident.severity.lowercased()
        return severity == "high" || severity == "critical"
    }

    func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical":
            return .pink
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .secondary
        }
    }

    func incidentStudentName(_ incident: Incident) -> String? {
        guard let studentId = incident.studentId?.int64Value else { return nil }
        let source = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        guard let student = source.first(where: { $0.id == studentId }) else { return nil }
        return "\(student.firstName) \(student.lastName)"
    }

    func incidentDateLabel(_ incident: Incident) -> String {
        Date(timeIntervalSince1970: TimeInterval(incident.date.epochSeconds))
            .formatted(date: .abbreviated, time: .shortened)
    }

    func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    func updateMetadata(for incidentId: Int64, mutate: (inout PEIncidentMetadata) -> Void) {
        if let index = metadata.firstIndex(where: { $0.id == incidentId }) {
            var current = metadata[index]
            mutate(&current)
            metadata[index] = current
        } else {
            var newEntry = PEIncidentMetadata(id: incidentId, category: selectedIncident.map(incidentCategory(for:)) ?? "Seguridad", workflowState: .open, sessionId: nil, followUpNote: "")
            mutate(&newEntry)
            metadata.append(newEntry)
        }
        persistItems(metadata, forKey: peIncidentMetadataStorageKey)
    }

    func setIncidentWorkflowState(for incidentId: Int64, state: PEIncidentWorkflowState) {
        updateMetadata(for: incidentId) { current in
            current.workflowState = state
        }
    }

    @ViewBuilder
    func workflowButton(title: String, incidentId: Int64, targetState: PEIncidentWorkflowState, activeState: PEIncidentWorkflowState) -> some View {
        let isActive = activeState == targetState
        if isActive {
            Button(title) {
                setIncidentWorkflowState(for: incidentId, state: targetState)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(title) {
                setIncidentWorkflowState(for: incidentId, state: targetState)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct PESessionsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State var sessions: [KmpBridge.PESessionSnapshot] = []
    @State var selectedSessionId: Int64?
    @State var timerStart = Date()
    @State var now = Date()
    @State var showingCreateSheet = false
    @State var showingOperationalSheet = false

    var selectedSession: KmpBridge.PESessionSnapshot? {
        sessions.first(where: { $0.id == selectedSessionId })
    }

    var activeDurationText: String {
        let interval = Int(now.timeIntervalSince(timerStart))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Sesiones", value: "\(sessions.count)", tint: .blue)
                        WorkspaceCompactStat(title: "Con diario", value: "\(sessions.filter { $0.summary != nil }.count)", tint: .green)
                        WorkspaceCompactStat(title: "Activa", value: activeDurationText, tint: .orange)
                        Spacer()
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nueva sesión EF", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)

                List(sessions, id: \.id) { snapshot in
                    Button {
                        selectedSessionId = snapshot.id
                        timerStart = Date()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(snapshot.session.teachingUnitName)
                                    .font(.headline)
                                Spacer()
                                Text("P\(snapshot.session.period)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(weekdayLabel(snapshot.session.dayOfWeek)) · \(snapshot.session.groupName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 330, maxWidth: 390)

            Divider().opacity(0.2)

            Group {
                if let snapshot = selectedSession {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(
                                title: snapshot.session.teachingUnitName,
                                subtitle: "Sesión activa · \(snapshot.session.groupName)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Temporizador", value: activeDurationText, systemImage: "timer")
                                WorkspaceMetricCard(title: "Intensidad", value: snapshot.intensityScore == 0 ? "Sin dato" : "\(snapshot.intensityScore)/5", systemImage: "flame.fill")
                                WorkspaceMetricCard(title: "Estado", value: snapshot.summary?.status.name.capitalized ?? "Sin diario", systemImage: "doc.text.fill")
                                WorkspaceMetricCard(title: "Sesión", value: sessionStateText(snapshot.session.status), systemImage: "figure.run")
                            }

                            WorkspaceDetailBlock(title: "Material listo", content: fallback(snapshot.materialToPrepareText, empty: "Sin preparación registrada"))
                            WorkspaceDetailBlock(title: "Material usado", content: fallback(snapshot.materialUsedText, empty: "Sin material usado registrado"))
                            WorkspaceDetailBlock(title: "Lesiones", content: fallback(snapshot.injuriesText, empty: "Sin lesiones activas"))
                            WorkspaceDetailBlock(title: "Sin equipación", content: fallback(snapshot.unequippedStudentsText, empty: "Sin alumnado sin equipación"))
                            WorkspaceDetailBlock(title: "Estaciones", content: fallback(snapshot.stationObservationsText, empty: "Sin observaciones por estaciones"))

                            if !fallback(snapshot.physicalIncidentsText, empty: "").isEmpty {
                                WorkspaceDetailBlock(title: "Incidencias físicas", content: snapshot.physicalIncidentsText)
                            }

                            HStack(spacing: 12) {
                                Button("Editar operativa") {
                                    showingOperationalSheet = true
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Abrir diario") {
                                    onOpenModule(.diary, snapshot.session.groupId, nil)
                                }
                                .buttonStyle(.bordered)

                                Button("Abrir asistencia") {
                                    onOpenModule(.attendance, snapshot.session.groupId, nil)
                                }
                                .buttonStyle(.bordered)

                                Button("Ver incidencias EF") {
                                    onOpenModule(.peIncidents, snapshot.session.groupId, nil)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona una sesión EF",
                        subtitle: "La sesión activa muestra temporizador, intensidad, material, lesiones y accesos rápidos de pista."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePESessionSheet(defaultClassId: selectedClassId) {
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .sheet(isPresented: $showingOperationalSheet) {
            if let selectedSession {
                EditPESessionOperationalSheet(snapshot: selectedSession) {
                    Task { await reload() }
                }
                .environmentObject(bridge)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
        .appOnChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
    }

    @MainActor
    func reload() async {
        let calendar = Calendar(identifier: .iso8601)
        let date = Date()
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        sessions = (try? await bridge.loadPESessions(weekNumber: week, year: year, classId: selectedClassId)) ?? []
        if selectedSessionId == nil || !sessions.contains(where: { $0.id == selectedSessionId }) {
            selectedSessionId = sessions.first?.id
        }
        timerStart = Date()
    }

    func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }

    func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    func sessionStateText(_ status: SessionStatus) -> String {
        switch status {
        case .planned: return "Planificada"
        case .inProgress: return "Activa"
        case .completed: return "Cerrada"
        case .cancelled: return "Cancelada"
        default: return status.name.capitalized
        }
    }
}

struct PEMaterialWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State var sessions: [KmpBridge.PESessionSnapshot] = []
    @State var records: [PEMaterialRecord] = storedItems(forKey: peMaterialStorageKey, as: PEMaterialRecord.self)
    @State var selectedRecordId: UUID?
    @State var showingCreateSheet = false

    var filteredRecords: [PEMaterialRecord] {
        let scoped = selectedClassId.map { classId in
            records.filter { $0.classId == classId }
        } ?? records
        return scoped.sorted { $0.createdAt > $1.createdAt }
    }

    var selectedRecord: PEMaterialRecord? {
        filteredRecords.first(where: { $0.id == selectedRecordId }) ?? filteredRecords.first
    }

    var selectedSession: KmpBridge.PESessionSnapshot? {
        guard let sessionId = selectedRecord?.sessionId else { return nil }
        return sessions.first(where: { $0.id == sessionId })
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Registros", value: "\(filteredRecords.count)", tint: .blue)
                        WorkspaceCompactStat(title: "Dañado", value: "\(filteredRecords.filter { $0.status == .damaged }.count)", tint: .red)
                        WorkspaceCompactStat(title: "Reponer", value: "\(filteredRecords.filter { $0.status == .replenish }.count)", tint: .orange)
                        Spacer()
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nuevo material", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)

                List(filteredRecords, id: \.id) { record in
                    Button {
                        selectedRecordId = record.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.itemName)
                                .font(.headline)
                            Text("\(record.status.rawValue) · \(record.quantity) uds")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 330, maxWidth: 390)

            Divider().opacity(0.2)

            Group {
                if let record = selectedRecord {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(title: record.itemName, subtitle: record.status.rawValue)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Cantidad", value: "\(record.quantity)", systemImage: "number")
                                WorkspaceMetricCard(title: "Estado", value: record.status.rawValue, systemImage: "shippingbox.fill")
                                WorkspaceMetricCard(
                                    title: "Sesión",
                                    value: selectedSession?.session.teachingUnitName ?? "Sin sesión",
                                    systemImage: "figure.run"
                                )
                            }
                            WorkspaceDetailBlock(title: "Nota logística", content: fallback(record.note, empty: "Sin notas adicionales"))
                            if let selectedSession {
                                WorkspaceDetailBlock(title: "Material de la sesión", content: fallback(selectedSession.materialUsedText, empty: "Sin material usado registrado"))
                            }

                            HStack(spacing: 12) {
                                if let selectedSession {
                                    Button("Abrir sesión EF") {
                                        onOpenModule(.peSessions, selectedSession.session.groupId, nil)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Abrir diario") {
                                        onOpenModule(.diary, selectedSession.session.groupId, nil)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 18) {
                        WorkspaceEmptyState(
                            title: "Registra material EF",
                            subtitle: "Crea registros de preparación, uso, faltantes, daños o reposición vinculados a una sesión."
                        )
                        Button("Nuevo registro de material") {
                            showingCreateSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePEMaterialRecordSheet(defaultClassId: selectedClassId, sessions: sessions) { record in
                records.removeAll { $0.id == record.id }
                records.append(record)
                persistItems(records, forKey: peMaterialStorageKey)
                selectedRecordId = record.id
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .appOnChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
    }

    @MainActor
    func reload() async {
        let calendar = Calendar(identifier: .iso8601)
        let date = Date()
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        sessions = (try? await bridge.loadPESessions(weekNumber: week, year: year, classId: selectedClassId)) ?? []
        if selectedRecordId == nil || !filteredRecords.contains(where: { $0.id == selectedRecordId }) {
            selectedRecordId = filteredRecords.first?.id
        }
    }

    func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }
}

struct PETournamentsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?

    @State var tournaments: [TournamentViewState] = storedItems(forKey: peTournamentStorageKey, as: TournamentViewState.self)
    @State var selectedTournamentId: UUID?
    @State var selectedMatchId: UUID?
    @State var showingCreateSheet = false
    @State var showingBoardScreen = false

    var scopedTournaments: [TournamentViewState] {
        tournaments
            .filter { selectedClassId == nil || $0.classId == selectedClassId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var selectedTournament: TournamentViewState? {
        scopedTournaments.first(where: { $0.id == selectedTournamentId }) ?? scopedTournaments.first
    }

    var selectedMatch: TournamentMatch? {
        guard let selectedTournament else { return nil }
        return selectedTournament.matches.first(where: { $0.id == selectedMatchId }) ?? selectedTournament.matches.first
    }

    var standings: [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        guard let selectedTournament else { return [] }
        return computeStandings(for: selectedTournament, matches: selectedTournament.matches)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Torneos", value: "\(scopedTournaments.count)", tint: .blue)
                        WorkspaceCompactStat(title: "Equipos", value: "\(selectedTournament?.teams.count ?? 0)", tint: .orange)
                        WorkspaceCompactStat(title: "Partidos", value: "\(selectedTournament?.matches.count ?? 0)", tint: .green)
                    }
                }
                .padding(16)

                List {
                    Section("Torneos") {
                        ForEach(scopedTournaments, id: \.id) { tournament in
                            Button {
                                selectedTournamentId = tournament.id
                                selectedMatchId = tournament.matches.first?.id
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tournament.name)
                                        .font(.headline)
                                    Text("\(tournament.template.rawValue) · \(tournament.status.rawValue)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 300, maxWidth: 340)

            Divider().opacity(0.2)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if let selectedTournament {
                        HStack {
                            Text(selectedTournament.template.rawValue)
                                .font(.headline)
                            Spacer()
                            Button("Vista torneo") {
                                showingBoardScreen = true
                            }
                            .buttonStyle(.bordered)
                            Menu {
                                ForEach(TournamentStatus.allCases) { status in
                                    Button(status.rawValue) {
                                        updateTournament(selectedTournament.id) { current in
                                            current.status = status
                                        }
                                    }
                                }
                            } label: {
                                Label(selectedTournament.status.rawValue, systemImage: "flag.fill")
                            }
                        }
                    }
                }
                .padding(16)

                List {
                    if let selectedTournament {
                        Section("Partidos") {
                            ForEach(Array(selectedTournament.matches.enumerated()), id: \.element.id) { index, match in
                                Button {
                                    selectedMatchId = match.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(match.phase) · Ronda \(match.round)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                        HStack {
                                            Text(match.homeLabel)
                                            Spacer()
                                            Stepper(value: matchBinding(tournamentId: selectedTournament.id, matchIndex: index, home: true), in: 0...99) {
                                                Text("\(match.homeScore)")
                                                    .font(.headline.monospacedDigit())
                                            }
                                        }
                                        HStack {
                                            Text(match.awayLabel)
                                            Spacer()
                                            Stepper(value: matchBinding(tournamentId: selectedTournament.id, matchIndex: index, home: false), in: 0...99) {
                                                Text("\(match.awayScore)")
                                                    .font(.headline.monospacedDigit())
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 380, maxWidth: 470)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let selectedTournament {
                        WorkspaceInspectorHero(title: selectedTournament.name, subtitle: selectedClassLabel)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            WorkspaceMetricCard(title: "Plantilla", value: selectedTournament.template.rawValue, systemImage: "square.grid.3x3.fill")
                            WorkspaceMetricCard(title: "Equipos", value: "\(selectedTournament.teams.count)", systemImage: "person.3.fill")
                            WorkspaceMetricCard(title: "Partidos", value: "\(selectedTournament.matches.count)", systemImage: "sportscourt.fill")
                            WorkspaceMetricCard(title: "Estado", value: selectedTournament.status.rawValue, systemImage: "flag.fill")
                        }

                        if let selectedMatch {
                            WorkspaceDetailBlock(
                                title: "Partido seleccionado",
                                content: "\(selectedMatch.phase) · Ronda \(selectedMatch.round)\n\(selectedMatch.homeLabel) vs \(selectedMatch.awayLabel)\nPista: \(selectedMatch.court.isEmpty ? "Sin asignar" : selectedMatch.court)"
                            )
                        }

                        HStack(spacing: 12) {
                            Button("Abrir progreso del torneo") {
                                showingBoardScreen = true
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Nuevo torneo") {
                                showingCreateSheet = true
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Clasificación")
                                .font(.headline)
                            ForEach(Array(standings.enumerated()), id: \.offset) { index, standing in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("#\(index + 1) · \(standing.team.name)")
                                        .font(.headline)
                                    Text("\(standing.points) pts · \(standing.scored) a favor · \(standing.conceded) en contra")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        if selectedTournament.template == .groupsAndKnockout {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Clasificación por grupos")
                                    .font(.headline)
                                ForEach(groupStandings(for: selectedTournament), id: \.key) { group, rows in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group)
                                            .font(.subheadline.bold())
                                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                            groupStandingRow(index: index, row: row)
                                        }
                                    }
                                    .padding(12)
                                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Equipos")
                                .font(.headline)
                            ForEach(selectedTournament.teams, id: \.id) { team in
                                WorkspaceDetailBlock(
                                    title: team.name,
                                    content: teamSummaryText(team, tournament: selectedTournament)
                                )
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            WorkspaceEmptyState(
                                title: "Organiza un torneo EF",
                                subtitle: "Crea torneos con plantillas Round-robin, Eliminatoria o Fase de grupos + eliminatoria."
                            )
                            Button("Nuevo torneo") {
                                showingCreateSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reloadTeams() }
        .sheet(isPresented: $showingCreateSheet) {
            CreateTournamentSheet(defaultClassId: selectedClassId) { tournament in
                tournaments.append(tournament)
                persistItems(tournaments, forKey: peTournamentStorageKey)
                selectedTournamentId = tournament.id
                selectedMatchId = tournament.matches.first?.id
            }
            .environmentObject(bridge)
        }
        .appFullScreenCover(isPresented: $showingBoardScreen) {
            if let selectedTournament, let binding = tournamentBinding(for: selectedTournament.id) {
                TournamentBoardScreen(
                    tournament: binding,
                    classLabel: selectedClassLabel,
                    students: bridge.studentsInClass
                )
            } else {
                EmptyView()
            }
        }
        .appOnChange(of: selectedClassId) { _ in
            Task { await reloadTeams() }
        }
    }

    var selectedClassLabel: String {
        guard let selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == selectedClassId }) else {
            return "Torneo de clase"
        }
        return schoolClass.name
    }

    @MainActor
    func reloadTeams() async {
        await bridge.selectStudentsClass(classId: selectedClassId)
        if selectedTournamentId == nil || !scopedTournaments.contains(where: { $0.id == selectedTournamentId }) {
            selectedTournamentId = scopedTournaments.first?.id
        }
        if selectedMatchId == nil || !(selectedTournament?.matches.contains(where: { $0.id == selectedMatchId }) ?? false) {
            selectedMatchId = selectedTournament?.matches.first?.id
        }
    }

    func updateTournament(_ tournamentId: UUID, mutate: (inout TournamentViewState) -> Void) {
        guard let index = tournaments.firstIndex(where: { $0.id == tournamentId }) else { return }
        var current = tournaments[index]
        mutate(&current)
        tournaments[index] = current
        persistItems(tournaments, forKey: peTournamentStorageKey)
    }

    func tournamentBinding(for tournamentId: UUID) -> Binding<TournamentViewState>? {
        guard let index = tournaments.firstIndex(where: { $0.id == tournamentId }) else { return nil }
        return Binding(
            get: { tournaments[index] },
            set: { tournaments[index] = $0; persistItems(tournaments, forKey: peTournamentStorageKey) }
        )
    }

    func matchBinding(tournamentId: UUID, matchIndex: Int, home: Bool) -> Binding<Int> {
        Binding(
            get: {
                guard let tournament = tournaments.first(where: { $0.id == tournamentId }),
                      tournament.matches.indices.contains(matchIndex) else { return 0 }
                return home ? tournament.matches[matchIndex].homeScore : tournament.matches[matchIndex].awayScore
            },
            set: { newValue in
                updateTournament(tournamentId) { current in
                    guard current.matches.indices.contains(matchIndex) else { return }
                    if home {
                        current.matches[matchIndex].homeScore = newValue
                    } else {
                        current.matches[matchIndex].awayScore = newValue
                    }
                }
            }
        )
    }

    func computeStandings(
        for tournament: TournamentViewState,
        matches: [TournamentMatch]
    ) -> [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        tournament.teams.map { team in
            let related = matches.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }
            let points = related.reduce(0) { total, match in
                let isHome = match.homeTeamId == team.id
                let scored = isHome ? match.homeScore : match.awayScore
                let conceded = isHome ? match.awayScore : match.homeScore
                if scored > conceded { return total + tournament.pointsWin }
                if scored == conceded { return total + tournament.pointsDraw }
                return total + tournament.pointsLoss
            }
            let scored = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.homeScore : match.awayTeamId == team.id ? match.awayScore : 0)
            }
            let conceded = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.awayScore : match.awayTeamId == team.id ? match.homeScore : 0)
            }
            return (team, points, scored, conceded)
        }
        .sorted { lhs, rhs in
            if lhs.points == rhs.points { return lhs.scored > rhs.scored }
            return lhs.points > rhs.points
        }
    }

    func groupStandings(for tournament: TournamentViewState) -> [(key: String, value: [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)])] {
        let grouped = Dictionary(grouping: tournament.matches.filter { $0.phase.hasPrefix("Grupo") }) { $0.phase }
        return grouped.keys.sorted().map { key in
            (key, computeStandings(for: tournament, matches: grouped[key] ?? []))
        }
    }

    func teamSummaryText(_ team: TournamentTeam, tournament: TournamentViewState) -> String {
        let names = team.studentIds.compactMap { studentId in
            bridge.studentsInClass.first(where: { $0.id == studentId }).map { "\($0.firstName) \($0.lastName)" }
        }
        guard !names.isEmpty else { return "Sin participantes asignados" }
        return "\(names.count) participante(s)\n" + names.joined(separator: ", ")
    }

    func groupStandingRow(
        index: Int,
        row: (team: TournamentTeam, points: Int, scored: Int, conceded: Int)
    ) -> some View {
        let description = "#\(index + 1) · \(row.team.name) · \(row.points) pts"
        return Text(description)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
