import SwiftUI
import MiGestorKit

struct NotebookGroupBoardView: View {
    @ObservedObject var bridge: KmpBridge
    let groups: [NotebookWorkGroup]
    let classSituations: [LearningSituation]
    let onToast: (String, NotebookToastStyle) -> Void
    let onCreateGroup: () -> Void

    @State private var showingAutoCompose = false

    private var data: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var students: [Student] {
        guard let data else { return [] }
        return data.sheet.rows.map(\.student).sorted {
            let left = "\($0.lastName) \($0.firstName)"
            let right = "\($1.lastName) \($1.firstName)"
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private var groupedIds: Set<Int64> {
        guard let data else { return [] }
        return Set(data.sheet.workGroupMembers.filter { member in
            groups.contains(where: { $0.id == member.groupId })
        }.map(\.studentId))
    }

    private var ungroupedStudents: [Student] {
        students.filter { !groupedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    onCreateGroup()
                } label: {
                    Label("Nuevo grupo", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    showingAutoCompose = true
                } label: {
                    Label("Agrupar automáticamente", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(students.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    boardColumn(
                        title: "Sin grupo",
                        count: ungroupedStudents.count,
                        students: ungroupedStudents,
                        group: nil
                    )
                    ForEach(groups, id: \.id) { group in
                        boardColumn(
                            title: group.name,
                            count: students(in: group).count,
                            students: students(in: group),
                            group: group
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingAutoCompose) {
            if let data {
                NotebookGroupAutoComposeSheet(
                    studentCount: students.count,
                    classSituations: classSituations
                ) { groupCount, strategy, mixSex, spreadInjured, situationId in
                    bridge.autoComposeNotebookWorkGroups(
                        groupCount: groupCount,
                        strategy: strategy,
                        mixSex: mixSex,
                        spreadInjured: spreadInjured,
                        learningSituationId: situationId,
                        tabId: NotebookWorkGroupPolicy.canonicalTabId(
                            tabs: data.sheet.tabs,
                            requestedTabId: bridge.selectedNotebookTabId,
                            selectedTabId: bridge.selectedNotebookTabId
                        )
                    )
                    onToast("Grupos creados", .success)
                }
            }
        }
    }

    private func students(in group: NotebookWorkGroup) -> [Student] {
        guard let data else { return [] }
        let ids = NotebookWorkGroupPolicy.memberIds(group: group, members: data.sheet.workGroupMembers)
        return students.filter { ids.contains($0.id) }
    }

    private func boardColumn(
        title: String,
        count: Int,
        students: [Student],
        group: NotebookWorkGroup?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NotebookStyle.primaryTint.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(students, id: \.id) { student in
                        studentChip(student)
                            .draggable(String(student.id))
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 240)
            .background(IOSAppStyle.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NotebookStyle.softBorder, lineWidth: 1)
            )
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, group: group)
            }
        }
        .frame(width: 220)
    }

    private func studentChip(_ student: Student) -> some View {
        HStack(spacing: 8) {
            Text("\(student.lastName), \(student.firstName)")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func handleDrop(items: [String], group: NotebookWorkGroup?) -> Bool {
        let studentIds = items.compactMap { Int64($0) }
        guard !studentIds.isEmpty else { return false }
        bridge.assignStudentsToNotebookGroup(
            groupId: group?.id,
            studentIds: studentIds,
            tabId: group?.tabId
        )
        return true
    }
}

private struct NotebookGroupAutoComposeSheet: View {
    let studentCount: Int
    let classSituations: [LearningSituation]
    let onCompose: (Int32, String, Bool, Bool, Int64?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groupCount: Int
    @State private var strategy = "heterogeneous_grade"
    @State private var mixSex = true
    @State private var spreadInjured = true
    @State private var selectedSituationId: Int64? = nil

    init(
        studentCount: Int,
        classSituations: [LearningSituation],
        onCompose: @escaping (Int32, String, Bool, Bool, Int64?) -> Void
    ) {
        self.studentCount = studentCount
        self.classSituations = classSituations
        self.onCompose = onCompose
        let suggested = max(2, min(6, studentCount / 4))
        _groupCount = State(initialValue: max(2, min(max(studentCount, 2), suggested)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tamaño") {
                    Stepper(value: $groupCount, in: 2...max(2, studentCount)) {
                        Text("\(groupCount) grupos")
                    }
                }
                Section("Criterio") {
                    Picker("Reparto", selection: $strategy) {
                        Text("Heterogéneos por nota").tag("heterogeneous_grade")
                        Text("Homogéneos por nota").tag("homogeneous_grade")
                        Text("Azar equilibrado").tag("random_balanced")
                    }
                    Toggle("Mezclar chicos y chicas", isOn: $mixSex)
                    Toggle("Repartir alumnado lesionado", isOn: $spreadInjured)
                }
                if !classSituations.isEmpty {
                    Section("Situación de aprendizaje") {
                        Picker("Asociar a", selection: $selectedSituationId) {
                            Text("Ninguna").tag(nil as Int64?)
                            ForEach(classSituations, id: \.id) { situation in
                                Text(situation.title).tag(situation.id as Int64?)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agrupar automáticamente")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear grupos") {
                        onCompose(Int32(groupCount), strategy, mixSex, spreadInjured, selectedSituationId)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 420)
        #endif
    }
}
