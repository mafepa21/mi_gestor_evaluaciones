import SwiftUI
import PDFKit

/// Junta abierta o cerrada: resumen, filtro, alumnado y panel del alumno.
///
/// Mac/iPad: `Table` con el panel del alumno a la derecha. iPhone y tamaños de
/// accesibilidad: tarjetas apiladas y el alumno se abre en una hoja con detents.
struct JuntaBoardScreen: View {
    @ObservedObject var store: EvaluationSessionStore
    let groupName: String

    @State private var filter: JuntaFilter = .all
    @State private var selection: Int64?
    @State private var sortOrder = [KeyPathComparator(\JuntaStudentRowUI.sortName)]
    @State private var showingClose = false
    @State private var showingReopen = false
    @State private var showingDelete = false
    @State private var showingActa = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isWide: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    private var useTable: Bool { isWide && !dynamicTypeSize.isAccessibilitySize }

    private var visibleRows: [JuntaStudentRowUI] {
        guard let board = store.board else { return [] }
        return board.students.filter(filter.matches).sorted(using: sortOrder)
    }

    private var selectedRow: JuntaStudentRowUI? {
        store.board?.students.first { $0.studentId == selection }
    }

    var body: some View {
        content
            .navigationTitle(store.board?.session.label ?? "Junta")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .onChange(of: filter) { _, _ in
                if let id = selection, !visibleRows.contains(where: { $0.studentId == id }) { selection = nil }
            }
            .alert("¿Cerrar la junta?", isPresented: $showingClose) {
                // El cancelar lleva el foco inicial: cerrar no se activa por accidente.
                Button("Seguir revisando", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
                Button("Cerrar junta") { Task { await store.closeSession() } }
            } message: {
                let pending = store.board?.summary.pendingReviewCount ?? 0
                let warning = pending > 0 ? "\n\(pending == 1 ? "Queda 1 alumno sin revisar." : "Quedan \(pending) alumnos sin revisar.")" : ""
                Text("Se guardan las medias y las faltas de hoy. El acta usará esos datos aunque luego cambies notas.\(warning)")
            }
            .alert("¿Reabrir la junta?", isPresented: $showingReopen) {
                Button("Cancelar", role: .cancel) {}
                Button("Reabrir junta") { Task { await store.reopenSession() } }
            } message: {
                Text("Podrás editarla otra vez. Al cerrarla de nuevo se congelan las medias y las faltas de ese día.")
            }
            .alert("¿Borrar la junta?", isPresented: $showingDelete) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar junta", role: .destructive) {
                    if let id = store.board?.session.id { Task { await store.delete(sessionId: id); await store.closeBoard() } }
                }
            } message: {
                Text("Se borran sus acuerdos y el seguimiento de cada alumno. No se puede deshacer.")
            }
            .sheet(isPresented: $showingActa) {
                if let board = store.board {
                    JuntaActaSheet(board: board, groupName: groupName)
                }
            }
            #if os(iOS)
            .sheet(isPresented: Binding(
                get: { !isWide && selectedRow != nil },
                set: { if !$0 { selection = nil } }
            )) {
                if let row = selectedRow, let board = store.board {
                    NavigationStack {
                        JuntaStudentPanel(
                            store: store, row: row, position: position(of: row), total: visibleRows.count,
                            isClosed: board.session.isClosed,
                            move: move, markAndNext: markAndNext
                        )
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Hecho") { selection = nil }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            #endif
    }

    // MARK: Estructura

    @ViewBuilder
    private var content: some View {
        switch store.boardPhase {
        case .failed:
            JuntaLoadError { Task { await store.retryBoard() } }
        case .idle, .loading:
            JuntaDelayedProgress {
                List {
                    ForEach(0..<5, id: \.self) { _ in
                        JuntaSessionRow(title: "Nombre Apellido", detail: "Mi media 6,5 · Faltas 3 %")
                    }
                }
                .redacted(reason: .placeholder)
                .disabled(true)
            }
        case .ready:
            if let board = store.board {
                boardContent(board)
            }
        }
    }

    private func boardContent(_ board: JuntaBoardUI) -> some View {
        let isClosed = board.session.isClosed
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(board)
                if isClosed { closedBanner(board.session) }
                Picker("Filtro", selection: $filter) {
                    ForEach(JuntaFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.bottom, 8)

                if board.students.isEmpty {
                    ContentUnavailableView(
                        "Este grupo no tiene alumnado",
                        systemImage: "person.3",
                        description: Text("Añade alumnos al grupo y vuelve a abrir la junta.")
                    )
                } else if visibleRows.isEmpty {
                    ContentUnavailableView("Nadie en «\(filter.rawValue)»", systemImage: "checkmark.circle")
                } else if useTable {
                    table(isClosed: isClosed)
                    Divider()
                    JuntaGeneralSection(store: store, session: board.session)
                        .frame(maxHeight: 190)
                } else {
                    cards(board, isClosed: isClosed)
                }
            }
            .frame(maxWidth: .infinity)

            if isWide, let row = selectedRow {
                Divider()
                JuntaStudentPanel(
                    store: store, row: row, position: position(of: row), total: visibleRows.count,
                    isClosed: isClosed, move: move, markAndNext: markAndNext
                )
                .frame(width: 340)
                .id(row.studentId)
            }
        }
    }

    private func header(_ board: JuntaBoardUI) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(JuntaFormat.headline(board.summary)).font(.title2.weight(.semibold))
            Text("\(JuntaFormat.ownSubjectLine(board.summary)) \(JuntaFormat.dayMonth(board.session.dateIso)) · \(groupName) · \(board.summary.studentCount) alumnos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(JuntaFormat.summarySpeech(board.summary))
        .accessibilityAddTraits(.isHeader)
    }

    private func closedBanner(_ session: JuntaSessionUI) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cerrada el \(JuntaFormat.closedOn(session.closedAtEpochMs))").font(.subheadline.weight(.semibold))
                Text("El acta usa las medias y faltas de ese día.").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Ver acta") { showingActa = true }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Tabla (Mac e iPad)

    private func table(isClosed: Bool) -> some View {
        Table(visibleRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Alumno", value: \.sortName) { row in
                JuntaNameCell(store: store, row: row, isClosed: isClosed)
            }
            TableColumn("Mi media", value: \.sortAverage) { row in
                Text(JuntaFormat.average(row.average)).monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            TableColumn("Faltas", value: \.sortAbsence) { row in
                Text(JuntaFormat.absence(row.absencePercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            TableColumn("Otras materias", value: \.otherFailedCount) { row in
                JuntaOtherStepper(store: store, row: row, isClosed: isClosed)
            }
            .width(min: 120, ideal: 140)
            TableColumn("Total", value: \.totalFailed) { row in
                JuntaTotalBadge(count: row.totalFailed)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Revisado") { row in
                JuntaReviewedToggle(store: store, row: row, isClosed: isClosed)
            }
            .width(min: 70, ideal: 80)
        }
    }

    // MARK: Tarjetas (iPhone y tamaños de accesibilidad)

    private func cards(_ board: JuntaBoardUI, isClosed: Bool) -> some View {
        List(selection: isWide ? $selection : nil) {
            Section {
                ForEach(visibleRows) { row in
                    JuntaCard(store: store, row: row, isClosed: isClosed) { selection = row.studentId }
                        .tag(row.studentId)
                }
            }
            Section {
                JuntaGeneralSection(store: store, session: board.session)
            }
        }
        .listStyle(.plain)
    }

    // MARK: Panel: navegación entre alumnos

    private func position(of row: JuntaStudentRowUI) -> Int {
        (visibleRows.firstIndex { $0.studentId == row.studentId } ?? 0) + 1
    }

    private func move(_ delta: Int) {
        guard let id = selection, let index = visibleRows.firstIndex(where: { $0.studentId == id }) else { return }
        let target = index + delta
        if visibleRows.indices.contains(target) { selection = visibleRows[target].studentId }
    }

    /// Marca revisado y pasa al siguiente de la lista visible (se calcula antes de marcar,
    /// porque con el filtro «Sin revisar» la fila actual desaparece al marcarla).
    private func markAndNext() {
        guard let id = selection else { return }
        let next = JuntaRules.nextStudentId(after: id, in: visibleRows)
        store.setReviewed(studentId: id, to: true)
        if let next { selection = next }
    }

    // MARK: Barra de herramientas

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                Task { await store.closeBoard() }
            } label: {
                Label("Juntas", systemImage: "chevron.backward")
            }
        }
        if let board = store.board {
            ToolbarItem(placement: .secondaryAction) {
                Button { showingActa = true } label: { Label("Acta", systemImage: "doc.text") }
            }
            ToolbarItem(placement: .primaryAction) {
                if board.session.isClosed {
                    Button { showingActa = true } label: { Label("Ver acta", systemImage: "doc.text") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Cerrar junta") { showingClose = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isWorking)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if board.session.isClosed {
                        Button { showingReopen = true } label: { Label("Reabrir junta", systemImage: "lock.open") }
                    }
                    Button(role: .destructive) { showingDelete = true } label: { Label("Borrar junta", systemImage: "trash") }
                } label: {
                    Label("Más", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

// MARK: - Celdas

private func juntaTotalColor(_ count: Int) -> Color {
    switch count {
    case 0: return .green
    case 1...2: return .orange
    default: return .red
    }
}

/// Total de suspensas: el color siempre va con el número.
struct JuntaTotalBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(juntaTotalColor(count))
            .accessibilityLabel(JuntaFormat.suspensas(count))
    }
}

/// Alumno + señales bajo el nombre (medida, incidencias, acuerdo). Lleva la etiqueta
/// completa y las acciones de VoiceOver de toda la fila.
struct JuntaNameCell: View {
    @ObservedObject var store: EvaluationSessionStore
    let row: JuntaStudentRowUI
    let isClosed: Bool

    private var signals: [String] {
        var items: [String] = []
        if let level = row.supportLevel { items.append(level.displayName) }
        if let incidents = row.incidentCount, incidents > 0 { items.append(incidents == 1 ? "1 incidencia" : "\(incidents) incidencias") }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.fullName).fontWeight(.medium)
            if !signals.isEmpty || !row.agreement.isEmpty {
                HStack(spacing: 6) {
                    Text(signals.joined(separator: " · "))
                    if !row.agreement.isEmpty {
                        Label("Acuerdo", systemImage: "square.and.pencil").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(JuntaFormat.rowSpeech(row))
        .accessibilityAction(named: "Añadir suspensa") {
            if !isClosed { store.setOtherFailed(studentId: row.studentId, to: row.otherFailedCount + 1) }
        }
        .accessibilityAction(named: "Quitar suspensa") {
            if !isClosed { store.setOtherFailed(studentId: row.studentId, to: row.otherFailedCount - 1) }
        }
        .accessibilityAction(named: row.isReviewed ? "Marcar sin revisar" : "Marcar revisado") {
            if !isClosed { store.setReviewed(studentId: row.studentId, to: !row.isReviewed) }
        }
    }
}

struct JuntaOtherStepper: View {
    @ObservedObject var store: EvaluationSessionStore
    let row: JuntaStudentRowUI
    let isClosed: Bool

    var body: some View {
        Stepper(
            value: Binding(
                get: { row.otherFailedCount },
                set: { store.setOtherFailed(studentId: row.studentId, to: $0) }
            ),
            in: 0...JuntaRules.maxOtherFailed
        ) {
            Text("\(row.otherFailedCount)").monospacedDigit()
        }
        .disabled(isClosed)
        .accessibilityLabel("Suspensas en otras materias de \(row.fullName)")
    }
}

struct JuntaReviewedToggle: View {
    @ObservedObject var store: EvaluationSessionStore
    let row: JuntaStudentRowUI
    let isClosed: Bool

    var body: some View {
        Button {
            store.setReviewed(studentId: row.studentId, to: !row.isReviewed)
        } label: {
            Image(systemName: row.isReviewed ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(row.isReviewed ? Color.accentColor : Color.secondary)
                .frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
        .disabled(isClosed)
        .accessibilityLabel("Revisado, \(row.fullName)")
        .accessibilityValue(row.isReviewed ? "Sí" : "No")
    }
}

/// Tarjeta de alumno (iPhone y tamaños de accesibilidad).
struct JuntaCard: View {
    @ObservedObject var store: EvaluationSessionStore
    let row: JuntaStudentRowUI
    let isClosed: Bool
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.fullName).font(.headline)
                        if let level = row.supportLevel {
                            Text(level.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if row.isReviewed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    JuntaTotalBadge(count: row.totalFailed)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(JuntaFormat.rowSpeech(row))
            .accessibilityHint("Abre el panel del alumno")
            .accessibilityAction(named: "Añadir suspensa") {
                if !isClosed { store.setOtherFailed(studentId: row.studentId, to: row.otherFailedCount + 1) }
            }
            .accessibilityAction(named: "Quitar suspensa") {
                if !isClosed { store.setOtherFailed(studentId: row.studentId, to: row.otherFailedCount - 1) }
            }
            .accessibilityAction(named: row.isReviewed ? "Marcar sin revisar" : "Marcar revisado") {
                if !isClosed { store.setReviewed(studentId: row.studentId, to: !row.isReviewed) }
            }

            let figures = Text("Mi media \(JuntaFormat.average(row.average)) · Faltas \(JuntaFormat.absence(row.absencePercent))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                figures
                stepper
            } else {
                HStack {
                    figures
                    Spacer(minLength: 8)
                    stepper
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var stepper: some View {
        Stepper(
            value: Binding(
                get: { row.otherFailedCount },
                set: { store.setOtherFailed(studentId: row.studentId, to: $0) }
            ),
            in: 0...JuntaRules.maxOtherFailed
        ) {
            Text("Otras: \(row.otherFailedCount)").font(.subheadline).monospacedDigit()
        }
        .disabled(isClosed)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        .accessibilityLabel("Suspensas en otras materias de \(row.fullName)")
    }
}

// MARK: - Datos de la junta y acuerdos generales

struct JuntaGeneralSection: View {
    @ObservedObject var store: EvaluationSessionStore
    let session: JuntaSessionUI

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acuerdos generales del grupo").font(.headline)
            if session.isClosed {
                Text(session.generalAgreements.isEmpty ? "Sin acuerdos generales." : session.generalAgreements)
                    .foregroundStyle(session.generalAgreements.isEmpty ? .secondary : .primary)
                if !session.attendees.isEmpty {
                    Text("Asistentes: \(session.attendees)").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                TextEditor(text: Binding(
                    get: { session.generalAgreements },
                    set: { value in store.editHeader { $0.generalAgreements = value } }
                ))
                .frame(minHeight: 64)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Acuerdos generales del grupo")
                HStack {
                    DatePicker("Fecha", selection: Binding(
                        get: { JuntaFormat.parseDate(session.dateIso) ?? Date() },
                        set: { value in store.editHeader { $0.dateIso = JuntaFormat.isoDate(value) } }
                    ), displayedComponents: .date)
                    .fixedSize()
                    TextField("Asistentes", text: Binding(
                        get: { session.attendees },
                        set: { value in store.editHeader { $0.attendees = value } }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Panel del alumno

struct JuntaStudentPanel: View {
    @ObservedObject var store: EvaluationSessionStore
    let row: JuntaStudentRowUI
    let position: Int
    let total: Int
    let isClosed: Bool
    let move: (Int) -> Void
    let markAndNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.fullName).font(.title3.weight(.semibold))
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button { move(-1) } label: { Label("Alumno anterior", systemImage: "chevron.up") }
                        .labelStyle(.iconOnly)
                        .disabled(position <= 1)
                    Button { move(1) } label: { Label("Alumno siguiente", systemImage: "chevron.down") }
                        .labelStyle(.iconOnly)
                        .disabled(position >= total)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], alignment: .leading, spacing: 12) {
                    metric(JuntaFormat.average(row.average), caption: row.ownFailed == true ? "Mi media · suspensa" : "Mi media")
                    metric(JuntaFormat.absence(row.absencePercent), caption: absenceCaption)
                    metric(row.incidentCount.map(String.init) ?? "–", caption: "Incidencias")
                    metric("\(row.totalFailed)", caption: "Suspensas en total", color: juntaTotalColor(row.totalFailed))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Otras materias").font(.headline)
                    Stepper(
                        value: Binding(
                            get: { row.otherFailedCount },
                            set: { store.setOtherFailed(studentId: row.studentId, to: $0) }
                        ),
                        in: 0...JuntaRules.maxOtherFailed
                    ) {
                        Text("Suspensas en otras materias: \(row.otherFailedCount)").monospacedDigit()
                    }
                    .disabled(isClosed)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Acuerdo").font(.headline)
                    if isClosed {
                        Text(row.agreement.isEmpty ? "Sin acuerdos." : row.agreement)
                            .foregroundStyle(row.agreement.isEmpty ? .secondary : .primary)
                    } else {
                        TextEditor(text: Binding(
                            get: { row.agreement },
                            set: { store.setAgreement(studentId: row.studentId, to: $0) }
                        ))
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Acuerdo de \(row.fullName)")
                        Text("Sale en el acta. Escribe solo lo acordado, sin datos médicos.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isClosed {
                    Toggle("Revisado", isOn: Binding(
                        get: { row.isReviewed },
                        set: { store.setReviewed(studentId: row.studentId, to: $0) }
                    ))
                    Button(action: markAndNext) {
                        Label("Marcar y siguiente", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(position >= total && row.isReviewed)
                }
            }
            .padding()
        }
        .navigationTitle(row.fullName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var subtitle: String {
        var text = "\(position) de \(total)"
        if let level = row.supportLevel { text += " · Medida de \(level.displayName.lowercased())" }
        return text
    }

    private var absenceCaption: String {
        guard let count = row.absenceCount else { return "Faltas" }
        return count == 1 ? "Faltas (1 falta)" : "Faltas (\(count) faltas)"
    }

    private func metric(_ value: String, caption: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Acta

struct JuntaActaSheet: View {
    let board: JuntaBoardUI
    let groupName: String

    @Environment(\.dismiss) private var dismiss
    @State private var pdfURL: URL?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    JuntaPDFPreview(url: pdfURL)
                } else if failed {
                    JuntaLoadError(title: "No se pudo preparar el acta", message: "Prueba otra vez.") { prepare() }
                } else {
                    ProgressView("Preparando el acta…")
                }
            }
            .navigationTitle("Acta")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if let pdfURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: pdfURL) { Label("Compartir", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .task { prepare() }
        // El PDF vive en la carpeta temporal: se borra al cerrar la hoja del acta.
        .onDisappear { removeTemporaryPDF() }
    }

    private func removeTemporaryPDF() {
        if let url = pdfURL { try? FileManager.default.removeItem(at: url) }
        pdfURL = nil
    }

    private func prepare() {
        removeTemporaryPDF()
        failed = false
        let content = JuntaActaContent(board: board, groupName: groupName)
        let name = "Acta \(groupName) \(board.session.label)"
        if let url = JuntaActaPDFRenderer.writeToTemporaryFile(content, suggestedName: name) {
            pdfURL = url
        } else {
            failed = true
        }
    }
}

#if os(macOS)
struct JuntaPDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#else
struct JuntaPDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#endif
