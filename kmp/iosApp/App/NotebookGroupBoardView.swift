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

    private var pendingAssignments: [Int64: Set<Int64>] = [:]
    private var nextTemporaryId: Int64 = -1
    /// Movimientos locales recientes: una recarga con datos viejos no los pisa (caducan solos).
    private var recentMoves: [Int64: (groupId: Int64?, at: Date)] = [:]
    private static let recentMoveGrace: TimeInterval = 2.0

    private func makeTemporaryId() -> Int64 {
        defer { nextTemporaryId -= 1 }
        return nextTemporaryId
    }

    func ingest(
        groups remoteGroups: [NotebookWorkGroup],
        members: [NotebookWorkGroupMember],
        force: Bool = false,
        onResolvePendingAssignments: ((_ realGroupId: Int64, _ studentIds: [Int64], _ tabId: String?) -> Void)? = nil
    ) {
        let remapped = remapTemporaryIds(from: remoteGroups, onResolve: onResolvePendingAssignments)

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

        let pendingTemps = groups.filter { temp in
            temp.isTemporary && !nextGroups.contains(where: {
                $0.id == temp.id || $0.name.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(temp.name.trimmingCharacters(in: .whitespaces)) == .orderedSame
            })
        }
        nextGroups.append(contentsOf: pendingTemps)

        let remoteMembership = Dictionary(uniqueKeysWithValues: members.map { ($0.studentId, $0.groupId) })
        var nextMembership = remoteMembership

        let pendingTempIds = Set(pendingTemps.map(\.id))
        let resolvedRealGroupIds = Set(remapped.values)

        for (studentId, groupId) in membership {
            if pendingTempIds.contains(groupId) {
                nextMembership[studentId] = groupId
            } else if resolvedRealGroupIds.contains(groupId) && remoteMembership[studentId] != groupId {
                nextMembership[studentId] = groupId
            }
        }

        let now = Date()
        let knownGroupIds = Set(nextGroups.map(\.id))
        for (studentId, move) in recentMoves {
            if now.timeIntervalSince(move.at) > Self.recentMoveGrace || remoteMembership[studentId] == move.groupId {
                recentMoves.removeValue(forKey: studentId)
                continue
            }
            if let target = move.groupId {
                guard knownGroupIds.contains(target) else { continue }
                nextMembership[studentId] = target
            } else {
                nextMembership.removeValue(forKey: studentId)
            }
        }

        if groups != nextGroups { groups = nextGroups }
        if membership != nextMembership { membership = nextMembership }
    }

    @discardableResult
    private func remapTemporaryIds(
        from remoteGroups: [NotebookWorkGroup],
        onResolve: ((_ realGroupId: Int64, _ studentIds: [Int64], _ tabId: String?) -> Void)? = nil
    ) -> [Int64: Int64] {
        guard groups.contains(where: \.isTemporary) else { return [:] }
        var remapped: [Int64: Int64] = [:]
        var nextGroups = groups
        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let localRealIds = Set(nextGroups.filter { !$0.isTemporary }.map(\.id))
        var unclaimed = remoteGroups
            .sorted { $0.order != $1.order ? $0.order < $1.order : $0.id < $1.id }
            .filter { !localRealIds.contains($0.id) }

        func claim(_ remote: NotebookWorkGroup, for index: Int) {
            let local = nextGroups[index]
            unclaimed.removeAll { $0.id == remote.id }
            remapped[local.id] = remote.id
            nextGroups[index] = GroupItem(
                id: remote.id,
                name: remote.name,
                tabId: remote.tabId,
                learningSituationId: remote.learningSituationId?.int64Value,
                isTemporary: false
            )
            if let pendingStudentIds = pendingAssignments[local.id], !pendingStudentIds.isEmpty {
                onResolve?(remote.id, Array(pendingStudentIds), remote.tabId)
                pendingAssignments.removeValue(forKey: local.id)
            }
        }

        // 1) Mismo nombre, cada grupo real se usa una sola vez.
        for index in nextGroups.indices where nextGroups[index].isTemporary {
            if let remote = unclaimed.first(where: { normalized($0.name) == normalized(nextGroups[index].name) }) {
                claim(remote, for: index)
            }
        }
        // 2) Si el sistema renombró (p. ej. "Grupo (2)"), se emparejan por orden con los sobrantes.
        for index in nextGroups.indices where nextGroups[index].isTemporary {
            let base = normalized(nextGroups[index].name)
            if let remote = unclaimed.first(where: { normalized($0.name).hasPrefix(base) }) {
                claim(remote, for: index)
            }
        }
        guard !remapped.isEmpty else { return [:] }
        groups = nextGroups
        var nextMembership = membership
        for (studentId, groupId) in membership {
            if let resolved = remapped[groupId] {
                nextMembership[studentId] = resolved
            }
        }
        membership = nextMembership
        return remapped
    }

    func updateGroup(id: Int64, name: String, learningSituationId: Int64?) {
        if let index = groups.firstIndex(where: { $0.id == id }) {
            groups[index].name = name
            groups[index].learningSituationId = learningSituationId
        }
    }

    func addTemporaryGroup(name: String, tabId: String, learningSituationId: Int64?) {
        let id = makeTemporaryId()
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
        pendingAssignments.removeAll()
        recentMoves.removeAll()
        var nextGroups: [GroupItem] = []
        var nextMembership: [Int64: Int64] = [:]
        for group in composed {
            let id = makeTemporaryId()
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
    }

    func applyImported(
        _ imported: [(name: String, studentIds: [Int64])],
        tabId: String,
        learningSituationId: Int64?
    ) {
        pendingAssignments.removeAll()
        recentMoves.removeAll()
        var nextGroups: [GroupItem] = []
        var nextMembership: [Int64: Int64] = [:]
        for group in imported {
            let id = makeTemporaryId()
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
    }

    func move(studentIds: [Int64], to groupId: Int64?) {
        for studentId in studentIds {
            recentMoves[studentId] = (groupId, Date())
            for tempId in pendingAssignments.keys {
                pendingAssignments[tempId]?.remove(studentId)
                if pendingAssignments[tempId]?.isEmpty == true {
                    pendingAssignments.removeValue(forKey: tempId)
                }
            }
            if let groupId {
                membership[studentId] = groupId
                if groupId < 0 {
                    pendingAssignments[groupId, default: []].insert(studentId)
                }
            } else {
                membership.removeValue(forKey: studentId)
            }
        }
    }

    func removeGroup(id: Int64) {
        groups.removeAll { $0.id == id }
        membership = membership.filter { $0.value != id }
        pendingAssignments.removeValue(forKey: id)
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

    /// Reparto de alumnado por grupo en una sola pasada (clave `nil` = sin grupo).
    func studentsByGroup(from all: [Student]) -> [Int64?: [Student]] {
        Dictionary(grouping: all, by: { membership[$0.id] })
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
    let onGenerateCooperative: () -> Void

    @State private var showingAutoCompose = false
    @State private var targetedColumnKey: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            ViewThatFits(in: .horizontal) {
                actionBar(compact: false)
                actionBar(compact: true)
            }
            .groupGlassContainer(spacing: 8)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            GeometryReader { geo in
                let columnCount = max(draft.groups.count + 1, 1)
                let spacing: CGFloat = 8
                let available = max(geo.size.width - 32, 160)
                let isCompact = horizontalSizeClass == .compact
                let columnWidth = isCompact
                    ? max(available * 0.82, 220)
                    : max((available - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount), 160)
                let grouped = draft.studentsByGroup(from: students)

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: spacing) {
                        boardColumn(
                            title: "Sin grupo",
                            students: grouped[nil] ?? [],
                            groupId: nil,
                            height: geo.size.height
                        )
                        .frame(width: columnWidth)

                        ForEach(draft.groups) { group in
                            boardColumn(
                                title: group.name,
                                students: grouped[group.id] ?? [],
                                groupId: group.id,
                                height: geo.size.height
                            )
                            .frame(width: columnWidth)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .onAppear {
            seedDraft()
        }
        .appOnChange(of: groupSignature) { _ in
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

    private var groupSignature: Int {
        var hasher = Hasher()
        for group in groups {
            hasher.combine(group.id)
            hasher.combine(group.name)
            hasher.combine(group.order)
            hasher.combine(group.learningSituationId?.int64Value ?? -1)
        }
        return hasher.finalize()
    }

    private var memberSignature: Int {
        guard let data else { return 0 }
        var hasher = Hasher()
        for member in data.sheet.workGroupMembers {
            hasher.combine(member.groupId)
            hasher.combine(member.studentId)
        }
        return hasher.finalize()
    }

    private func seedDraft() {
        guard let data else { return }
        draft.ingest(groups: groups, members: data.sheet.workGroupMembers) { realGroupId, studentIds, tabId in
            bridge.assignStudentsToNotebookGroup(
                groupId: realGroupId,
                studentIds: studentIds,
                tabId: tabId
            )
        }
    }

    private func actionBar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onCreateGroup) {
                if compact {
                    Image(systemName: "plus").frame(minWidth: 32, minHeight: 32)
                } else {
                    Label("Nuevo grupo", systemImage: "plus").frame(minHeight: 32)
                }
            }
            .groupGlassButton(circular: compact)
            .accessibilityLabel("Nuevo grupo")

            Menu {
                Button(action: onImportExcel) {
                    Label("Importar desde Excel", systemImage: "square.and.arrow.down")
                }
                Button(action: onGenerateCooperative) {
                    Label("Equipos cooperativos (IA)", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "ellipsis").frame(minWidth: 32, minHeight: 32)
            }
            .groupGlassButton(circular: true)
            .accessibilityLabel("Más acciones")

            Spacer(minLength: 0)

            Button {
                showingAutoCompose = true
            } label: {
                if compact {
                    Image(systemName: "sparkles").frame(minWidth: 32, minHeight: 32)
                } else {
                    Label("Agrupar automáticamente", systemImage: "sparkles").frame(minHeight: 32)
                }
            }
            .groupGlassButton(prominent: true, circular: compact)
            .disabled(students.isEmpty)
            .accessibilityLabel("Agrupar automáticamente")
        }
    }

    private func boardColumn(
        title: String,
        students: [Student],
        groupId: Int64?,
        height: CGFloat
    ) -> some View {
        let key = groupId.map(String.init) ?? "none"
        let isTargeted = targetedColumnKey == key
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text("\(students.count)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NotebookStyle.primaryTint.opacity(0.14), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(students.count) alumnos")

            ScrollView {
                studentStack(students, currentGroupId: groupId)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: max(height - 48, 120), maxHeight: max(height - 48, 120), alignment: .top)
            .groupSolidCard(highlighted: isTargeted)
            .dropDestination(for: String.self) { items, _ in
                return handleDrop(items: items, groupId: groupId)
            } isTargeted: { targeted in
                if targeted {
                    targetedColumnKey = key
                } else if targetedColumnKey == key {
                    targetedColumnKey = nil
                }
            }
        }
    }

    private func studentStack(_ students: [Student], currentGroupId: Int64?) -> some View {
        VStack(spacing: 8) {
            ForEach(students, id: \.id) { student in
                studentChip(student, currentGroupId: currentGroupId)
                    .draggable(String(student.id))
            }
            Spacer(minLength: 0)
        }
    }

    private func studentChip(_ student: Student, currentGroupId: Int64?) -> some View {
        #if os(iOS)
        let minHeight: CGFloat = 44
        #else
        let minHeight: CGFloat = 32
        #endif
        return Text("\(student.lastName), \(student.firstName)")
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contextMenu {
                // Alternativa accesible y de teclado al arrastre.
                Menu("Mover a…") {
                    if currentGroupId != nil {
                        Button("Sin grupo") { _ = handleDrop(items: [String(student.id)], groupId: nil) }
                    }
                    ForEach(draft.groups.filter { $0.id != currentGroupId }) { group in
                        Button(group.name) { _ = handleDrop(items: [String(student.id)], groupId: group.id) }
                    }
                }
            }
    }

    private func handleDrop(items: [String], groupId: Int64?) -> Bool {
        let studentIds = items.compactMap { Int64($0) }
        guard !studentIds.isEmpty else { return false }

        let resolvedGroupId: Int64?
        if let groupId, groupId < 0 {
            if let temp = draft.groups.first(where: { $0.id == groupId }),
               let real = groups.first(where: {
                   $0.name.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(temp.name.trimmingCharacters(in: .whitespaces)) == .orderedSame
               }) {
                resolvedGroupId = real.id
            } else {
                resolvedGroupId = groupId
            }
        } else {
            resolvedGroupId = groupId
        }

        draft.move(studentIds: studentIds, to: resolvedGroupId)
        if let targetId = resolvedGroupId, targetId >= 0 {
            let tabId = draft.groups.first(where: { $0.id == targetId })?.tabId ?? groups.first(where: { $0.id == targetId })?.tabId
            bridge.assignStudentsToNotebookGroup(
                groupId: targetId,
                studentIds: studentIds,
                tabId: tabId
            )
        } else if resolvedGroupId == nil {
            bridge.assignStudentsToNotebookGroup(
                groupId: nil,
                studentIds: studentIds,
                tabId: groups.first?.tabId
            )
        }
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

// MARK: - Estilo Liquid Glass de grupos

extension View {
    /// Botón de vidrio (iOS/macOS 26) con fallback a los estilos clásicos.
    @ViewBuilder
    func groupGlassButton(prominent: Bool = false, circular: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent).buttonBorderShape(circular ? .circle : .capsule)
            } else {
                self.buttonStyle(.glass).buttonBorderShape(circular ? .circle : .capsule)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent).buttonBorderShape(circular ? .circle : .capsule)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(circular ? .circle : .capsule)
        }
    }

    /// Tarjeta de contenido sólida: el vidrio se reserva para barras y controles.
    func groupSolidCard(highlighted: Bool = false) -> some View {
        self
            .background(
                highlighted ? NotebookStyle.primaryTint.opacity(0.12) : IOSAppStyle.cardBackground,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(highlighted ? NotebookStyle.primaryTint : NotebookStyle.softBorder, lineWidth: highlighted ? 3 : 1)
            )
    }

    /// Agrupa controles de vidrio para que se fundan entre sí (iOS/macOS 26).
    @ViewBuilder
    func groupGlassContainer(spacing: CGFloat = 8) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}
