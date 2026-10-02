import SwiftUI
import MiGestorKit

struct NotebookGroupManagementSheet: View {
    @ObservedObject var bridge: KmpBridge
    let onToast: (String, NotebookToastStyle) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editGroupTarget: NotebookWorkGroup? = nil
    @State private var showingEditSheet = false

    @State private var showingFileImporter = false
    @State private var showingGeneratorSheet = false
    @State private var importPreview: NotebookWorkGroupImportPreview? = nil
    @State private var importErrorMessage: String? = nil

    @State private var loadingSituations = false
    @State private var classSituations: [LearningSituation] = []
    @State private var boardMode = true
    @StateObject private var boardDraft = WorkGroupBoardDraft()

    private var data: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var activeTabId: String? {
        guard let data = data else { return nil }
        return NotebookWorkGroupPolicy.canonicalTabId(
            tabs: data.sheet.tabs,
            requestedTabId: bridge.selectedNotebookTabId,
            selectedTabId: bridge.selectedNotebookTabId
        )
    }

    private var currentGroups: [NotebookWorkGroup] {
        guard let data = data else { return [] }
        return NotebookWorkGroupPolicy.groupsForManagement(
            groups: data.sheet.workGroups,
            tabs: data.sheet.tabs,
            selectedTabId: bridge.selectedNotebookTabId
        )
    }

    private func extractCourseNumber(from text: String) -> Int? {
        NotebookLearningSituationMatcher.extractCourseNumber(from: text)
    }

    private func isSituation(_ situation: LearningSituation, matchingClassName rawClassName: String, course: Int) -> Bool {
        NotebookLearningSituationMatcher.isSituation(situation, matchingClassName: rawClassName, course: course)
    }

