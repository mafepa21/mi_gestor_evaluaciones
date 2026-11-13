import SwiftUI

/// Estado y guardado de "Tu valoración": el texto cualitativo que el docente escribe
/// sobre un alumno en un grupo y un trimestre para que la IA local lo use como base
/// del Comentario LOMLOE (issue #407, parte B).
///
/// Vive fuera de la vista para que iPad y Mac compartan el mismo comportamiento:
/// se guarda sola poco después de dejar de escribir, y siempre contra el alumno,
/// grupo y trimestre que estaban cargados cuando se escribió.
@MainActor
final class TeacherTermNoteStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case pending
        case saved
        case failed(String)
    }

    private struct Target: Equatable {
        let studentId: Int64
        let classId: Int64
        let termLabel: String
    }

    @Published var text = "" {
        didSet {
            guard !isApplyingLoadedText, text != oldValue else { return }
            scheduleSave()
        }
    }
    @Published private(set) var status: Status = .idle

    /// Se llama tras cada guardado real, para que la pantalla refresque lo que depende del texto.
    var onSaved: (() -> Void)?

    private weak var bridge: KmpBridge?
    private var target: Target?
    private var savedText = ""
    private var saveTask: Task<Void, Never>?
    private var isApplyingLoadedText = false

    var hasTarget: Bool { target != nil }
    var isLoading: Bool { status == .loading }

    /// Carga la valoración de un alumno. Antes guarda lo que quedara pendiente del anterior.
    func load(bridge: KmpBridge, studentId: Int64, classId: Int64, termLabel: String) async {
        let newTarget = Target(studentId: studentId, classId: classId, termLabel: termLabel)
        if target == newTarget, self.bridge === bridge { return }
        await flush()
        self.bridge = bridge
        target = nil
        status = .loading
        do {
            let loaded = try await bridge.teacherTermNote(studentId: studentId, classId: classId, termLabel: termLabel)
            apply(loaded)
            target = newTarget
            status = .idle
        } catch {
            apply("")
            status = .failed("No se pudo cargar tu valoración.")
        }
    }

    /// Deja la casilla sin alumno (p. ej. al quitar la selección). Guarda antes lo pendiente.
    func clear() async {
        await flush()
        target = nil
        apply("")
        status = .idle
    }

    /// Guarda ya lo pendiente. Llamar antes de generar, para que la IA lea lo último escrito.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard let bridge, let target, text != savedText else { return }
        let pending = text
        do {
            try await bridge.saveTeacherTermNote(
                studentId: target.studentId,
                classId: target.classId,
                termLabel: target.termLabel,
                text: pending
            )
            savedText = pending
            // Si se siguió escribiendo durante el guardado, queda pendiente el resto.
            status = text == pending ? .saved : .pending
            onSaved?()
        } catch {
            status = .failed("No se pudo guardar tu valoración.")
        }
    }

    private func apply(_ loaded: String) {
        saveTask?.cancel()
        saveTask = nil
        isApplyingLoadedText = true
        savedText = loaded
        text = loaded
        isApplyingLoadedText = false
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard target != nil else { return }
        status = .pending
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }
}

/// Casilla "Tu valoración". Sin tarjeta propia: cada plataforma la coloca dentro de la suya.
struct TeacherTermNoteEditor: View {
    @ObservedObject var store: TeacherTermNoteStore
    var minHeight: CGFloat = 96
    /// `false` cuando la tarjeta que la contiene ya pone el título.
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if showsTitle {
                    Text("Tu valoración")
                        .font(.headline)
                }
                Spacer()
                statusLabel
            }
            Text("Escribe lo que has observado este trimestre. La IA lo usa como base del comentario y lo redacta con el tono elegido. Es privada: no se copia tal cual.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $store.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(store.isLoading || !store.hasTarget)
                .accessibilityLabel("Tu valoración del alumno para este trimestre")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.status {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .pending:
            Text("Guardando…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saved:
            Label("Guardada", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
