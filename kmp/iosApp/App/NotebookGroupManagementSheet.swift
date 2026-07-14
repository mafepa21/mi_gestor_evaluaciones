import SwiftUI
import MiGestorKit

struct NotebookGroupManagementSheet: View {
    @ObservedObject var bridge: KmpBridge
    let onToast: (String, NotebookToastStyle) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editGroupTarget: NotebookWorkGroup? = nil
    @State private var showingEditSheet = false

    @State private var loadingSituations = false
    @State private var classSituations: [LearningSituation] = []

    private var data: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var activeTabId: String? {
        guard let data = data else { return nil }
        let tabs = data.sheet.tabs.filter { $0.parentTabId == nil }
        let source = tabs.isEmpty ? data.sheet.tabs : tabs
        let orderedTabs = source.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
        if let selected = bridge.selectedNotebookTabId,
           orderedTabs.contains(where: { $0.id == selected }) {
            return selected
        }
        return orderedTabs.first?.id
    }

    private var currentGroups: [NotebookWorkGroup] {
        guard let data = data else { return [] }
        let tabId = activeTabId
        return data.sheet.workGroups
            .filter { tabId == nil || $0.tabId == tabId }
            .sorted { $0.order < $1.order }
    }

    private func courseLabel(for schoolClass: SchoolClass) -> String {
        let lowercasedName = schoolClass.name.lowercased()
        if lowercasedName.contains("bach") {
            return "\(schoolClass.course)º Bachillerato"
        }
        if lowercasedName.contains("eso") || (1...4).contains(schoolClass.course) {
            return "\(schoolClass.course)º ESO"
        }
        return "\(schoolClass.course)º"
    }

    private func cleanLabel(_ label: String) -> String {
        let lower = label.lowercased()
        let charactersToKeep = "0123456789abcdefghijklmnopqrstuvwxyz"
        let filtered = lower.filter { charactersToKeep.contains($0) }
        return filtered
            .replacingOccurrences(of: "bachillerato", with: "bach")
            .replacingOccurrences(of: "de", with: "")
    }

    private func isSituation(_ situation: LearningSituation, matchingClass schoolClass: SchoolClass) -> Bool {
        let classLabel = courseLabel(for: schoolClass)
        let sitLabel = situation.courseLabel
        
        let cleanClass = cleanLabel(classLabel)
        let cleanSit = cleanLabel(sitLabel)
        
        return cleanClass == cleanSit
    }

    private func loadClassLearningSituations() {
        guard let classId = data?.sheet.classId else { return }
        guard let schoolClass = bridge.classes.first(where: { $0.id == classId }) else { return }
        loadingSituations = true
        Task {
            do {
                let situations = try await bridge.learningSituations()
                var linked: [LearningSituation] = []
                var other: [LearningSituation] = []
                for sit in situations {
                    guard isSituation(sit, matchingClass: schoolClass) else { continue }
                    
                    let links = try await bridge.learningSituationClassLinks(id: sit.id)
                    if links.contains(where: { $0.classId == classId }) {
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
            List {
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
                                        HStack(spacing: 6) {
                                            Text("\(memberCount(group.id)) alumnos")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            if let sitId = group.learningSituationId?.int64Value,
                                               let situation = classSituations.first(where: { $0.id == sitId }) {
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
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Grupos de trabajo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                NotebookGroupEditSheet(
                    bridge: bridge,
                    group: editGroupTarget,
                    classSituations: classSituations
                ) { name, situationId in
                    let classId = data?.sheet.classId
                    Task {
                        if let situationId = situationId, let classId = classId {
                            do {
                                try await bridge.addLearningSituationClassLink(situationId: situationId, classId: classId)
                            } catch {
                                // ignore
                            }
                        }
                        await MainActor.run {
                            if let target = editGroupTarget {
                                bridge.updateNotebookWorkGroup(groupId: target.id, name: name, learningSituationId: situationId)
                                onToast("Grupo actualizado", .success)
                            } else {
                                bridge.saveNotebookWorkGroup(name: name, learningSituationId: situationId)
                                onToast("Grupo creado", .success)
                            }
                        }
                    }
                }
                #if os(macOS)
                .frame(width: 420, height: 280)
                #endif
            }
            .onAppear {
                loadClassLearningSituations()
            }
        }
    }

    private func memberCount(_ groupId: Int64) -> Int {
        guard let data = data else { return 0 }
        let tabId = activeTabId
        return data.sheet.workGroupMembers
            .filter { $0.groupId == groupId && (tabId == nil || $0.tabId == tabId) }
            .count
    }
}

struct NotebookGroupEditSheet: View {
    let bridge: KmpBridge
    let group: NotebookWorkGroup?
    let classSituations: [LearningSituation]
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
                    if classSituations.isEmpty {
                        Picker("Situación asociada", selection: $selectedSituationId) {
                            Text("No hay situaciones creadas")
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

    private var activeTabId: String? {
        guard let data = data else { return nil }
        let tabs = data.sheet.tabs.filter { $0.parentTabId == nil }
        let source = tabs.isEmpty ? data.sheet.tabs : tabs
        let orderedTabs = source.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
        if let selected = bridge.selectedNotebookTabId,
           orderedTabs.contains(where: { $0.id == selected }) {
            return selected
        }
        return orderedTabs.first?.id
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
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Buscar alumno...")
                .padding()
                .background(IOSAppStyle.pageBackground)

            List {
                Section {
                    ForEach(filteredStudents, id: \.id) { student in
                        let isMember = isStudentInCurrentGroup(student.id)
                        let otherGroupName = studentOtherGroupName(student.id)

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

    private func isStudentInCurrentGroup(_ studentId: Int64) -> Bool {
        guard let data = data else { return false }
        let tabId = activeTabId
        return data.sheet.workGroupMembers.contains {
            $0.studentId == studentId && $0.groupId == group.id && (tabId == nil || $0.tabId == tabId)
        }
    }

    private func studentOtherGroupName(_ studentId: Int64) -> String? {
        guard let data = data else { return nil }
        let tabId = activeTabId
        guard let member = data.sheet.workGroupMembers.first(where: {
            $0.studentId == studentId && $0.groupId != group.id && (tabId == nil || $0.tabId == tabId)
        }) else { return nil }

        return data.sheet.workGroups.first(where: { $0.id == member.groupId })?.name
    }

    private func toggleStudentMembership(_ studentId: Int64, isMember: Bool) {
        if isMember {
            bridge.assignStudentsToNotebookGroup(groupId: nil, studentIds: [studentId])
        } else {
            bridge.assignStudentsToNotebookGroup(groupId: group.id, studentIds: [studentId])
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
