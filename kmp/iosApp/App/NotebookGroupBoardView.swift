import SwiftUI
import Combine
import MiGestorKit
#if os(macOS)
import AppKit
#endif

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

/// Reparto de la rejilla del tablero de grupos: elige columnas y altura de ficha para que
/// todos los grupos se vean a la vez sin desplazar la pantalla. Es pura para poder probarla.
struct GroupBoardGridLayout: Equatable {
    var columns: Int
    var rows: Int
    var cardWidth: CGFloat
    var cardHeight: CGFloat
    /// Columnas de fichas dentro de cada tarjeta (2 si la tarjeta es ancha).
    var innerColumns: Int
    var chipHeight: CGFloat
    /// `false` si algún grupo no cabe ni con fichas mínimas: esa tarjeta se desplaza por dentro.
    var fitsWithoutScroll: Bool

    static let spacing: CGFloat = 8
    /// Cabecera (nombre + menú), línea de SdA, relleno y huecos fijos de una tarjeta.
    static let cardChrome: CGFloat = 8 * 2 + 32 + 18 + 4 * 2

    static func make(
        cardCount: Int,
        size: CGSize,
        largestGroup: Int,
        chipRange: ClosedRange<CGFloat>,
        allowTwoInnerColumns: Bool = true
    ) -> GroupBoardGridLayout {
        let count = max(cardCount, 1)
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        var bestColumns = 1
        var bestScore = Double.greatestFiniteMagnitude
        for columns in 1...count {
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let cardW = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cardH = (height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            guard cardW > 0, cardH > 0 else { continue }
            // Tarjetas algo más anchas que altas (≈1,25:1) y pocas celdas vacías.
            let score = abs(log(Double(cardW / cardH) / 1.25)) + Double(columns * rows - count) * 0.15
            if score < bestScore {
                bestScore = score
                bestColumns = columns
            }
        }
        let rows = Int((Double(count) / Double(bestColumns)).rounded(.up))
        let cardW = (width - spacing * CGFloat(bestColumns - 1)) / CGFloat(bestColumns)
        let cardH = (height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        let inner = allowTwoInnerColumns && cardW > 300 ? 2 : 1
        let members = max(largestGroup, 4)
        let lines = Int((Double(members) / Double(inner)).rounded(.up))
        let available = cardH - cardChrome - 4 * CGFloat(lines - 1)
        let ideal = (available / CGFloat(lines)).rounded(.down)
        let chip = min(max(ideal, chipRange.lowerBound), chipRange.upperBound)
        return GroupBoardGridLayout(
            columns: bestColumns,
            rows: rows,
            cardWidth: cardW,
            cardHeight: cardH,
            innerColumns: inner,
            chipHeight: chip,
            fitsWithoutScroll: ideal >= chipRange.lowerBound
        )
    }
}

struct NotebookGroupBoardView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var draft: WorkGroupBoardDraft
    let groups: [NotebookWorkGroup]
    let classSituations: [LearningSituation]
    let onToast: (String, NotebookToastStyle) -> Void
    let onCreateGroup: () -> Void
    let onEditGroup: (Int64) -> Void
    let onDeleteGroup: (Int64) -> Void
    let onImportExcel: () -> Void
    let onGenerateCooperative: () -> Void

    @State private var showingAutoCompose = false
    @State private var targetedColumnKey: String?
    @State private var isSelecting = false
    @State private var selectedStudentIds = Set<Int64>()
    @State private var deleteTargetId: Int64?
    /// Marcas Fuerte / Necesita apoyo del curso, por id de alumno (sin «sin marca»).
    @State private var marks: [Int64: WorkGroupMarkUI] = [:]
    /// Nota de técnica por alumno con las columnas elegidas (o sugeridas) del curso.
    @State private var techniqueScores: [Int64: Double] = [:]
    /// Marca que no se pudo guardar, para ofrecer «Reintentar».
    @State private var failedMark: FailedMark?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    #if os(macOS)
    @ScaledMetric(relativeTo: .subheadline) private var maxChipHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .subheadline) private var minChipHeight: CGFloat = 24
    #else
    @ScaledMetric(relativeTo: .subheadline) private var maxChipHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var minChipHeight: CGFloat = 32
    #endif

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

