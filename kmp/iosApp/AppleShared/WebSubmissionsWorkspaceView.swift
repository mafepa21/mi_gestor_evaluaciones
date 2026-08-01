import SwiftUI
import MiGestorKit

#if os(macOS)
import AppKit
#endif

/// Bandeja operativa de Entregas web.
///
/// El Mac es el centro de esta función: aquí se publican formularios, se
/// conservan las correspondencias privadas y se importan lotes. La pantalla ya
/// no depende de un único grupo ni del formulario más reciente.
struct WebSubmissionsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge

    @AppStorage("webSubmissions.baseURL") private var baseURL = "https://entregas-alumnado.vercel.app"
    @AppStorage("webSubmissions.deliveryEmail") private var deliveryEmail = ""

    @State private var tasks: [WebSubmissionTaskInfo] = []
    @State private var snapshots: [String: WebSubmissionSnapshot] = [:]
    @State private var manifests: [String: WebFormManifest] = [:]
    @State private var manifestJSONByFormInstanceId: [String: Data] = [:]
    @State private var linksByFormInstanceId: [String: [WebPublishedStudentLink]] = [:]
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var importSummary: String?
    @State private var importing = false
    @State private var revoking = false

    @State private var selectedGroupFilter = "all"
    @State private var statusFilter: WebSubmissionTaskFilter = .active
    @State private var searchText = ""

    @State private var creationClassId: Int64?
    @State private var creationInstruments: [WebPublishableInstrument] = []
    @State private var showingPublish = false
    @State private var publishing = false
    @State private var publishResult: WebPublishResult?
    @State private var emailTask: WebSubmissionTaskInfo?
    @State private var taskToRevoke: WebSubmissionTaskInfo?
    @State private var selectionMode = false
    @State private var selectedTaskIDs: Set<String> = []
    @State private var bulkActionToConfirm: WebSubmissionBulkAction?
    @State private var bulkProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            filters

            #if os(macOS)
            selectionBar
            #endif

            if let importSummary {
                Label(importSummary, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }

            taskList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if creationClassId == nil {
                creationClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
            }
            await reload()
        }
        .task(id: creationClassId) {
            await reloadCreationInstruments()
        }
        .sheet(isPresented: $showingPublish) {
            WebSubmissionPublishSheet(
                classId: creationClassId ?? 0,
                className: creationClassName,
                instruments: creationInstruments,
                baseURL: $baseURL,
                deliveryEmail: $deliveryEmail,
                isPublishing: publishing,
                onPublish: { columnId, url, correo, caducidad in
                    Task {
                        await publish(
                            columnId: columnId,
                            baseURL: url,
                            deliveryEmail: correo,
                            expiresAt: caducidad
                        )
                    }
                },
                result: publishResult
            )
        }
        .sheet(item: $emailTask) { task in
            WebSubmissionLinkEmailSheet(
                task: task,
                links: linksByFormInstanceId[task.formInstanceId] ?? []
            )
        }
        .alert(
            "No se pudo completar la operación",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )
        ) {
            Button("Entendido") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Revocar tarea web",
            isPresented: Binding(
                get: { taskToRevoke != nil },
                set: { visible in if !visible { taskToRevoke = nil } }
            )
        ) {
            Button("Revocar tarea", role: .destructive) {
                guard let task = taskToRevoke else { return }
                taskToRevoke = nil
                Task { await revoke(task) }
            }
            Button("Cancelar", role: .cancel) {
                taskToRevoke = nil
            }
        } message: {
            Text(
                "\(taskToRevoke?.title ?? "Esta tarea") quedará como Revocada en este Mac. "
                + "No se borrarán el historial ni las entregas ya recibidas. Para bloquear nuevos accesos, retira también el manifiesto público ya desplegado."
            )
        }
        .alert(
            "Gestionar tareas seleccionadas",
            isPresented: Binding(
                get: { bulkActionToConfirm != nil },
                set: { visible in if !visible { bulkActionToConfirm = nil } }
            )
        ) {
            if let action = bulkActionToConfirm {
                switch action {
                case .revoke:
                    Button("Revocar seleccionadas", role: .destructive) {
                        confirmBulkAction(action)
                    }
                case .archive:
                    Button("Archivar seleccionadas") {
                        confirmBulkAction(action)
                    }
                case .restore:
                    Button("Restaurar seleccionadas") {
                        confirmBulkAction(action)
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                bulkActionToConfirm = nil
            }
        } message: {
            Text(bulkConfirmationMessage)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                creationControls
            }

            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                creationControls
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Entregas web")
                .font(.largeTitle.weight(.bold))
            Text("Publica formularios y recoge entregas de todos tus grupos desde una sola bandeja.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var creationControls: some View {
        HStack(spacing: 12) {
            Picker("Grupo para la nueva tarea", selection: Binding(
                get: { creationClassId ?? bridge.classes.first?.id ?? 0 },
                set: { creationClassId = $0 }
            )) {
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(schoolClass.name).tag(schoolClass.id)
                }
            }
            .pickerStyle(.menu)

            if !tasks.isEmpty || !manifests.isEmpty {
                WebSubmissionBatchImportButton(
                    taskInfoByFormInstanceId: Dictionary(uniqueKeysWithValues: tasks.map { ($0.formInstanceId, $0) }),
                    manifestsByFormInstanceId: manifests,
                    manifestJSONByFormInstanceId: manifestJSONByFormInstanceId,
                    service: WebSubmissionImportService(
                        resolver: WebSubmissionSnapshotResolver(snapshots: snapshots)
                    ),
                    rosterByFormInstanceId: snapshots.mapValues(\.roster),
                    isImporting: importing,
                    onConfirm: { decisions in
                        Task { await confirmImport(decisions) }
                    }
                )
                .buttonStyle(.bordered)
                .disabled(importing || manifests.isEmpty)
            }

            Button {
                publishResult = nil
                showingPublish = true
            } label: {
                Label("Nueva tarea web", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(creationClassId == nil || loading)
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                statusPicker
                groupPicker
                searchField
                #if os(macOS)
                Spacer(minLength: 8)
                selectionToggle
                #endif
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    statusPicker
                    groupPicker
                }
                HStack(spacing: 12) {
                    searchField
                    #if os(macOS)
                    Spacer(minLength: 8)
                    selectionToggle
                    #endif
                }
            }
        }
    }

    #if os(macOS)
    private var selectionToggle: some View {
        Button {
            selectionMode.toggle()
            if !selectionMode {
                selectedTaskIDs.removeAll()
            }
        } label: {
            Label(
                selectionMode ? "Salir de selección" : "Seleccionar tareas",
                systemImage: selectionMode ? "checkmark.circle.fill" : "checklist"
            )
        }
        .buttonStyle(.bordered)
        .disabled(loading || bulkProcessing)
    }

    @ViewBuilder
    private var selectionBar: some View {
        if selectionMode {
            HStack(spacing: 12) {
                Label(
                    selectedTaskIDs.isEmpty
                        ? "Selecciona tareas para gestionarlas juntas"
                        : "\(selectedTaskIDs.count) seleccionada\(selectedTaskIDs.count == 1 ? "" : "s")",
                    systemImage: "checklist"
                )
                .font(.callout.weight(.semibold))

                Spacer(minLength: 8)

                Button("Todas las visibles") {
                    selectedTaskIDs = Set(filteredTasks.map(\.id))
                }
                .buttonStyle(.borderless)
                .disabled(filteredTasks.isEmpty || bulkProcessing)

                Button("Limpiar") {
                    selectedTaskIDs.removeAll()
                }
                .buttonStyle(.borderless)
                .disabled(selectedTaskIDs.isEmpty || bulkProcessing)

                Menu {
                    let revocable = selectedTasks.filter { $0.status == .active && !$0.isArchived }
                    let archivable = selectedTasks.filter { !$0.isArchived }
                    let restorable = selectedTasks.filter(\.isArchived)

                    Button("Revocar seleccionadas (\(revocable.count))", role: .destructive) {
                        bulkActionToConfirm = .revoke
                    }
                    .disabled(revocable.isEmpty || bulkProcessing)

                    Button("Archivar seleccionadas (\(archivable.count))") {
                        bulkActionToConfirm = .archive
                    }
                    .disabled(archivable.isEmpty || bulkProcessing)

                    Button("Restaurar seleccionadas (\(restorable.count))") {
                        bulkActionToConfirm = .restore
                    }
                    .disabled(restorable.isEmpty || bulkProcessing)
                } label: {
                    Label("Acciones", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .disabled(selectedTaskIDs.isEmpty || bulkProcessing)

                Button("Terminar") {
                    selectionMode = false
                    selectedTaskIDs.removeAll()
                }
                .buttonStyle(.borderless)
                .disabled(bulkProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    #endif

    private var statusPicker: some View {
        Picker("Estado", selection: $statusFilter) {
            ForEach(WebSubmissionTaskFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.menu)
    }

    private var groupPicker: some View {
        Picker("Grupo", selection: $selectedGroupFilter) {
            Text("Todos los grupos").tag("all")
            ForEach(groupNames, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .pickerStyle(.menu)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar grupo o tarea", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(minWidth: 220, maxWidth: 360)
    }

    @ViewBuilder
    private var taskList: some View {
        let visibleTasks = filteredTasks
        if loading && tasks.isEmpty {
            ProgressView("Cargando tareas…")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 64)
        } else if visibleTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: tasks.isEmpty ? "paperplane" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(tasks.isEmpty ? "Todavía no hay tareas web" : "No hay tareas con estos filtros")
                    .font(.headline)
                Text(tasks.isEmpty
                     ? "Crea una tarea para generar un formulario y enlaces personales por alumno."
                     : "Prueba otro estado, grupo o búsqueda.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(visibleTasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: WebSubmissionTaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if selectionMode {
                    Button {
                        toggleSelection(for: task)
                    } label: {
                        Image(systemName: selectedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedTaskIDs.contains(task.id) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(selectedTaskIDs.contains(task.id) ? "Quitar selección" : "Seleccionar tarea")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                    Text("\(task.groupName) · \(task.columnTitle)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                statusBadge(task)
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Label(expiryText(task), systemImage: "calendar")
                Label("\(task.importedCount) importadas", systemImage: "tray.full")
                if let last = task.lastImportedAtEpochMs {
                    Text("Última: \(shortDate(last))")
                }
                Spacer(minLength: 0)
                taskActions(task)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusBadge(_ task: WebSubmissionTaskInfo) -> some View {
        Text(task.managementLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                task.isArchived
                    ? Color.secondary
                    : (task.status == .active ? Color.green : (task.status == .expired ? Color.orange : Color.secondary))
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.secondary.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func taskActions(_ task: WebSubmissionTaskInfo) -> some View {
        #if os(macOS)
        HStack(spacing: 8) {
            if task.status == .active && !task.isArchived {
                Button {
                    emailTask = task
                } label: {
                    Label("Enviar enlaces", systemImage: "envelope")
                }
                .buttonStyle(.borderless)
                .disabled(revoking || bulkProcessing)
            }

            Menu {
                Button("Abrir carpeta") { revealFiles(for: task) }
                Button("Copiar enlaces") { copyLinks(for: task) }
                if task.status == .active && !task.isArchived {
                    Divider()
                    Button("Revocar tarea", role: .destructive) {
                        taskToRevoke = task
                    }
                }
                if task.isArchived {
                    Divider()
                    Button("Restaurar en la bandeja") {
                        Task { await restore([task]) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
            .help("Más acciones")
            .disabled(revoking || bulkProcessing)
        }
        #else
        EmptyView()
        #endif
    }

    private var filteredTasks: [WebSubmissionTaskInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            let matchesStatus = statusFilter.matches(task)
            let matchesGroup = selectedGroupFilter == "all" || task.groupName == selectedGroupFilter
            let matchesSearch = query.isEmpty
                || task.groupName.localizedCaseInsensitiveContains(query)
                || task.title.localizedCaseInsensitiveContains(query)
                || task.columnTitle.localizedCaseInsensitiveContains(query)
            return matchesStatus && matchesGroup && matchesSearch
        }
    }

    private var groupNames: [String] {
        Array(Set(tasks.map(\.groupName))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var creationClassName: String {
        bridge.classes.first(where: { $0.id == creationClassId })?.name ?? "Grupo"
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        tasks = await bridge.listWebSubmissionTasks()
        selectedTaskIDs.formIntersection(Set(tasks.map(\.id)))

        var loadedSnapshots: [String: WebSubmissionSnapshot] = [:]
        var loadedManifests: [String: WebFormManifest] = [:]
        var loadedManifestJSON: [String: Data] = [:]
        var loadedLinks: [String: [WebPublishedStudentLink]] = [:]
        for classId in Set(tasks.map(\.classId)) {
            guard let instances = try? await bridge.listWebFormInstances(classId: classId) else { continue }
            for instance in instances {
                let rawManifest = Data(instance.manifestJson.utf8)
                guard let snapshot = await bridge.loadWebSubmissionSnapshot(
                    formInstanceId: instance.formInstanceId
                ),
                let manifest = try? JSONDecoder().decode(
                    WebFormManifest.self,
                    from: rawManifest
                ) else { continue }
                loadedSnapshots[instance.formInstanceId] = snapshot
                loadedManifests[instance.formInstanceId] = manifest
                loadedManifestJSON[instance.formInstanceId] = rawManifest
                loadedLinks[instance.formInstanceId] = WebSubmissionPrivateLinksStore.readLinks(
                    formInstanceId: instance.formInstanceId,
                    snapshot: snapshot,
                    students: bridge.allStudents
                )
            }
        }
        snapshots = loadedSnapshots
        manifests = loadedManifests
        manifestJSONByFormInstanceId = loadedManifestJSON
        linksByFormInstanceId = loadedLinks
    }

    private func reloadCreationInstruments() async {
        guard let classId = creationClassId else {
            creationInstruments = []
            return
        }
        creationInstruments = await bridge.listPublishableWebForms(classId: classId)
    }

    private func publish(
        columnId: String,
        baseURL url: String,
        deliveryEmail correo: String,
        expiresAt: Date
    ) async {
        guard let classId = creationClassId else { return }
        publishing = true
        defer { publishing = false }
        do {
            publishResult = try await bridge.publishWebForm(
                classId: classId,
                columnId: columnId,
                baseURL: url,
                deliveryEmail: cleanEmail(correo),
                expiresAt: expiresAt
            )
            await reload()
            await reloadCreationInstruments()
        } catch {
            errorMessage = error.localizedDescription
            showingPublish = false
        }
    }

    private func confirmImport(_ decisions: [WebSubmissionImportDecision]) async {
        importing = true
        defer { importing = false }
        let result = await bridge.importWebSubmissions(decisions)
        importSummary = result.summary
        await reload()
    }

    private func revoke(_ task: WebSubmissionTaskInfo) async {
        revoking = true
        defer { revoking = false }
        do {
            try await bridge.revokeWebForm(formInstanceId: task.formInstanceId)
            importSummary = "Tarea «\(task.title)» revocada en este Mac."
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ tasks: [WebSubmissionTaskInfo]) async {
        let targets = tasks.filter(\.isArchived)
        guard !targets.isEmpty else { return }
        bulkProcessing = true
        defer { bulkProcessing = false }
        do {
            try await bridge.restoreArchivedWebForms(formInstanceIds: targets.map(\.formInstanceId))
            importSummary = "\(targets.count) tareas restauradas en la bandeja."
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var selectedTasks: [WebSubmissionTaskInfo] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    private var bulkConfirmationMessage: String {
        guard let action = bulkActionToConfirm else { return "" }
        switch action {
        case .revoke:
            let count = selectedTasks.filter { $0.status == .active && !$0.isArchived }.count
            return "Se revocarán \(count) tareas activas. Se conservarán el historial y las entregas ya recibidas. Para bloquear nuevos accesos, retira también los manifiestos públicos desplegados."
        case .archive:
            let count = selectedTasks.filter { !$0.isArchived }.count
            return "Se archivarán \(count) tareas en la bandeja de este Mac. Archivar no revoca el formulario ni borra sus entregas."
        case .restore:
            let count = selectedTasks.filter(\.isArchived).count
            return "Se devolverán \(count) tareas a la bandeja operativa."
        }
    }

    private func toggleSelection(for task: WebSubmissionTaskInfo) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
    }

    private func confirmBulkAction(_ action: WebSubmissionBulkAction) {
        bulkActionToConfirm = nil
        Task { await performBulkAction(action) }
    }

    private func performBulkAction(_ action: WebSubmissionBulkAction) async {
        let targetTasks: [WebSubmissionTaskInfo]
        switch action {
        case .revoke:
            targetTasks = selectedTasks.filter { $0.status == .active && !$0.isArchived }
        case .archive:
            targetTasks = selectedTasks.filter { !$0.isArchived }
        case .restore:
            targetTasks = selectedTasks.filter(\.isArchived)
        }
        guard !targetTasks.isEmpty else { return }

        bulkProcessing = true
        defer { bulkProcessing = false }
        do {
            let ids = targetTasks.map(\.formInstanceId)
            switch action {
            case .revoke:
                try await bridge.revokeWebForms(formInstanceIds: ids)
                importSummary = "\(ids.count) tareas revocadas en este Mac."
            case .archive:
                try await bridge.archiveWebForms(formInstanceIds: ids)
                importSummary = "\(ids.count) tareas archivadas en la bandeja."
            case .restore:
                try await bridge.restoreArchivedWebForms(formInstanceIds: ids)
                importSummary = "\(ids.count) tareas restauradas en la bandeja."
            }
            selectedTaskIDs.removeAll()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanEmail(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private func expiryText(_ task: WebSubmissionTaskInfo) -> String {
        let date = Date(timeIntervalSince1970: Double(task.expiresAtEpochMs) / 1000)
        return task.status == .expired
            ? "Caducó el \(date.formatted(date: .abbreviated, time: .omitted))"
            : "Hasta \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func shortDate(_ epochMs: Int64) -> String {
        Date(timeIntervalSince1970: Double(epochMs) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }

    #if os(macOS)
    private func folderURL(for task: WebSubmissionTaskInfo) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documents
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent(task.formInstanceId, isDirectory: true)
    }

    private func revealFiles(for task: WebSubmissionTaskInfo) {
        guard let folder = folderURL(for: task) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func copyLinks(for task: WebSubmissionTaskInfo) {
        guard let folder = folderURL(for: task),
              let text = try? String(
                  contentsOf: folder.appendingPathComponent("enlaces-alumnado.txt"),
                  encoding: .utf8
              ) else {
            errorMessage = "Todavía no se encuentra la hoja de enlaces de esta tarea."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        importSummary = "Se han copiado los enlaces de «\(task.title)»."
    }
    #endif
}

private enum WebSubmissionBulkAction {
    case revoke
    case archive
    case restore
}

enum WebSubmissionTaskFilter: String, CaseIterable, Identifiable {
    case active
    case all
    case expired
    case revoked
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: return "Activas"
        case .all: return "Todas"
        case .expired: return "Caducadas"
        case .revoked: return "Revocadas"
        case .archived: return "Archivadas"
        }
    }

    func matches(_ task: WebSubmissionTaskInfo) -> Bool {
        switch self {
        case .active: return !task.isArchived && task.status == .active
        case .all: return true
        case .expired: return !task.isArchived && task.status == .expired
        case .revoked: return !task.isArchived && task.status == .revoked
        case .archived: return task.isArchived
        }
    }
}

/// Destino que se muestra en iPad: las claves y tablas privadas permanecen en el
/// Mac, pero el docente recibe una explicación clara en vez de una pantalla vacía.
struct WebSubmissionsIPadInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.teal)

            Text("Entregas web se gestionan en el Mac")
                .font(.title2.weight(.bold))

            Text("Publica los formularios e importa allí los archivos del alumnado. Cuando termines, las respuestas pasan al Cuaderno del iPad mediante SyncLAN.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Las claves y la relación entre alias y alumnado no salen del Mac.", systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