    private func loadClassLearningSituations() {
        guard let classId = data?.sheet.classId else { return }
        loadingSituations = true
        Task {
            // Resolver información de la clase desde el bridge
            let targetClass = bridge.classes.first(where: { $0.id == classId })
            let className = targetClass?.name ?? ""
            let classCourse = targetClass != nil ? Int(targetClass!.course) : (extractCourseNumber(from: className) ?? 1)

            do {
                let situations = try await bridge.learningSituations()
                let allLinks = (try? await bridge.learningSituationClassLinksAll()) ?? []
                let directLinkedIds = Set(
                    allLinks.lazy
                        .filter { $0.classId == classId }
                        .map(\.learningSituationId)
                )

                var linked: [LearningSituation] = []
                var other: [LearningSituation] = []

                for sit in situations {
                    let hasDirectLink = directLinkedIds.contains(sit.id)
                    let matches = isSituation(sit, matchingClassName: className, course: classCourse)

                    // Estricto: debe pertenecer a la clase (bien por link directo o por coincidir en curso)
                    guard hasDirectLink || matches else { continue }

                    if hasDirectLink {
                        linked.append(sit)
                    } else {
                        other.append(sit)
                    }
                }

                linked.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
                other.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
                let finalFiltered = linked + other

                await MainActor.run {
                    self.classSituations = finalFiltered
                    self.loadingSituations = false
                }
            } catch {
                await MainActor.run {
                    self.loadingSituations = false
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if boardMode {
                    NotebookGroupBoardView(
                        bridge: bridge,
                        draft: boardDraft,
                        groups: currentGroups,
                        classSituations: classSituations,
                        onToast: onToast,
                        onCreateGroup: {
                            editGroupTarget = nil
                            showingEditSheet = true
                        },
                        onImportExcel: {
                            showingFileImporter = true
                        },
                        onGenerateCooperative: {
                            showingGeneratorSheet = true
                        }
                    )
                } else {
                    groupsList
                }
            }
            .navigationTitle("Grupos de trabajo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Vista", selection: $boardMode) {
                        Text("Lista").tag(false)
                        Text("Tablero").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.xlsx, .commaSeparatedText, .tabSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showingGeneratorSheet) {
                CooperativeGroupGeneratorSheet(bridge: bridge) { generatedGroups in
                    applyImportedGroups(generatedGroups, clearExisting: false, learningSituationId: nil)
                    onToast("Equipos cooperativos aplicados al cuaderno", .success)
                }
            }
            .sheet(item: $importPreview) { preview in
                NotebookGroupImportPreviewSheet(
                    preview: preview,
                    existingGroupNames: currentGroups.map(\.name),
                    classSituations: classSituations
                ) { confirmedGroups, clearExisting, situationId in
                    applyImportedGroups(confirmedGroups, clearExisting: clearExisting, learningSituationId: situationId)
                }
            }
            .alert("No se pudo importar", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
            .sheet(isPresented: $showingEditSheet) {
                NotebookGroupEditSheet(
                    bridge: bridge,
                    group: editGroupTarget,
                    classSituations: classSituations,
                    isLoadingSituations: loadingSituations
                ) { name, situationId in
                    let classId = data?.sheet.classId
                    Task {
                        var linkFailed = false
                        if let situationId = situationId, let classId = classId {
                            do {
                                try await bridge.addLearningSituationClassLink(situationId: situationId, classId: classId)
                            } catch {
                                linkFailed = true
                            }
                        }
                        await MainActor.run {
                            let tabId = activeTabId ?? ""
                            if let target = editGroupTarget {
                                boardDraft.updateGroup(id: target.id, name: name, learningSituationId: linkFailed ? nil : situationId)
                                bridge.updateNotebookWorkGroup(groupId: target.id, name: name, learningSituationId: linkFailed ? nil : situationId, tabId: tabId)
                                onToast(linkFailed ? "Grupo actualizado, pero no se pudo vincular la situación" : "Grupo actualizado", linkFailed ? .warning : .success)
                            } else {
                                boardDraft.addTemporaryGroup(name: name, tabId: tabId, learningSituationId: linkFailed ? nil : situationId)
                                bridge.saveNotebookWorkGroup(name: name, learningSituationId: linkFailed ? nil : situationId, tabId: tabId)
                                onToast(linkFailed ? "Grupo creado, pero no se pudo vincular la situación" : "Grupo creado", linkFailed ? .warning : .success)
                            }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 360)
                #endif
            }
            .onAppear {
                loadClassLearningSituations()
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            guard let data = data else {
                throw NotebookWorkGroupImportError.emptySpreadsheet
            }
            let classStudents = data.sheet.rows.map(\.student)
            let service = NotebookWorkGroupImportService()
            let preview = try service.preview(
                rows: rows,
                sourceName: url.lastPathComponent,
                classStudents: classStudents
            )
            self.importPreview = preview
        } catch {
            self.importErrorMessage = error.localizedDescription
        }
    }

    private func applyImportedGroups(
        _ groups: [ImportedNotebookGroup],
        clearExisting: Bool,
        learningSituationId: Int64? = nil
    ) {
        guard let data = data else { return }
        let classId = data.sheet.classId
        let resolvedTabId = activeTabId ?? data.sheet.tabs.first?.id ?? ""

        Task {
            if let situationId = learningSituationId {
                do {
                    try await bridge.addLearningSituationClassLink(situationId: situationId, classId: classId)
                } catch {
                    await MainActor.run {
                        importErrorMessage = "No se pudo enlazar la situación de aprendizaje. Los grupos no se han aplicado."
                    }
                    return
                }
            }

            let batchGroups: [(name: String, studentIds: [Int64], learningSituationId: Int64?)] = groups.map { group in
                let matchedStudentIds = group.members.compactMap(\.matchedStudentId)
                return (name: group.name, studentIds: matchedStudentIds, learningSituationId: learningSituationId)
            }

            await MainActor.run {
                boardDraft.applyImported(
                    batchGroups.map { ($0.name, $0.studentIds) },
                    tabId: resolvedTabId,
                    learningSituationId: learningSituationId
                )
                boardMode = true
            }

            do {
                try await bridge.importNotebookWorkGroups(
                    classId: classId,
                    tabId: resolvedTabId,
                    groups: batchGroups,
                    clearExisting: clearExisting
                )
                await MainActor.run {
                    onToast("\(groups.count) grupos importados con éxito", .success)
                }
            } catch {
                await MainActor.run {
                    onToast("Error al importar grupos", .warning)
                }
            }
        }
    }

    /// Recuento y resumen de alumnado por grupo, calculado una vez por pintado.
    private func memberSummaries() -> [Int64: (count: Int, text: String)] {
        guard let data else { return [:] }
        let studentsById = Dictionary(data.sheet.rows.map { ($0.student.id, $0.student) }, uniquingKeysWith: { first, _ in first })
        var idsByGroup: [Int64: [Int64]] = [:]
        for member in data.sheet.workGroupMembers {
            idsByGroup[member.groupId, default: []].append(member.studentId)
        }
        var result: [Int64: (count: Int, text: String)] = [:]
        for (groupId, ids) in idsByGroup {
            let students = ids.compactMap { studentsById[$0] }.sorted {
                "\($0.lastName) \($0.firstName)".localizedStandardCompare("\($1.lastName) \($1.firstName)") == .orderedAscending
            }
            let names = students.prefix(4).map { "\($0.lastName), \($0.firstName)" }
            let text = names.isEmpty
                ? "Sin alumnado"
                : names.joined(separator: " · ") + (students.count > names.count ? "…" : "")
            result[groupId] = (ids.count, text)
        }
        return result
    }

    @ViewBuilder
    private var groupsList: some View {
        let summaries = memberSummaries()
        let situationsById = Dictionary(classSituations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return List {
            if currentGroups.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)

                        Text("Sin grupos de trabajo")
                            .font(.headline)

                        Text("Crea grupos para organizar tu alumnado y agruparlos en el cuaderno.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Section("Grupos actuales") {
                    ForEach(currentGroups, id: \.id) { group in
                        NavigationLink {
                            GroupMembersView(bridge: bridge, group: group)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                        .font(.headline)
                                    Text(summaries[group.id]?.text ?? "Sin alumnado")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text("\(summaries[group.id]?.count ?? 0) alumnos")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if let sitId = group.learningSituationId?.int64Value,
                                           let situation = situationsById[sitId] {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(situation.title)
                                                .font(.caption)
                                                .foregroundStyle(NotebookStyle.primaryTint)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                boardDraft.removeGroup(id: group.id)
                                bridge.deleteNotebookWorkGroup(groupId: group.id)
                                onToast("Grupo eliminado", .warning)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }

                            Button {
                                editGroupTarget = group
                                showingEditSheet = true
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(NotebookStyle.primaryTint)
                        }
                    }
                }
            }

            Section {
                Button {
                    editGroupTarget = nil
                    showingEditSheet = true
                } label: {
                    Label("Nuevo grupo de trabajo", systemImage: "person.2.badge.plus")
                }

                Button {
                    showingGeneratorSheet = true
                } label: {
                    Label("Generar equipos cooperativos (IA)", systemImage: "sparkles")
                }

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Importar grupos desde Excel", systemImage: "arrow.down.doc")
                }

                Button {
                    boardMode = true
                } label: {
                    Label("Organizar en tablero", systemImage: "rectangle.split.3x1")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }
}

struct NotebookGroupEditSheet: View {
    let bridge: KmpBridge
    let group: NotebookWorkGroup?
    let classSituations: [LearningSituation]
    var isLoadingSituations: Bool = false
    let onSave: (String, Int64?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedSituationId: Int64? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre del grupo") {
                    TextField("Nombre", text: $name)
                }

                Section(header: Text("Situación de aprendizaje"), footer: Text("Asociar el grupo a una situación de aprendizaje permite organizarlo por proyectos. Puedes crear y vincular situaciones desde la pestaña 'Situaciones' del menú principal.")) {
                    if isLoadingSituations {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Buscando situaciones del curso...")
                                .foregroundStyle(.secondary)
                        }
                    } else if classSituations.isEmpty {
                        Picker("Situación asociada", selection: $selectedSituationId) {
                            Text("No hay situaciones para este curso")
                                .tag(nil as Int64?)
                        }
                        .disabled(true)
                    } else {
                        Picker("Situación asociada", selection: $selectedSituationId) {
                            Text("Ninguna")
                                .tag(nil as Int64?)

                            ForEach(classSituations, id: \.id) { situation in
                                Text(situation.title)
                                    .tag(situation.id as Int64?)
                            }
                        }
                    }
                }
            }
            .navigationTitle(group == nil ? "Nuevo grupo" : "Editar grupo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, selectedSituationId)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let group = group {
                    name = group.name
                    selectedSituationId = group.learningSituationId?.int64Value
                }
            }
        }
    }
}

private struct GroupMembersView: View {
    @ObservedObject var bridge: KmpBridge
    let group: NotebookWorkGroup

    @State private var searchText = ""

    private var data: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var sortedStudents: [Student] {
        guard let data = data else { return [] }
        return data.sheet.rows.map(\.student).sorted {
            let name1 = "\($0.lastName) \($0.firstName)"
            let name2 = "\($1.lastName) \($1.firstName)"
            return name1.localizedStandardCompare(name2) == .orderedAscending
        }
    }

    private var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedStudents }
        return sortedStudents.filter {
            "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let members = data?.sheet.workGroupMembers ?? []
        let currentIds = Set(members.filter { $0.groupId == group.id }.map(\.studentId))
        let groupNames = Dictionary((data?.sheet.workGroups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var otherByStudent: [Int64: String] = [:]
        for member in members where member.groupId != group.id && otherByStudent[member.studentId] == nil {
            otherByStudent[member.studentId] = groupNames[member.groupId]
        }
        return VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Buscar alumno...")
                .padding()
                .background(IOSAppStyle.pageBackground)

            List {
                Section {
                    ForEach(filteredStudents, id: \.id) { student in
                        let isMember = currentIds.contains(student.id)
                        let otherGroupName = otherByStudent[student.id]

                        Button {
                            toggleStudentMembership(student.id, isMember: isMember)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(student.firstName) \(student.lastName)")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    if let otherGroupName {
                                        Text("En \(otherGroupName)")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Spacer()

                                if isMember {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NotebookStyle.primaryTint)
                                        .font(.title3)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                        .font(.title3)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Selecciona alumnos para este grupo")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
        .navigationTitle(group.name)
    }

    private func toggleStudentMembership(_ studentId: Int64, isMember: Bool) {
        if isMember {
            bridge.assignStudentsToNotebookGroup(groupId: nil, studentIds: [studentId], tabId: group.tabId)
        } else {
            bridge.assignStudentsToNotebookGroup(groupId: group.id, studentIds: [studentId], tabId: group.tabId)
        }
    }
}

private struct SearchBar: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(8)
        .background(IOSAppStyle.cardBackground)
        .cornerRadius(10)
    }
}

enum NotebookLearningSituationMatcher {
    static func extractCourseNumber(from text: String) -> Int? {
        let regex = try? NSRegularExpression(pattern: "\\b([1-6])(?:º|ª|o|a)?\\b", options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex?.firstMatch(in: text, options: [], range: range),
           let digitRange = Range(match.range(at: 1), in: text),
           let num = Int(text[digitRange]) {
            return num
        }
        return nil
    }

    static func isSituation(_ situation: LearningSituation, matchingClassName rawClassName: String, course: Int) -> Bool {
        let sitCourseLabel = situation.courseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let sitStageLabel = situation.stageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let sitCombined = "\(sitCourseLabel) \(sitStageLabel)".lowercased()
        let className = rawClassName.lowercased()

        // 1. Número de curso (1, 2, 3, 4, etc.)
        let expectedCourse: Int = course > 0 ? course : (extractCourseNumber(from: className) ?? 0)
        let sitCourseNumber = extractCourseNumber(from: sitCourseLabel) ?? extractCourseNumber(from: sitCombined)

        if expectedCourse > 0, let sitNum = sitCourseNumber {
            if sitNum != expectedCourse {
                return false
            }
        }

        // 2. Etapa educativa (por palabras completas: "Primero A" no es Primaria)
        let isClassBach = hasStage(className, .bachillerato)
        let isClassEso = hasStage(className, .eso)
        let isClassPrimaria = hasStage(className, .primaria)

        let isSitBach = hasStage(sitCombined, .bachillerato)
        let isSitEso = hasStage(sitCombined, .eso)
        let isSitPrimaria = hasStage(sitCombined, .primaria)

        if isClassBach {
            return isSitBach || (!isSitEso && !isSitPrimaria)
        } else if isClassEso {
            return isSitEso || (!isSitBach && !isSitPrimaria)
        } else if isClassPrimaria {
            return isSitPrimaria
        }

        // 3. Fallback a etiqueta de curso si no se identificó etapa especial
        let sitLabel = sitCourseLabel.lowercased().filter { $0.isLetter || $0.isNumber }
        let classLabel = className.filter { $0.isLetter || $0.isNumber }
        return !sitLabel.isEmpty && (classLabel.contains(sitLabel) || sitLabel.contains(classLabel))
    }

    private enum Stage { case bachillerato, eso, primaria }

    private static func hasStage(_ text: String, _ stage: Stage) -> Bool {
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return tokens.contains { token in
            switch stage {
            case .bachillerato: return token.hasPrefix("bach") || ["bac", "bto", "bat"].contains(token)
            case .eso: return token == "eso" || token.hasPrefix("secundaria")
            case .primaria: return token.hasPrefix("primaria") || ["prim", "pri"].contains(token)
            }
        }
    }
}
