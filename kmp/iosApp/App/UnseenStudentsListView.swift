import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Lista «Sin mirar» de un grupo (maqueta `docs/maquetas/alumnos-invisibles/`, estados
/// 2-7 y 10). Una acción visible por fila («Observación…»); «Abrir ficha» y «Visto»
/// van al deslizar y en el menú contextual. Se usa en el inspector de «Hoy».
struct UnseenStudentsListView: View {
    let bridge: KmpBridge
    let classId: Int64
    let className: String
    var onOpenStudent: (Int64) -> Void = { _ in }

    @ObservedObject private var store = UnseenStudentsStore.shared
    @State private var phase: Phase = .loading
    @State private var unseen: [UnseenStudentRow] = []
    @State private var seen: [SeenStudentRow] = []
    @State private var total = 0
    @State private var observing: UnseenStudentRow?
    @State private var isScreenShared = false

    private enum Phase { case loading, loaded, failed }

    var body: some View {
        content
            .task(id: TaskKey(classId: classId, version: store.version)) { await load() }
            .onAppear { isScreenShared = UnseenScreenShare.isActive }
            .sheet(item: $observing) { row in
                QuickObservationSheet(bridge: bridge, row: row, className: className)
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                isScreenShared = UnseenScreenShare.isActive
            }
            #endif
    }

    private struct TaskKey: Equatable {
        let classId: Int64
        let version: Int
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            List {
                ForEach(0..<3, id: \.self) { _ in
                    Text("Nombre del alumno · 17 días sin registro").redacted(reason: .placeholder)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calculando")
        case .failed:
            UnseenEmptyState(
                title: "No se pudo calcular",
                message: "No se han leído los registros del grupo. Tus datos no han cambiado.",
                systemImage: "exclamationmark.triangle",
                actionTitle: "Reintentar",
                action: { Task { await load() } }
            )
        case .loaded:
            if unseen.isEmpty && seen.isEmpty {
                UnseenEmptyState(
                    title: "Todos mirados",
                    message: "Todo el grupo tiene algún registro tuyo en las últimas 2 semanas.",
                    systemImage: "checkmark.circle",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            Section {
                if unseen.isEmpty {
                    Text("Nadie más sin mirar.").foregroundStyle(.secondary)
                }
                ForEach(unseen) { row in
                    UnseenStudentRowView(row: row, showsSupportMarker: !isScreenShared) {
                        observing = row
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Visto") { markSeen(row) }.tint(.gray)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Ficha") { onOpenStudent(row.studentId) }.tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Observación…", systemImage: "square.and.pencil") { observing = row }
                        Button("Abrir ficha", systemImage: "person.crop.circle") { onOpenStudent(row.studentId) }
                        Button("Visto (7 días)", systemImage: "eye") { markSeen(row) }
                    }
                    .accessibilityAction(named: "Observación") { observing = row }
                    .accessibilityAction(named: "Abrir ficha") { onOpenStudent(row.studentId) }
                    .accessibilityAction(named: "Visto 7 días") { markSeen(row) }
                }
            } header: {
                Text("\(className) · \(unseen.count) de \(total)")
            } footer: {
                Text("Sin nota, observación ni comentario en 2 semanas (no cuentan vacaciones ni festivos del calendario). Pasar lista sin escribir nada no cuenta.")
            }

            if !seen.isEmpty {
                Section {
                    ForEach(seen) { row in
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                Text("Vuelve a la lista el \(UnseenText.shortDate(row.until))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Mostrar de nuevo") {
                                bridge.unmarkStudentSeen(classId: classId, studentId: row.studentId)
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text("Vistos hace poco · solo en este aparato")
                }
            }
        }
    }

    private func load() async {
        do {
            let result = try await bridge.unseenStudents(classId: classId)
            unseen = result.unseen
            seen = result.seen
            total = result.total
            phase = .loaded
        } catch {
            if phase == .loading { phase = .failed }
        }
    }

    private func markSeen(_ row: UnseenStudentRow) {
        bridge.markStudentSeen(classId: classId, studentId: row.studentId)
        if #available(iOS 17.0, macOS 14.0, *) {
            AccessibilityNotification.Announcement("\(row.name) oculto 7 días").post()
        }
    }
}

/// Fila: nombre, último registro y días, con «Observación…» como única acción visible.
private struct UnseenStudentRowView: View {
    let row: UnseenStudentRow
    let showsSupportMarker: Bool
    let onObserve: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    private var initials: String {
        row.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Button(action: onObserve) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                HStack(spacing: 12) {
                    Text(initials)
                        .font(.footnote.weight(.semibold))
                        .frame(width: avatarSize, height: avatarSize)
                        .background(Color.secondary.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.name).foregroundStyle(.primary)
                            if showsSupportMarker && row.hasSupportMeasure {
                                Image(systemName: "diamond.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help("Tiene medida de apoyo (el detalle, en su ficha)")
                            }
                        }
                        Text(row.lastDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Label(row.daysText, systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                Text("Observación…")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Abre una observación rápida")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [row.name]
        if showsSupportMarker && row.hasSupportMeasure { parts.append("con medida de apoyo") }
        parts.append(row.daysText)
        parts.append(row.lastDescription)
        return parts.joined(separator: ", ")
    }
}

/// Observación rápida sin salir de la lista (maqueta, estado 3).
struct QuickObservationSheet: View {
    let bridge: KmpBridge
    let row: UnseenStudentRow
    let className: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @State private var failed = false
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if failed {
                    Section {
                        Label("No se pudo guardar. Lo que has escrito sigue aquí.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    TextField("Qué has visto hoy", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } header: {
                    Text("\(row.name) · \(className)")
                } footer: {
                    Text("Se guarda con la fecha de hoy y la ves en su ficha.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Observación")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if trimmed.isEmpty { dismiss() } else { confirmDiscard = true }
                    }
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog("¿Descartar observación?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                        Button("Descartar", role: .destructive) { dismiss() }
                        Button("Seguir escribiendo", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmed.isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(!trimmed.isEmpty)
            .onAppear { focused = true }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, idealWidth: 480, minHeight: 300)
        #endif
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                try await bridge.saveQuickObservation(classId: row.classId, studentId: row.studentId, text: trimmed)
                AppleInteractionFeedback.play(.success)
                dismiss()
            } catch {
                failed = true
                AppleInteractionFeedback.play(.error)
            }
            isSaving = false
        }
    }
}

/// Línea discreta de la ficha: «Último registro: hace 2 días (observación)».
struct LastContactLine: View {
    let bridge: KmpBridge
    let classId: Int64
    let studentId: Int64

    @ObservedObject private var store = UnseenStudentsStore.shared
    @State private var text: String?
    @State private var isOverdue = false

    var body: some View {
        Group {
            if let text {
                if isOverdue {
                    Label(text, systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                } else {
                    Text(text).foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .task(id: "\(classId)|\(studentId)|\(store.version)") {
            // Al cambiar de alumno no se debe ver ni un instante la línea del anterior.
            text = nil
            isOverdue = false
            if let line = try? await bridge.lastContactLine(classId: classId, studentId: studentId) {
                text = line.text
                isOverdue = line.isOverdue
            }
        }
    }
}

/// Vacío y error con la misma forma que `ContentUnavailableView` (que pide iOS 17 / macOS 14).
private struct UnseenEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}

/// Pantalla compartida o proyectada: se esconde la marca de «tiene medida».
/// En Mac no se puede saber si se comparte la pantalla: se esconde con más de una
/// pantalla conectada (proyector o monitor externo).
enum UnseenScreenShare {
    @MainActor static var isActive: Bool {
        #if os(iOS)
        return UIScreen.main.isCaptured || UIScreen.screens.count > 1
        #else
        return NSScreen.screens.count > 1
        #endif
    }
}
