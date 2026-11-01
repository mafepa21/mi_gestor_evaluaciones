import SwiftUI
import MiGestorKit

/// Pantalla «Juntas»: preparar la junta de evaluación de un grupo y salir con el
/// acta hecha. Lista de juntas del grupo (la abierta arriba) y, al entrar en una,
/// el tablero (`JuntaBoardScreen`). La lógica vive en KMP; el estado, en
/// `EvaluationSessionStore`.
struct EvaluationSessionView: View {
    let bridge: KmpBridge
    @Binding var selectedClassId: Int64?

    @StateObject private var store: EvaluationSessionStore
    @State private var showingNew = false

    init(bridge: KmpBridge, selectedClassId: Binding<Int64?>) {
        self.bridge = bridge
        self._selectedClassId = selectedClassId
        self._store = StateObject(wrappedValue: EvaluationSessionStore(bridge: bridge))
    }

    private var groupName: String {
        bridge.classes.first { $0.id == selectedClassId }?.name ?? "Grupo"
    }

    var body: some View {
        NavigationStack {
            content
        }
        .overlay(alignment: .bottom) {
            if let message = store.errorMessage {
                JuntaErrorBanner(message: message) { store.errorMessage = nil }
            }
        }
        .animation(.snappy, value: store.errorMessage)
        .task(id: selectedClassId) {
            await store.loadList(classId: selectedClassId)
        }
        .onDisappear {
            Task { await store.flushNow() }
        }
        .sheet(isPresented: $showingNew) {
            JuntaNewSessionSheet(
                groupName: groupName,
                existingKinds: Set(store.sessions.map(\.kind))
            ) { kind, date, attendees in
                await store.create(kind: kind, date: date, attendees: attendees)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if selectedClassId == nil {
            ContentUnavailableView(
                "Elige un grupo",
                systemImage: "list.clipboard",
                description: Text("Selecciona un grupo para preparar su junta de evaluación.")
            )
        } else if store.boardPhase != .idle || store.board != nil {
            JuntaBoardScreen(store: store, groupName: groupName)
        } else {
            listScreen
        }
    }

    // MARK: Lista de juntas

    private var orderedSessions: [JuntaSessionUI] {
        store.sessions.sorted {
            if $0.isClosed != $1.isClosed { return !$0.isClosed }
            return $0.dateIso > $1.dateIso
        }
    }

    @ViewBuilder
    private var listScreen: some View {
        Group {
            switch store.listPhase {
            case .idle, .loading:
                JuntaDelayedProgress {
                    List {
                        ForEach(0..<3, id: \.self) { _ in
                            JuntaSessionRow(title: "1ª evaluación", detail: "15 dic · abierta")
                        }
                    }
                    .redacted(reason: .placeholder)
                    .disabled(true)
                }
            case .failed:
                JuntaLoadError(message: "No se pudieron cargar las juntas.") {
                    Task { await store.loadList(classId: selectedClassId) }
                }
            case .ready where store.sessions.isEmpty:
                ContentUnavailableView {
                    Label("Aún no hay juntas", systemImage: "list.clipboard")
                } description: {
                    Text("Crea la junta de este grupo. Tus medias, faltas e inclusión ya estarán dentro.")
                } actions: {
                    Button("Nueva junta") { showingNew = true }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                }
            case .ready:
                List {
                    Section {
                        ForEach(orderedSessions) { session in
                            Button {
                                Task { await store.open(sessionId: session.id) }
                            } label: {
                                JuntaSessionRow(
                                    title: session.label,
                                    detail: "\(JuntaFormat.dayMonth(session.dateIso)) · \(session.isClosed ? "cerrada" : "abierta")",
                                    isClosed: session.isClosed
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(groupName)
                    }
                }
            }
        }
        .navigationTitle("Juntas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNew = true
                } label: {
                    Label("Nueva junta", systemImage: "plus")
                }
                .disabled(selectedClassId == nil)
            }
        }
    }
}

// MARK: - Piezas

struct JuntaSessionRow: View {
    let title: String
    let detail: String
    var isClosed = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isClosed {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Muestra su contenido solo si la carga tarda más de medio segundo, para no
/// parpadear con cargas rápidas.
struct JuntaDelayedProgress<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var visible = false

    var body: some View {
        Group {
            if visible {
                content().overlay { ProgressView("Preparando la junta…").controlSize(.large) }
            } else {
                Color.clear
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            visible = true
        }
    }
}

struct JuntaLoadError: View {
    let title: String
    let message: String
    let retry: () -> Void

    init(title: String = "No se pudo abrir la junta", message: String = "Lo que ya apuntaste está guardado. Prueba otra vez.", retry: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Reintentar", action: retry)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
    }
}

struct JuntaErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Entendido", action: dismiss)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hoja «Nueva junta»

struct JuntaNewSessionSheet: View {
    let groupName: String
    let existingKinds: Set<EvaluationKindUI>
    /// Devuelve el mensaje de error, o `nil` si se creó bien.
    let create: (EvaluationKindUI, Date, String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var kind: EvaluationKindUI
    @State private var date = Date()
    @State private var attendees = ""
    @State private var errorText: String?
    @State private var isCreating = false

    init(
        groupName: String,
        existingKinds: Set<EvaluationKindUI>,
        create: @escaping (EvaluationKindUI, Date, String) async -> String?
    ) {
        self.groupName = groupName
        self.existingKinds = existingKinds
        self.create = create
        let firstFree = EvaluationKindUI.allCases.first { !existingKinds.contains($0) && $0 != .initial }
            ?? EvaluationKindUI.allCases.first { !existingKinds.contains($0) }
            ?? .first
        self._kind = State(initialValue: firstFree)
    }

    private var isDuplicate: Bool { existingKinds.contains(kind) }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Grupo", value: groupName)
                Picker("Evaluación", selection: $kind) {
                    ForEach(EvaluationKindUI.allCases) { Text($0.title).tag($0) }
                }
                if isDuplicate || errorText != nil {
                    Label(
                        errorText ?? "Este grupo ya tiene una junta de «\(kind.title)».",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                }
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Asistentes", text: $attendees, axis: .vertical)
                    .lineLimit(1...3)
            }
            .formStyle(.grouped)
            .navigationTitle("Nueva junta")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        isCreating = true
                        Task {
                            errorText = await create(kind, date, attendees)
                            isCreating = false
                            if errorText == nil { dismiss() }
                        }
                    }
                    .disabled(isDuplicate || isCreating)
                }
            }
            .onChange(of: kind) { _, _ in errorText = nil }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}
