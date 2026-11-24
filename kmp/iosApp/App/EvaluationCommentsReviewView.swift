import SwiftUI
import MiGestorKit

/// «Leer y editar comentarios»: todos los comentarios de evaluación del grupo, enteros,
/// sin cortar, y editables en el sitio. Cada cambio se guarda solo al dejar de escribir.
struct EvaluationCommentsReviewView: View {
    let bridge: KmpBridge
    let classId: Int64
    let tabId: String?
    let students: [(id: Int64, name: String)]
    let initialComments: [Int64: String]

    @State private var columnId: String?
    @State private var errorMessage: String?
    /// Último texto guardado por alumno: una fila que reaparece al desplazar no vuelve al antiguo.
    @State private var savedComments: [Int64: String]?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label {
                        Text(errorMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            Section {
                ForEach(students, id: \.id) { student in
                    EvaluationCommentEditorRow(
                        studentName: student.name,
                        initialText: (savedComments ?? initialComments)[student.id] ?? "",
                        onSave: { text in await save(studentId: student.id, text: text) }
                    )
                }
            } footer: {
                Text("Se guarda solo al dejar de escribir. Es el texto que se exporta a Educamos.")
            }
        }
        .navigationTitle("Leer y editar comentarios")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @MainActor
    private func save(studentId: Int64, text: String) async -> Bool {
        do {
            let id: String
            if let columnId {
                id = columnId
            } else {
                id = try await bridge.ensureEvaluationCommentColumn(classId: classId, tabId: tabId).id
                columnId = id
            }
            _ = try await bridge.saveEvaluationComments(classId: classId, columnId: id, comments: [(studentId, text)])
            var updated = savedComments ?? initialComments
            updated[studentId] = text
            savedComments = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
            AccessibilityNotification.Announcement(errorMessage ?? "").post()
            return false
        }
    }
}

/// Un alumno con su comentario entero. Crece con el texto: nunca se corta.
private struct EvaluationCommentEditorRow: View {
    let studentName: String
    let initialText: String
    let onSave: (String) async -> Bool

    private enum SaveState { case idle, pending, saved, failed }

    @State private var text = ""
    @State private var savedText = ""
    @State private var state: SaveState = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var loaded = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(studentName).font(.headline)
                    Spacer(minLength: 8)
                    stateLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName).font(.headline)
                    stateLabel
                }
            }
            TextField("Sin comentario", text: $text, axis: .vertical)
                .lineLimit(3...)
                .focused($isFocused)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Comentario de \(studentName)")
                .appOnChange(of: text) { newValue in scheduleSave(newValue) }
                .appOnChange(of: isFocused) { focused in
                    if !focused { saveNow() }
                }
            Text("\(text.count) caracteres")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = initialText
            savedText = initialText
        }
        .onDisappear { saveNow() }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch state {
        case .idle: EmptyView()
        case .pending:
            Text("Guardando…").font(.footnote).foregroundStyle(.secondary)
        case .saved:
            Label("Guardado", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 8) {
                Label {
                    Text("Sin guardar").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button("Reintentar") { saveNow(force: true) }
                    .buttonStyle(.borderless)
            }
            .font(.footnote)
        }
    }

    private func scheduleSave(_ value: String) {
        guard value != savedText else { return }
        state = .pending
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await commit(value)
        }
    }

    private func saveNow(force: Bool = false) {
        guard force || text != savedText else { return }
        saveTask?.cancel()
        let value = text
        Task { await commit(value) }
    }

    @MainActor
    private func commit(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await onSave(trimmed)
        // Si el texto cambió mientras se guardaba, manda el guardado siguiente.
        guard value == text else { return }
        if ok {
            savedText = value
            state = .saved
            AccessibilityNotification.Announcement("Comentario de \(studentName) guardado").post()
        } else {
            state = .failed
        }
    }
}
