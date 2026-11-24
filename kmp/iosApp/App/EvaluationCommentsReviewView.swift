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
                        initialText: initialComments[student.id] ?? "",
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
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(studentName).font(.headline)
                Spacer(minLength: 8)
                stateLabel
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
            Label("Sin guardar", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
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

    private func saveNow() {
        guard text != savedText else { return }
        saveTask?.cancel()
        let value = text
        Task { await commit(value) }
    }

    @MainActor
    private func commit(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await onSave(trimmed)
        if ok {
            savedText = value
            state = .saved
        } else {
            state = .failed
        }
    }
}
