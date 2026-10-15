//
//  TournamentsWorkspaceView.swift
//  MiGestorKMP
//
//  Pantalla «Torneos» del menú lateral. Lista del curso agrupada por Situación de Aprendizaje a la
//  izquierda y el torneo elegido a pantalla completa a la derecha (iPad y Mac). En iPhone o ventana
//  estrecha, pila lista -> detalle. El modo directo se abre a pantalla completa.
//  Maqueta aprobada: docs/maquetas/torneos_menu_lateral_2026-10-15.html
//

import SwiftUI
import MiGestorKit

struct TournamentsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @ObservedObject private var navigation = SdaTournamentNavigationStore.shared
    @StateObject private var model = SdaTournamentsHubModel()
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    @State private var selectedId: String?
    @State private var isCompactDetailVisible = false
    @State private var containerWidth: CGFloat = 0
    @State private var isLiveMode = false
    @State private var isPickingSituation = false
    @State private var pendingTarget: SdaNewTournamentTarget?
    @State private var newTournament: SdaNewTournamentTarget?
    @State private var closeWarning: String?

    /// Por debajo de este ancho se usa la pila lista -> detalle.
    private static let compactLayoutThreshold: CGFloat = 700

    private var usesCompactLayout: Bool {
        containerWidth > 0 && containerWidth < Self.compactLayoutThreshold
    }

    private var listColumnWidth: CGFloat {
        min(340, max(280, containerWidth * 0.32))
    }

    private var className: String? {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id })?.name }
    }

    /// Torneo que se está mostrando. En pantalla ancha, si no se ha elegido ninguno, el primero de la lista.
    private var displayedId: String? {
        if let selectedId, model.record(id: selectedId) != nil { return selectedId }
        guard !usesCompactLayout else { return nil }
        return model.sections.first?.items.first?.id
    }

    private var displayedRecord: TournamentRecord? {
        model.record(id: displayedId)
    }

    /// En macOS el modo directo es una capa sobre este contenido: la lista se aparta para que la capa ocupe todo.
    private var hidesListForLiveMode: Bool {
        #if os(macOS)
        return isLiveMode
        #else
        return false
        #endif
    }

    // MARK: Cuerpo

    var body: some View {
        Group {
            if usesCompactLayout {
                compactLayout
            } else {
                regularLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appPageBackground(for: colorScheme))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard abs(containerWidth - newWidth) > 1 else { return }
            containerWidth = newWidth
        }
        .task(id: selectedClassId) {
            await model.load(bridge: bridge, classId: selectedClassId)
            applyPendingRequest()
        }
        .onChange(of: selectedClassId) {
            selectedId = nil
            isCompactDetailVisible = false
            closeWarning = nil
        }
        .onChange(of: navigation.pending) {
            applyPendingRequest()
        }
        .sheet(isPresented: $isPickingSituation, onDismiss: {
            if let target = pendingTarget {
                pendingTarget = nil
                newTournament = target
            }
        }) {
            if let classId = selectedClassId {
                SdaSituationPickerSheet(
                    classId: classId,
                    className: className ?? "este curso",
                    onPick: { pendingTarget = $0 },
                    onOpenSituations: { onOpenModule(.situations, classId, nil) }
                )
                .environmentObject(bridge)
            }
        }
        .sheet(item: $newTournament) { target in
            SdaNewTournamentSheet(
                learningSituationId: target.choice.id,
                teams: target.teams,
                suggestedName: suggestedName(for: target.choice.id),
                preferredClassId: selectedClassId
            ) { created in
                handleCreated(created)
            }
            .environmentObject(bridge)
        }
    }

    // MARK: Disposición adaptativa

    /// iPad y Mac: lista y detalle lado a lado. La vista ya vive dentro de la columna de detalle
    /// del `NavigationSplitView` del shell, así que no se anida otro split view.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            if !hidesListForLiveMode {
                listColumn(showsEmptyState: false)
                    .frame(width: listColumnWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                Divider()
            }
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// iPhone o ventana estrecha: pila. La fila abre el torneo y «Torneos» vuelve a la lista.
    @ViewBuilder
    private var compactLayout: some View {
        if isCompactDetailVisible, displayedRecord != nil {
            VStack(spacing: 0) {
                if !isLiveMode { compactDetailBar }
                detailColumn
            }
            .transition(.move(edge: .trailing))
        } else {
            listColumn(showsEmptyState: true)
                .transition(.move(edge: .leading))
        }
    }

    private var compactDetailBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { isCompactDetailVisible = false }
                } label: {
                    Label("Torneos", systemImage: "chevron.backward")
                        .frame(minHeight: tapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Volver a Torneos")
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .background(appCardBackground(for: colorScheme))
            Divider()
        }
    }

    // MARK: Lista

    private func listColumn(showsEmptyState: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
            listBody(showsEmptyState: showsEmptyState)
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Torneos")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: startNewTournament) {
                    Label("Nuevo", systemImage: "plus")
                        .frame(minHeight: tapSize)
                }
                .buttonStyle(.borderless)
                .disabled(selectedClassId == nil)
                .accessibilityLabel("Nuevo torneo")
            }
            courseMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var courseMenu: some View {
        Menu {
            ForEach(bridge.classes, id: \.id) { schoolClass in
                Button {
                    selectedClassId = schoolClass.id
                } label: {
                    if schoolClass.id == selectedClassId {
                        Label(schoolClass.name, systemImage: "checkmark")
                    } else {
                        Text(schoolClass.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(className ?? "Elige un curso")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(EvaluationDesign.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: tapSize - 8)
            .background(EvaluationDesign.accentSoft, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Curso")
        .accessibilityValue(className ?? "Sin elegir")
    }

    @ViewBuilder
    private func listBody(showsEmptyState: Bool) -> some View {
        if selectedClassId == nil {
            if showsEmptyState {
                WorkspaceEmptyState(
                    title: "Elige un curso",
                    subtitle: "Selecciona un curso para ver sus torneos.",
                    systemImage: "trophy"
                )
            } else {
                Spacer(minLength: 0)
            }
        } else {
            switch model.phase {
            case .loading:
                VStack(alignment: .leading, spacing: 16) {
                    LearningSituationSkeletonBlock(lines: 2)
                    LearningSituationSkeletonBlock(lines: 2)
                    LearningSituationSkeletonBlock(lines: 2)
                }
                .padding(16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cargando torneos")
            case .failed:
                LearningSituationInlineNotice(
                    kind: .error,
                    message: "No se pudieron cargar los torneos.",
                    actionTitle: "Reintentar"
                ) {
                    Task { await model.load(bridge: bridge, classId: selectedClassId) }
                }
                .padding(.horizontal, 16)
            case .ready:
                if model.records.isEmpty {
                    if showsEmptyState {
                        emptyState
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    sectionsList
                }
            }
        }
    }

    private var sectionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.sections) { section in
                    Text(section.title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.items) { item in
                        row(item)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 16)
        }
    }

    private func row(_ item: SdaTournamentListItem) -> some View {
        let isSelected = item.id == displayedId
        return Button {
            select(item.id)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let status = item.status {
                    SdaStatusBadge(status: status)
                }
                if usesCompactLayout {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: tapSize, alignment: .leading)
            .background(
                isSelected && !usesCompactLayout ? EvaluationDesign.accentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Abre el torneo.")
    }

    private var emptyState: some View {
        WorkspaceEmptyState(
            title: "Sin torneos en \(className ?? "este curso")",
            subtitle: "Crea uno a partir de los grupos de una situación.",
            systemImage: "trophy",
            actionTitle: "Crear torneo",
            action: startNewTournament
        )
    }

    // MARK: Detalle

    private var detailColumn: some View {
        VStack(spacing: 0) {
            if let closeWarning {
                LearningSituationInlineNotice(kind: .error, message: closeWarning)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            if let record = displayedRecord {
                SdaTournamentSheetHost(
                    record: record,
                    currentTeams: record.learningSituationId.flatMap { model.teamsBySituation[$0] } ?? [],
                    className: bridge.classes.first(where: { $0.id == record.classId })?.name ?? "Curso",
                    onSaved: { model.upsert($0) },
                    onDeleted: {
                        model.remove(id: record.id)
                        selectedId = nil
                        isCompactDetailVisible = false
                    },
                    presentation: .embedded,
                    onSaveFailedAtClose: { name in
                        closeWarning = "No se guardaron los últimos cambios de «\(name)». Ábrelo de nuevo y revisa los resultados."
                    },
                    onLiveModeChange: { isLiveMode = $0 }
                )
                .id(record.id)
                .environmentObject(bridge)
            } else if selectedClassId != nil, model.phase == .ready, model.records.isEmpty {
                emptyState
            } else if selectedClassId == nil {
                WorkspaceEmptyState(
                    title: "Elige un curso",
                    subtitle: "Selecciona un curso para ver sus torneos.",
                    systemImage: "trophy"
                )
            } else if model.phase == .loading {
                LearningSituationSkeletonBlock(lines: 4)
                    .padding(24)
                    .accessibilityHidden(true)
            } else {
                WorkspaceEmptyState(
                    title: "Elige un torneo",
                    subtitle: "Selecciona un torneo de la lista para ver su calendario y sus resultados.",
                    systemImage: "trophy"
                )
            }
        }
    }

    // MARK: Acciones

    private func select(_ id: String) {
        closeWarning = nil
        selectedId = id
        if usesCompactLayout {
            withAnimation(.snappy) { isCompactDetailVisible = true }
        }
    }

    private func startNewTournament() {
        guard selectedClassId != nil else { return }
        isPickingSituation = true
    }

    private func suggestedName(for situationId: Int64) -> String {
        let existing = model.records.filter { $0.learningSituationId == situationId }.count
        return "Torneo \(existing + 1)"
    }

    /// Al crear, el torneo nuevo queda seleccionado. Si es de otro curso (la hoja deja elegir), se
    /// cambia de curso y se selecciona cuando cargue.
    private func handleCreated(_ created: TournamentRecord) {
        if created.classId == selectedClassId {
            model.upsert(created)
            select(created.id)
        } else {
            navigation.request(tournamentId: created.id, classId: created.classId)
        }
    }

    /// Atiende «abre este torneo» pedido desde la Situación. Espera a tener cargado el curso del torneo.
    private func applyPendingRequest() {
        guard let request = navigation.pending else { return }
        if let classId = request.classId, classId != selectedClassId {
            selectedClassId = classId
            return
        }
        guard model.phase == .ready, model.loadedClassId == selectedClassId else { return }
        if model.record(id: request.tournamentId) != nil {
            select(request.tournamentId)
        }
        navigation.consume()
    }
}
