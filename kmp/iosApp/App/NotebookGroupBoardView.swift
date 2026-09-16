import SwiftUI
import MiGestorKit

final class WorkGroupBoardDraft: ObservableObject {
    struct GroupItem: Identifiable, Equatable {
        let id: Int64
        var name: String
        var tabId: String
        var learningSituationId: Int64?
        var isTemporary: Bool
    }

    @Published private(set) var groups: [GroupItem] = []
    @Published private(set) var membership: [Int64: Int64] = [:]

    private var pendingMutations = 0
    private var lastLocalMemberCount = 0

    func ingest(groups remoteGroups: [NotebookWorkGroup], members: [NotebookWorkGroupMember], force: Bool = false) {
        remapTemporaryIds(from: remoteGroups)

        let remoteMembership = Dictionary(uniqueKeysWithValues: members.map { ($0.studentId, $0.groupId) })
        if !force, remoteMembership.count < membership.count {
            return
        }
        if !force, remoteGroups.isEmpty, !groups.isEmpty {
            return
        }

        var nextGroups = remoteGroups
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.id < rhs.id
            }
            .map { group in
                GroupItem(
                    id: group.id,
                    name: group.name,
                    tabId: group.tabId,
                    learningSituationId: group.learningSituationId?.int64Value,
                    isTemporary: false
                )
            }

        let unmatchedTemps = groups.filter { temp in
            temp.isTemporary && !nextGroups.contains(where: { $0.name == temp.name })
        }
        nextGroups.append(contentsOf: unmatchedTemps)

        var nextMembership = remoteMembership
        for (studentId, groupId) in membership where nextMembership[studentId] == nil {
            nextMembership[studentId] = groupId
        }

        groups = nextGroups
        membership = nextMembership
        lastLocalMemberCount = nextMembership.count
        if remoteMembership.count >= lastLocalMemberCount {
            pendingMutations = 0
        }
    }

    private func remapTemporaryIds(from remoteGroups: [NotebookWorkGroup]) {
        guard groups.contains(where: \.isTemporary) else { return }
        var remapped: [Int64: Int64] = [:]
        var nextGroups = groups
        for index in nextGroups.indices {
            let local = nextGroups[index]
            guard local.isTemporary,
                  let remote = remoteGroups.first(where: { $0.name == local.name }) else { continue }
            remapped[local.id] = remote.id
            nextGroups[index] = GroupItem(
                id: remote.id,
                name: remote.name,
                tabId: remote.tabId,
                learningSituationId: remote.learningSituationId?.int64Value,
                isTemporary: false
            )
        }
        guard !remapped.isEmpty else { return }
        groups = nextGroups
        var nextMembership = membership
        for (studentId, groupId) in membership {
            if let resolved = remapped[groupId] {
                nextMembership[studentId] = resolved
            }
        }
        membership = nextMembership
    }

    func addTemporaryGroup(name: String, tabId: String, learningSituationId: Int64?) {
        pendingMutations += 1
        let id = -Int64(Date().timeIntervalSince1970 * 1000)
        groups.append(
            GroupItem(
                id: id,
                name: name,
                tabId: tabId,
                learningSituationId: learningSituationId,
                isTemporary: true
            )
        )
    }

    func applyComposed(_ composed: [ComposedWorkGroup], tabId: String, learningSituationId: Int64?) {
        pendingMutations += 1
        var nextGroups: [GroupItem] = []
        var nextMembership: [Int64: Int64] = [:]
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for (index, group) in composed.enumerated() {
            let id = -(now + Int64(index) + 1)
            nextGroups.append(
                GroupItem(
                    id: id,
                    name: group.name,
                    tabId: tabId,
                    learningSituationId: learningSituationId,
                    isTemporary: true
                )
            )
            for studentId in group.studentIds {
                nextMembership[kotlinInt64(studentId)] = id
            }
        }
        groups = nextGroups
        membership = nextMembership
        lastLocalMemberCount = nextMembership.count
    }

    func applyImported(
        _ imported: [(name: String, studentIds: [Int64])],
        tabId: String,
        learningSituationId: Int64?
    ) {
        pendingMutations += 1
        var nextGroups: [GroupItem] = []
        var nextMembership: [Int64: Int64] = [:]
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for (index, group) in imported.enumerated() {
            let id = -(now + Int64(index) + 1)
            nextGroups.append(
                GroupItem(
                    id: id,
                    name: group.name,
                    tabId: tabId,
                    learningSituationId: learningSituationId,
                    isTemporary: true
                )
            )
            for studentId in group.studentIds {
                nextMembership[studentId] = id
            }
        }
        groups = nextGroups
        membership = nextMembership
        lastLocalMemberCount = nextMembership.count
    }

    func move(studentIds: [Int64], to groupId: Int64?) {
        pendingMutations += 1
        for studentId in studentIds {
            if let groupId {
                membership[studentId] = groupId
            } else {
                membership.removeValue(forKey: studentId)
            }
        }
        lastLocalMemberCount = membership.count
    }

    func removeGroup(id: Int64) {
        pendingMutations += 1
        groups.removeAll { $0.id == id }
        membership = membership.filter { $0.value != id }
        lastLocalMemberCount = membership.count
    }

    private func kotlinInt64(_ value: Any) -> Int64 {
        if let number = value as? KotlinLong {
            return number.int64Value
        }
        if let number = value as? Int64 {
            return number
        }
        return 0
    }

    func students(in groupId: Int64?, from all: [Student]) -> [Student] {
        all.filter { student in
            let assigned = membership[student.id]
            if let groupId {
                return assigned == groupId
            }
            return assigned == nil
        }
    }
}