    private var usesStackedLayout: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize >= .accessibility1
    }

    var body: some View {
        let grouped = draft.studentsByGroup(from: students)
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                actionBar(compact: false)
                actionBar(compact: true)
            }
            .groupGlassContainer(spacing: 8)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            unassignedStrip(grouped[nil] ?? [])
                .padding(.horizontal, 16)

            if usesStackedLayout {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(draft.groups) { group in
                            groupCard(group, students: grouped[group.id] ?? [], chipHeight: maxChipHeight, innerColumns: 1, fixedHeight: nil)
                        }
                        newGroupTile.frame(minHeight: 88)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                GeometryReader { geo in
                    let largest = draft.groups.map { grouped[$0.id]?.count ?? 0 }.max() ?? 0
                    let layout = GroupBoardGridLayout.make(
                        cardCount: draft.groups.count + 1,
                        size: CGSize(width: geo.size.width - 32, height: geo.size.height - 16),
                        largestGroup: largest,
                        chipRange: minChipHeight...max(minChipHeight, maxChipHeight)
                    )
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: GroupBoardGridLayout.spacing), count: layout.columns),
                        spacing: GroupBoardGridLayout.spacing
                    ) {
                        ForEach(draft.groups) { group in
                            groupCard(
                                group,
                                students: grouped[group.id] ?? [],
                                chipHeight: layout.chipHeight,
                                innerColumns: layout.innerColumns,
                                fixedHeight: layout.cardHeight
                            )
                        }
                        newGroupTile.frame(height: layout.cardHeight)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedStudentIds.isEmpty {
                selectionBar
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedStudentIds.isEmpty)
        .onAppear {
            seedDraft()
            reloadMarks()
        }
        .appOnChange(of: groupSignature) { _ in
            seedDraft()
            reloadMarks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workGroupMarksDidChange)) { _ in
            reloadMarks()
        }
        .alert(
            "No se pudo guardar la marca",
            isPresented: Binding(
                get: { failedMark != nil },
                set: { if !$0 { failedMark = nil } }
            ),
            presenting: failedMark
        ) { failed in
            Button("Reintentar") { setMark(failed.mark, for: failed.studentIds) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("La marca vuelve a como estaba.")
        }
        .appOnChange(of: memberSignature) { _ in
            seedDraft()
            reloadMarks()
            // Un alumno que ya no está en el curso no puede seguir seleccionado.
            let valid = Set(students.map(\.id))
            selectedStudentIds.formIntersection(valid)
        }
        .alert(
            deleteTitle,
            isPresented: Binding(
                get: { deleteTargetId != nil },
                set: { if !$0 { deleteTargetId = nil } }
            )
        ) {
            Button("Eliminar", role: .destructive) {
                if let id = deleteTargetId { onDeleteGroup(id) }
                deleteTargetId = nil
            }
            Button("Cancelar", role: .cancel) { deleteTargetId = nil }
        } message: {
            Text(deleteMessage(grouped: grouped))
        }
        .sheet(isPresented: $showingAutoCompose) {
            if let data {
                NotebookGroupAutoComposeSheet(
                    bridge: bridge,
                    classId: bridge.currentNotebookClassId,
                    studentCount: students.count,
                    marks: marks,
                    classSituations: classSituations
                ) { choice in
                    let tabId = NotebookWorkGroupPolicy.canonicalTabId(
                        tabs: data.sheet.tabs,
                        requestedTabId: bridge.selectedNotebookTabId,
                        selectedTabId: bridge.selectedNotebookTabId
                    ) ?? data.sheet.tabs.first?.id
                    let composed = bridge.autoComposeNotebookWorkGroups(
                        groupCount: choice.groupCount,
                        strategy: choice.strategy,
                        mixSex: choice.mixSex,
                        spreadInjured: choice.spreadInjured,
                        learningSituationId: choice.situationId,
                        tabId: tabId,
                        skill: choice.skill
                    )
                    draft.applyComposed(composed, tabId: tabId ?? "", learningSituationId: choice.situationId)
                    reloadMarks()
                    onToast("Grupos creados", .success)
                }
            }
        }
    }

    // MARK: Firmas de recarga

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

    // MARK: Barras

    private func actionBar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                toggleSelecting()
            } label: {
                Text(isSelecting ? "Cancelar" : "Seleccionar").frame(minHeight: 32)
            }
            .groupGlassButton()
            .help("Elige varios alumnos para moverlos juntos")

            Button(action: onCreateGroup) {
                if compact {
                    Image(systemName: "plus").frame(minWidth: 32, minHeight: 32)
                } else {
                    Label("Nuevo grupo", systemImage: "plus").frame(minHeight: 32)
                }
            }
            .groupGlassButton(circular: compact)
            .keyboardShortcut("n", modifiers: [.command, .shift])
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
            .help("Más acciones")

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
            .help("Reparte al alumnado en grupos")
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text(selectedStudentIds.count == 1 ? "1 seleccionado" : "\(selectedStudentIds.count) seleccionados")
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 8)
            moveMenu(studentIds: Array(selectedStudentIds), currentGroupId: nil) {
                Label("Mover a…", systemImage: "arrow.right.circle").frame(minHeight: 32)
            }
            .groupGlassButton()
            Menu {
                markMenuItems(studentIds: Array(selectedStudentIds))
            } label: {
                Label("Marcar", systemImage: "star").frame(minHeight: 32)
            }
            .groupGlassButton()
            .accessibilityLabel("Marcar seleccionados")
            Button("Listo") {
                isSelecting = false
                selectedStudentIds.removeAll()
            }
            .groupGlassButton(prominent: true)
        }
        .padding(8)
        .groupGlassContainer(spacing: 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }

    // MARK: Zonas

    private func unassignedStrip(_ students: [Student]) -> some View {
        let isTargeted = targetedColumnKey == "none"
        return HStack(alignment: .center, spacing: 8) {
            Text("Sin grupo · \(students.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            if students.isEmpty {
                Text(isTargeted ? "Soltar aquí" : "Todos tienen grupo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LearningSituationFlowLayout(spacing: 4) {
                        ForEach(students, id: \.id) { student in
                            studentChip(student, currentGroupId: nil, height: minChipHeight, compactWidth: true)
                        }
                    }
                }
                .frame(maxHeight: minChipHeight * 2 + 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .groupSolidCard(highlighted: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items, groupId: nil)
        } isTargeted: { setTargeted($0, key: "none") }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sin grupo, \(students.count) alumnos")
    }

    private func groupCard(
        _ group: WorkGroupBoardDraft.GroupItem,
        students: [Student],
        chipHeight: CGFloat,
        innerColumns: Int,
        fixedHeight: CGFloat?
    ) -> some View {
        let key = String(group.id)
        let isTargeted = targetedColumnKey == key
        let situation = situationTitle(group.learningSituationId)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(students.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                if isTargeted {
                    Text("Soltar aquí")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(NotebookStyle.primaryTint, in: Capsule())
                }
                Spacer(minLength: 0)
                groupMenu(group)
            }
            .frame(minHeight: 32)

            groupSummary(students)

            Group {
                if let situation {
                    Label("SA · \(situation)", systemImage: "link")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Sin SA · no aparece en Torneos", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .frame(minHeight: 18)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: innerColumns),
                    spacing: 4
                ) {
                    ForEach(students, id: \.id) { student in
                        studentChip(student, currentGroupId: group.id, height: chipHeight, compactWidth: false)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: fixedHeight, alignment: .top)
        .frame(minHeight: fixedHeight == nil ? 120 : nil, alignment: .top)
        .groupSolidCard(highlighted: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items, groupId: group.id)
        } isTargeted: { setTargeted($0, key: key) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(group.name), \(students.count) alumnos, \(situation.map { "SA \($0)" } ?? "sin SA")"
                + (summaryText(students).map { ", \($0)" } ?? "")
        )
    }

    private var newGroupTile: some View {
        Button(action: onCreateGroup) {
            Label("Nuevo grupo", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(NotebookStyle.softBorder)
        )
    }

    private func groupMenu(_ group: WorkGroupBoardDraft.GroupItem) -> some View {
        Menu {
            Button {
                onEditGroup(group.id)
            } label: {
                Label("Cambiar nombre…", systemImage: "pencil")
            }
            Menu {
                Picker("Situación de aprendizaje", selection: Binding(
                    get: { group.learningSituationId },
                    set: { setSituation($0, for: group) }
                )) {
                    Text("Ninguna").tag(nil as Int64?)
                    ForEach(classSituations, id: \.id) { situation in
                        Text(situation.title).tag(situation.id as Int64?)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(group.learningSituationId == nil ? "Asociar a una SA" : "Cambiar SA", systemImage: "link")
            }
            .disabled(classSituations.isEmpty)
            Divider()
            Button(role: .destructive) {
                deleteTargetId = group.id
            } label: {
                Label("Eliminar grupo…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                #if os(macOS)
                .frame(width: 32, height: 32)
                #else
                .frame(width: 44, height: 44)
                #endif
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #if os(iOS)
        .padding(.vertical, -6)
        #endif
        .accessibilityLabel("Opciones de \(group.name)")
        .help("Opciones del grupo")
        .disabled(group.isTemporary)
    }

    // MARK: Fichas

    private func studentChip(_ student: Student, currentGroupId: Int64?, height: CGFloat, compactWidth: Bool) -> some View {
        let isSelected = selectedStudentIds.contains(student.id)
        let name = "\(student.lastName), \(student.firstName)"
        let dragIds = isSelected ? Array(selectedStudentIds) : [student.id]
        return HStack(spacing: 6) {
            if isSelecting || isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? NotebookStyle.primaryTint : Color.secondary)
                    .accessibilityHidden(true)
            }
            Text(name)
                .font(.subheadline)
                .lineLimit(dynamicTypeSize >= .accessibility1 ? 2 : 1)
            if let mark = marks[student.id] {
                if !compactWidth { Spacer(minLength: 0) }
                Image(systemName: mark.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(mark.tint)
                    .accessibilityHidden(true)
                    .help(mark.title)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: compactWidth ? nil : .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(
            isSelected ? NotebookStyle.primaryTint.opacity(0.14) : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? NotebookStyle.primaryTint : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            handleChipTap(student.id)
        }
        .draggable(dragIds.map(String.init).joined(separator: ",")) {
            Text(dragIds.count > 1 ? "\(dragIds.count) alumnos" : name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(NotebookStyle.primaryTint, in: Capsule())
        }
        .contextMenu {
            // Alternativa sin arrastre (teclado, puntero y VoiceOver).
            moveMenu(studentIds: dragIds, currentGroupId: currentGroupId) {
                Text(dragIds.count > 1 ? "Mover \(dragIds.count) a…" : "Mover a…")
            }
            Divider()
            markMenuItems(studentIds: dragIds)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + (marks[student.id].map { ", \($0.spokenTitle)" } ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelecting ? "Toca para elegir" : "")
        .accessibilityActions {
            if currentGroupId != nil {
                Button("Mover a Sin grupo") { move(dragIds, to: nil) }
            }
            ForEach(draft.groups.filter { $0.id != currentGroupId }) { group in
                Button("Mover a \(group.name)") { move(dragIds, to: group.id) }
            }
            ForEach(WorkGroupMarkUI.allCases.filter { $0 != (marks[student.id] ?? .unmarked) }) { option in
                Button(option == .unmarked ? "Quitar marca" : "Marcar: \(option.spokenTitle)") {
                    setMark(option, for: dragIds)
                }
            }
        }
    }

    // MARK: Marcas

    /// Opciones de marca para el menú contextual y la barra de selección.
    /// Con un solo alumno, la marca actual lleva un check.
    @ViewBuilder
    private func markMenuItems(studentIds: [Int64]) -> some View {
        let current: WorkGroupMarkUI? = studentIds.count == 1 ? (marks[studentIds[0]] ?? .unmarked) : nil
        ForEach(WorkGroupMarkUI.allCases) { option in
            Button {
                setMark(option, for: studentIds)
            } label: {
                Label(option.title, systemImage: current == option ? "checkmark" : option.systemImage)
            }
        }
    }

    private func reloadMarks() {
        guard let classId = bridge.currentNotebookClassId else {
            marks = [:]
            techniqueScores = [:]
            return
        }
        techniqueScores = bridge.workGroupDimensionScores(
            columnIds: bridge.workGroupSkillSelection(classId: classId, dimension: .technique)
        )
        Task {
            // Si falla la lectura se conservan las marcas que ya se veían.
            if let loaded = try? await bridge.workGroupMarks(classId: classId),
               bridge.currentNotebookClassId == classId {
                marks = loaded
            }
        }
    }

    /// Cambio optimista: se ve al momento y vuelve atrás si no se puede guardar.
    private func setMark(_ mark: WorkGroupMarkUI, for studentIds: [Int64]) {
        guard let classId = bridge.currentNotebookClassId, !studentIds.isEmpty else { return }
        let previous = marks
        for id in studentIds {
            marks[id] = mark == .unmarked ? nil : mark
        }
        Task {
            do {
                try await bridge.saveWorkGroupMark(mark, studentIds: studentIds, classId: classId)
                announce(studentIds.count == 1
                         ? (mark == .unmarked ? "Marca quitada" : "Marcado: \(mark.spokenTitle)")
                         : "\(studentIds.count) alumnos: \(mark.spokenTitle)")
            } catch {
                // Si falló a mitad, parte ya quedó guardada: se relee de la base.
                marks = previous
                reloadMarks()
                announce("No se pudo guardar la marca")
                failedMark = FailedMark(mark: mark, studentIds: studentIds)
            }
        }
    }

    private func summaryText(_ students: [Student]) -> String? {
        let strong = students.filter { marks[$0.id] == .strong }.count
        let support = students.filter { marks[$0.id] == .support }.count
        var parts: [String] = []
        if strong > 0 { parts.append(strong == 1 ? "1 fuerte" : "\(strong) fuertes") }
        if support > 0 { parts.append("\(support) apoyo") }
        if let technique = techniqueMean(students) { parts.append("técnica \(technique)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func techniqueMean(_ students: [Student]) -> String? {
        let scores = students.compactMap { techniqueScores[$0.id] }
        guard !scores.isEmpty else { return nil }
        let mean = scores.reduce(0, +) / Double(scores.count)
        return mean.formatted(.number.precision(.fractionLength(1)))
    }

    /// «★ 1 fuerte · ✋ 1 apoyo · Técnica 6,8». Solo si hay algo que contar.
    @ViewBuilder
    private func groupSummary(_ students: [Student]) -> some View {
        let strong = students.filter { marks[$0.id] == .strong }.count
        let support = students.filter { marks[$0.id] == .support }.count
        let technique = techniqueMean(students)
        if strong > 0 || support > 0 || technique != nil {
            HStack(spacing: 8) {
                if strong > 0 {
                    summaryLabel(strong == 1 ? "1 fuerte" : "\(strong) fuertes", mark: .strong)
                }
                if support > 0 {
                    summaryLabel("\(support) apoyo", mark: .support)
                }
                if let technique {
                    Text("Técnica \(technique)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .frame(minHeight: 18)
            .accessibilityHidden(true)
        }
    }

    private func summaryLabel(_ text: String, mark: WorkGroupMarkUI) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: mark.systemImage).foregroundStyle(mark.tint)
        }
        .labelStyle(.titleAndIcon)
    }

    private func moveMenu<LabelView: View>(
        studentIds: [Int64],
        currentGroupId: Int64?,
        @ViewBuilder label: () -> LabelView
    ) -> some View {
        Menu {
            Button("Sin grupo") { move(studentIds, to: nil) }
            ForEach(draft.groups.filter { $0.id != currentGroupId }) { group in
                Button(group.name) { move(studentIds, to: group.id) }
            }
        } label: {
            label()
        }
    }

    // MARK: Acciones

    private func toggleSelecting() {
        isSelecting.toggle()
        if !isSelecting { selectedStudentIds.removeAll() }
    }

    private func handleChipTap(_ studentId: Int64) {
        #if os(macOS)
        let extending = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)
        #else
        let extending = false
        #endif
        guard isSelecting || extending || !selectedStudentIds.isEmpty else { return }
        if selectedStudentIds.contains(studentId) {
            selectedStudentIds.remove(studentId)
        } else {
            selectedStudentIds.insert(studentId)
        }
        announce(selectedStudentIds.count == 1 ? "1 seleccionado" : "\(selectedStudentIds.count) seleccionados")
    }

    private func setTargeted(_ targeted: Bool, key: String) {
        if targeted {
            targetedColumnKey = key
        } else if targetedColumnKey == key {
            targetedColumnKey = nil
        }
    }

    private func setSituation(_ situationId: Int64?, for group: WorkGroupBoardDraft.GroupItem) {
        guard situationId != group.learningSituationId, !group.isTemporary else { return }
        let classId = data?.sheet.classId
        Task { @MainActor in
            var linked = situationId
            if let situationId, let classId {
                do {
                    try await bridge.addLearningSituationClassLink(situationId: situationId, classId: classId)
                } catch {
                    linked = nil
                }
            }
            if situationId != nil, linked == nil {
                onToast("No se pudo asociar la SA", .warning)
                return
            }
            draft.updateGroup(id: group.id, name: group.name, learningSituationId: linked)
            bridge.updateNotebookWorkGroup(groupId: group.id, name: group.name, learningSituationId: linked, tabId: group.tabId)
            onToast(linked == nil ? "SA quitada. Ya no sale en Torneos." : "SA asociada", .success)
        }
    }

    private var deleteTitle: String {
        let name = draft.groups.first(where: { $0.id == deleteTargetId })?.name ?? "este grupo"
        return "¿Eliminar «\(name)»?"
    }

    private func deleteMessage(grouped: [Int64?: [Student]]) -> String {
        guard let id = deleteTargetId else { return "" }
        let count = grouped[id]?.count ?? 0
        var message = count == 1
            ? "Su alumno pasará a «Sin grupo»."
            : "Sus \(count) alumnos pasarán a «Sin grupo»."
        message += " No se borra ningún alumno ni ninguna nota."
        if draft.groups.first(where: { $0.id == id })?.learningSituationId != nil {
            message += " Si es equipo de un torneo, el torneo conserva sus resultados y te avisará de que los grupos han cambiado."
        }
        return message
    }

    private func move(_ studentIds: [Int64], to groupId: Int64?) {
        _ = handleDrop(items: studentIds.map(String.init), groupId: groupId)
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    private func handleDrop(items: [String], groupId: Int64?) -> Bool {
        // Cada elemento puede traer varios alumnos («12,15,20») si se arrastró una selección.
        let studentIds = Array(Set(
            items
                .flatMap { $0.split(separator: ",") }
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
        ))
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

        selectedStudentIds.subtract(studentIds)
        if studentIds.count > 1 {
            let destination = resolvedGroupId.flatMap { id in draft.groups.first(where: { $0.id == id })?.name } ?? "Sin grupo"
            announce("\(studentIds.count) alumnos movidos a \(destination)")
        }
        return true
    }

    private func situationTitle(_ id: Int64?) -> String? {
        guard let id else { return nil }
        return classSituations.first(where: { $0.id == id })?.title ?? "SA asociada"
    }
}

/// Marca que no se pudo guardar: se ofrece «Reintentar» con los mismos datos.
private struct FailedMark {
    let mark: WorkGroupMarkUI
    let studentIds: [Int64]
}

extension WorkGroupMarkUI {
    /// Color del icono. Nunca va solo: siempre con texto o etiqueta de voz.
    var tint: Color {
        switch self {
        case .unmarked: return .secondary
        case .strong: return .orange
        case .support: return .purple
        }
    }
}

/// Lo que elige el docente en «Agrupar automáticamente».
struct NotebookAutoComposeChoice {
    let groupCount: Int32
    let strategy: String
    let mixSex: Bool
    let spreadInjured: Bool
    let situationId: Int64?
    /// Solo con el criterio «Por nivel técnico».
    let skill: WorkGroupSkillRequest?
}

private struct NotebookGroupAutoComposeSheet: View {
    @ObservedObject var bridge: KmpBridge
    let classId: Int64?
    let studentCount: Int
    let marks: [Int64: WorkGroupMarkUI]
    let classSituations: [LearningSituation]
    let onCompose: (NotebookAutoComposeChoice) -> Void

    private static let skillStrategy = "skill_level"

    @Environment(\.dismiss) private var dismiss
    @State private var groupCount: Int
    @State private var strategy = "heterogeneous_grade"
    @State private var mixSex = true
    @State private var spreadInjured = true
    @State private var oneLeaderPerGroup = true
    @State private var spreadLowBehaviour = true
    @State private var selectedSituationId: Int64? = nil
    @State private var techniqueIds: [String] = []
    @State private var behaviourIds: [String] = []
    @State private var leadershipIds: [String] = []
    @State private var didLoad = false

    init(
        bridge: KmpBridge,
        classId: Int64?,
        studentCount: Int,
        marks: [Int64: WorkGroupMarkUI],
        classSituations: [LearningSituation],
        onCompose: @escaping (NotebookAutoComposeChoice) -> Void
    ) {
        self.bridge = bridge
        self.classId = classId
        self.studentCount = studentCount
        self.marks = marks
        self.classSituations = classSituations
        self.onCompose = onCompose
        let suggested = max(2, min(6, studentCount / 4))
        _groupCount = State(initialValue: max(2, min(max(studentCount, 2), suggested)))
    }

    private var isSkill: Bool { strategy == Self.skillStrategy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $groupCount, in: 2...max(2, studentCount)) {
                        Text("\(groupCount) grupos")
                    }
                } header: {
                    Text("Tamaño")
                } footer: {
                    if studentCount > 0 {
                        Text("Unos \(Int(ceil(Double(studentCount) / Double(groupCount)))) alumnos por grupo.")
                    }
                }

                Section("Criterio") {
                    Picker("Reparto", selection: $strategy) {
                        Text("Por nivel técnico").tag(Self.skillStrategy)
                        Text("Heterogéneos por nota").tag("heterogeneous_grade")
                        Text("Homogéneos por nota").tag("homogeneous_grade")
                        Text("Azar equilibrado").tag("random_balanced")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if isSkill {
                    Section {
                        dimensionRow(.technique, title: "Técnica", selection: $techniqueIds)
                        dimensionRow(.behaviour, title: "Comportamiento", selection: $behaviourIds)
                        dimensionRow(.leadership, title: "Liderazgo", selection: $leadershipIds)
                    } header: {
                        Text("Qué notas usar")
                    } footer: {
                        Text(techniqueFooter)
                    }
                }

                Section {
                    if isSkill {
                        Toggle("Un líder en cada grupo", isOn: $oneLeaderPerGroup)
                            .disabled(leadershipIds.isEmpty)
                        Toggle("Repartir comportamiento bajo", isOn: $spreadLowBehaviour)
                            .disabled(behaviourIds.isEmpty)
                    }
                    Toggle("Mezclar chicos y chicas", isOn: $mixSex)
                    Toggle("Repartir alumnado lesionado", isOn: $spreadInjured)
                } header: {
                    Text("Reparto")
                } footer: {
                    if isSkill {
                        Text(distributionFooter)
                    }
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
            .formStyle(.grouped)
            .navigationTitle("Agrupar automáticamente")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear grupos", action: create)
                        .disabled(studentCount == 0)
                }
            }
            .onAppear(perform: loadSelection)
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    // MARK: Filas y textos

    private func dimensionRow(
        _ dimension: WorkGroupSkillDimension,
        title: String,
        selection: Binding<[String]>
    ) -> some View {
        NavigationLink {
            WorkGroupSkillColumnPicker(
                title: title,
                columns: bridge.workGroupSkillCandidateColumns(),
                isSuggested: { bridge.workGroupSkillSuggests($0, dimension: dimension) },
                selection: selection
            )
        } label: {
            LabeledContent(title) {
                switch selection.wrappedValue.count {
                case 0:
                    Text("Elegir").foregroundStyle(.orange)
                case 1:
                    Text("1 instrumento")
                default:
                    Text("\(selection.wrappedValue.count) instrumentos")
                }
            }
        }
    }

    private var techniqueFooter: String {
        guard !techniqueIds.isEmpty else {
            return "No hay instrumentos de técnica elegidos. Elige alguno o se usará la media de cada alumno."
        }
        let withScore = bridge.workGroupDimensionScores(columnIds: techniqueIds).count
        let rest = max(0, studentCount - withScore)
        if rest == 0 { return "Todo el alumnado tiene nota de técnica." }
        return "\(withScore) de \(studentCount) alumnos tienen nota de técnica. "
            + (rest == 1 ? "El otro usa su media." : "Los otros \(rest) usan su media.")
    }

    private var distributionFooter: String {
        var lines: [String] = []
        let strong = marks.values.filter { $0 == .strong }.count
        let support = marks.values.filter { $0 == .support }.count
        if strong + support > 0 {
            lines.append("Las marcas Fuerte y Necesita apoyo siempre cuentan: \(strong) \(strong == 1 ? "fuerte" : "fuertes") y \(support) de apoyo en este curso.")
        }
        if leadershipIds.isEmpty {
            lines.append("Para repartir líderes, elige un instrumento de liderazgo.")
        }
        if behaviourIds.isEmpty {
            lines.append("Para repartir el comportamiento bajo, elige un instrumento de comportamiento.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: Acciones

    private func loadSelection() {
        guard !didLoad else { return }
        didLoad = true
        guard let classId else { return }
        techniqueIds = bridge.workGroupSkillSelection(classId: classId, dimension: .technique)
        behaviourIds = bridge.workGroupSkillSelection(classId: classId, dimension: .behaviour)
        leadershipIds = bridge.workGroupSkillSelection(classId: classId, dimension: .leadership)
        // «Por nivel técnico» sale primero cuando hay notas de técnica.
        if !techniqueIds.isEmpty { strategy = Self.skillStrategy }
    }

    private func create() {
        var skill: WorkGroupSkillRequest?
        if isSkill {
            if let classId {
                WorkGroupSkillSelectionStore.save(techniqueIds, classId: classId, dimension: .technique)
                WorkGroupSkillSelectionStore.save(behaviourIds, classId: classId, dimension: .behaviour)
                WorkGroupSkillSelectionStore.save(leadershipIds, classId: classId, dimension: .leadership)
            }
            let strongIds = marks.filter { $0.value == .strong }.keys.sorted().map { KotlinLong(value: $0) }
            let supportIds = marks.filter { $0.value == .support }.keys.sorted().map { KotlinLong(value: $0) }
            skill = WorkGroupSkillRequest(
                techniqueColumnIds: techniqueIds,
                behaviourColumnIds: behaviourIds,
                leadershipColumnIds: leadershipIds,
                strongStudentIds: strongIds,
                supportStudentIds: supportIds,
                oneLeaderPerGroup: oneLeaderPerGroup && !leadershipIds.isEmpty,
                spreadLowBehaviour: spreadLowBehaviour && !behaviourIds.isEmpty
            )
        }
        onCompose(
            NotebookAutoComposeChoice(
                groupCount: Int32(groupCount),
                strategy: strategy,
                mixSex: mixSex,
                spreadInjured: spreadInjured,
                situationId: selectedSituationId,
                skill: skill
            )
        )
        dismiss()
    }
}

/// Lista de columnas con nota para un apartado (Técnica, Comportamiento o Liderazgo).
private struct WorkGroupSkillColumnPicker: View {
    let title: String
    let columns: [NotebookColumnDefinition]
    let isSuggested: (String) -> Bool
    @Binding var selection: [String]

    var body: some View {
        Group {
            if columns.isEmpty {
                ContentUnavailableView(
                    "Sin instrumentos con nota",
                    systemImage: "tablecells",
                    description: Text("Añade una rúbrica o una columna numérica al Cuaderno.")
                )
            } else {
                Form {
                    Section {
                        ForEach(columns, id: \.id) { column in
                            row(column)
                        }
                    } header: {
                        Text("Rúbricas e instrumentos con nota")
                    } footer: {
                        Text("Sugeridas por su nombre o su tipo. Se recuerda tu elección en este equipo.")
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(title)
    }

    private func row(_ column: NotebookColumnDefinition) -> some View {
        let isSelected = selection.contains(column.id)
        return Button {
            if isSelected {
                selection.removeAll { $0 == column.id }
            } else {
                selection.append(column.id)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(column.title)
                        .foregroundStyle(.primary)
                    Text(subtitle(column))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func subtitle(_ column: NotebookColumnDefinition) -> String {
        let kind: String
        switch column.type {
        case .rubric: kind = "Rúbrica"
        case .ordinal: kind = "Escala"
        default: kind = "Numérica"
        }
        return isSuggested(column.id) ? "\(kind) · Sugerida" : kind
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
