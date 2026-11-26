import SwiftUI

/// Bloque «Lesión» de la ficha del alumno (maqueta, estados 5, 6, 7 y 11):
/// lo importante en una línea (hasta cuándo y qué hace), «Ha vuelto», «Editar»
/// y el historial plegado. Abre `StudentInjurySheet` para crear o editar.
struct StudentInjuryCard: View {
    let bridge: KmpBridge
    let studentId: Int64
    let studentName: String

    @ObservedObject private var injuryStore = StudentInjuryStore.shared
    @State private var injuries: [StudentInjurySnapshot] = []
    @State private var phase: Phase = .loading
    @State private var editing: SheetTarget?
    @State private var confirmReturn = false
    @State private var actionFailed = false

    private enum Phase { case loading, loaded, failed }

    private struct SheetTarget: Identifiable {
        let id = UUID()
        let injury: StudentInjurySnapshot?
    }

    private var active: StudentInjurySnapshot? { injuryStore.activeByStudent[studentId] }

    private var history: [StudentInjurySnapshot] {
        injuries.filter { $0.id != active?.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .loading:
                placeholder
            case .failed:
                failedRow
            case .loaded:
                if let active {
                    activeCard(active)
                } else {
                    emptyRow
                }
                if actionFailed {
                    Text("No se pudo guardar. Nada ha cambiado.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !history.isEmpty {
                    historyGroup
                }
            }
        }
        .task(id: TaskKey(studentId: studentId, active: active)) { await load() }
        .sheet(item: $editing) { target in
            StudentInjurySheet(
                bridge: bridge,
                studentId: studentId,
                studentName: studentName,
                existing: target.injury,
                onFinished: { Task { await load() } }
            )
        }
    }

    private struct TaskKey: Equatable {
        let studentId: Int64
        let active: StudentInjurySnapshot?
    }

    // MARK: - Estados

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lesionado hasta el 12 dic · Árbitro").font(.headline)
            Text("Desde el 26 nov · Justificante entregado").font(.subheadline)
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando lesión")
    }

    private var failedRow: some View {
        HStack(spacing: 16) {
            Text("No se pudo cargar la lesión.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Reintentar") { Task { await load() } }
                .buttonStyle(.bordered)
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lesión").font(.subheadline.weight(.semibold))
                Text("Sin lesión").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Añadir lesión") { editing = SheetTarget(injury: nil) }
                .buttonStyle(.bordered)
        }
        .frame(minHeight: 44)
    }

    private func activeCard(_ injury: StudentInjurySnapshot) -> some View {
        let isLastDay = injury.endsOn.map { Calendar.current.isDateInToday($0) } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Label(isLastDay ? "Último día" : "Lesionado", systemImage: "cross.case.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(headline(injury, isLastDay: isLastDay))
                .font(.headline)
            Text(detail(injury))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !injury.note.isEmpty {
                Text("«\(injury.note)»")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Ha vuelto") { confirmReturn = true }
                    .buttonStyle(.borderedProminent)
                    .confirmationDialog(
                        "¿\(studentName) ha vuelto hoy?",
                        isPresented: $confirmReturn,
                        titleVisibility: .visible
                    ) {
                        Button("Ha vuelto") { markReturned(injury) }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("La lesión termina ayer y desde hoy cuenta sin lesión. Queda en su historial.")
                    }
                Button("Editar") { editing = SheetTarget(injury: injury) }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyGroup: some View {
        DisclosureGroup("Historial de lesiones (\(history.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(history) { injury in
                    Button { editing = SheetTarget(injury: injury) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(range(injury)).font(.subheadline)
                            Text(historyDetail(injury)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Abre la lesión para editarla")
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Textos

    private func headline(_ injury: StudentInjurySnapshot, isLastDay: Bool) -> String {
        var text: String
        if isLastDay {
            text = "Hoy es su último día"
        } else if let endsOn = injury.endsOn {
            text = "Hasta el \(StudentInjuryText.shortDate(endsOn))"
        } else {
            text = "Sin fecha de fin"
        }
        if injury.role != .none { text += " · \(injury.role.title)" }
        return text
    }

    private func detail(_ injury: StudentInjurySnapshot) -> String {
        "Desde el \(StudentInjuryText.shortDate(injury.startsOn)) · "
            + (injury.proofDelivered ? "Justificante entregado" : "Sin justificante")
    }

    private func range(_ injury: StudentInjurySnapshot) -> String {
        let start = StudentInjuryText.shortDate(injury.startsOn)
        guard let endsOn = injury.endsOn else { return "Desde el \(start)" }
        return "\(start) – \(StudentInjuryText.shortDate(endsOn))"
    }

    private func historyDetail(_ injury: StudentInjurySnapshot) -> String {
        let role = injury.role == .none ? "Sin papel" : injury.role.title
        return role + " · " + (injury.proofDelivered ? "justificante entregado" : "sin justificante")
    }

    // MARK: - Acciones

    private func load() async {
        // Si la app lleva abierta desde ayer, la marca de hoy se recalcula antes.
        await bridge.refreshInjuriesIfDayChanged()
        do {
            injuries = try await bridge.injuries(forStudentId: studentId)
            phase = .loaded
        } catch {
            if phase == .loading { phase = .failed }
        }
    }

    private func markReturned(_ injury: StudentInjurySnapshot) {
        Task { @MainActor in
            do {
                try await bridge.markInjuryReturned(id: injury.id)
                actionFailed = false
                AppleInteractionFeedback.play(.success)
                await load()
            } catch {
                actionFailed = true
                AppleInteractionFeedback.play(.error)
            }
        }
    }
}