struct NotebookGroupBoardView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var draft: WorkGroupBoardDraft
    let groups: [NotebookWorkGroup]
    let classSituations: [LearningSituation]
    let onToast: (String, NotebookToastStyle) -> Void
    let onCreateGroup: () -> Void
    let onImportExcel: () -> Void

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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onCreateGroup) {
                    Label("Nuevo grupo", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button(action: onImportExcel) {
                    Label("Importar Excel", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button {
                    showingAutoCompose = true
                } label: {
                    Label("Agrupar automáticamente", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(students.isEmpty)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            GeometryReader { geo in
                let columnCount = max(draft.groups.count + 1, 1)
                let spacing: CGFloat = 8
                let available = max(geo.size.width - 32, 160)
                let columnWidth = max((available - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount), 112)

                HStack(alignment: .top, spacing: spacing) {
                    boardColumn(
                        title: "Sin grupo",
                        count: draft.students(in: nil, from: students).count,
                        students: draft.students(in: nil, from: students),
                        groupId: nil,
                        height: geo.size.height
                    )
                    .frame(width: columnWidth)

                    ForEach(draft.groups) { group in
                        boardColumn(
                            title: group.name,
                            count: draft.students(in: group.id, from: students).count,
                            students: draft.students(in: group.id, from: students),
                            groupId: group.id,
                            height: geo.size.height
                        )
                        .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, 16)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .onAppear {
            seedDraft()
        }
        .appOnChange(of: groups.map(\.id)) { _ in
            seedDraft()
        }
        .appOnChange(of: memberSignature) { _ in
            seedDraft()
        }
        .sheet(isPresented: $showingAutoCompose) {
            if let data {
                NotebookGroupAutoComposeSheet(
                    studentCount: students.count,
                    classSituations: classSituations
                ) { groupCount, strategy, mixSex, spreadInjured, situationId in
                    let tabId = NotebookWorkGroupPolicy.canonicalTabId(
                        tabs: data.sheet.tabs,
                        requestedTabId: bridge.selectedNotebookTabId,
                        selectedTabId: bridge.selectedNotebookTabId
                    ) ?? data.sheet.tabs.first?.id
                    let composed = bridge.autoComposeNotebookWorkGroups(
                        groupCount: groupCount,
                        strategy: strategy,
                        mixSex: mixSex,
                        spreadInjured: spreadInjured,
                        learningSituationId: situationId,
                        tabId: tabId
                    )
                    draft.applyComposed(composed, tabId: tabId ?? "", learningSituationId: situationId)
                    onToast("Grupos creados", .success)
                }
            }
        }
    }

    private var memberSignature: String {
        guard let data else { return "" }
        return data.sheet.workGroupMembers.map { "\($0.groupId):\($0.studentId)" }.joined(separator: ",")
    }

    private func seedDraft() {
        guard let data else { return }
        draft.ingest(groups: groups, members: data.sheet.workGroupMembers)
    }

    private func boardColumn(
        title: String,
        count: Int,
        students: [Student],
        groupId: Int64?,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NotebookStyle.primaryTint.opacity(0.14), in: Capsule())
            }

            ViewThatFits(in: .vertical) {
                studentStack(students)
                ScrollView {
                    studentStack(students)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: max(height - 48, 120), alignment: .top)
            .background(IOSAppStyle.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NotebookStyle.softBorder, lineWidth: 1)
            )
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, groupId: groupId)
            }
        }
    }

    private func studentStack(_ students: [Student]) -> some View {
        VStack(spacing: 2) {
            ForEach(students, id: \.id) { student in
                studentChip(student)
                    .draggable(String(student.id))
            }
            Spacer(minLength: 0)
        }
    }

    private func studentChip(_ student: Student) -> some View {
        Text("\(student.lastName), \(student.firstName)")
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func handleDrop(items: [String], groupId: Int64?) -> Bool {
        let studentIds = items.compactMap { Int64($0) }
        guard !studentIds.isEmpty else { return false }
        if let groupId, groupId < 0 {
            return false
        }
        draft.move(studentIds: studentIds, to: groupId)
        bridge.assignStudentsToNotebookGroup(
            groupId: groupId,
            studentIds: studentIds,
            tabId: draft.groups.first(where: { $0.id == groupId })?.tabId
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
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }
}
