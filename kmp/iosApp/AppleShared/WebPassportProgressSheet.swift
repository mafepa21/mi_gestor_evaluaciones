import SwiftUI

/// Progreso de un pasaporte por paradas: una fila por alumno y una marca por
/// parada. Pulsar una fila abre su ficha, de solo lectura.
///
/// Maqueta aprobada: `docs/maquetas/pasaporte_por_paradas_2026-10-25.html`
/// (estados L, M, N, O y P). Cada estado de parada se distingue por la forma del
/// símbolo y por su etiqueta de accesibilidad, no solo por el color.
struct WebPassportProgressSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: WebSubmissionTaskInfo
    let load: () async -> WebPassportProgress?
    /// Recoge del buzón. Devuelve un mensaje de error si no se pudo.
    let collect: () async -> String?
    let copyLinks: () -> Void
    let markSeen: (_ studentId: Int64) -> Void

    @State private var progress: WebPassportProgress?
    @State private var loading = true
    @State private var collecting = false
    @State private var collectError: String?
    @State private var selectedStudent: WebPassportStudentRow?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            await refresh(collectFirst: true)
        }
        .sheet(item: $selectedStudent) { fila in
            WebPassportStudentSheet(row: fila, stops: progress?.stops ?? [])
                .onAppear { markSeen(fila.studentId) }
                .onDisappear { Task { await refresh(collectFirst: false) } }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.title2.weight(.bold))
                Text("\(task.groupName) · Pasaporte")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if collecting {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Recogiendo del buzón")
            }
            Button("Copiar enlaces", action: copyLinks)
                .buttonStyle(.bordered)
            Button {
                Task { await refresh(collectFirst: true) }
            } label: {
                Label("Recoger ahora", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(collecting)
            Button("Cerrar") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if loading && progress == nil {
            VStack(spacing: 12) {
                ProgressView()
                Text("Recogiendo del buzón…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let progress {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let collectError {
                        Label("No se pudo abrir el buzón. Lo que ya tenías sigue aquí. (\(collectError))", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if progress.startedCount == 0 {
                        emptyState
                    } else {
                        summary(progress)
                        table(progress)
                        legend
                    }
                }
                .padding(24)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No se pudo abrir este pasaporte")
                    .font(.headline)
                Text("Puede que se publicara desde otro Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Nadie ha enviado nada todavía")
                .font(.headline)
            Text("Los envíos aparecen aquí solos cada vez que abres esta pantalla.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Copiar enlaces", action: copyLinks)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func summary(_ progress: WebPassportProgress) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(Array(progress.stops.enumerated()), id: \.element.id) { indice, parada in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(progress.sentCount(stopIndex: indice))")
                        .font(.title2.weight(.bold))
                    + Text("/\(progress.rows.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("P\(indice + 1) · \(parada.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func table(_ progress: WebPassportProgress) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Alumno/a")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(progress.stops.enumerated()), id: \.element.id) { indice, parada in
                    Text("P\(indice + 1)")
                        .frame(width: 44)
                        .help(parada.title)
                }
                Text("Último envío")
                    .frame(width: 96, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            Divider()

            ForEach(progress.rows) { fila in
                Button {
                    selectedStudent = fila
                } label: {
                    HStack(spacing: 8) {
                        Text(fila.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        ForEach(Array(fila.statuses.enumerated()), id: \.offset) { indice, estado in
                            WebPassportStopMark(status: estado)
                                .frame(width: 44)
                                .accessibilityLabel("Parada \(indice + 1): \(Self.statusText(estado))")
                        }
                        Text(fila.lastSubmittedAt.map(Self.shortDate) ?? "Sin envíos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(fila.lastSubmittedAt == nil)
                Divider()
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Label { Text("Enviada") } icon: { WebPassportStopMark(status: .sent(at: "")) }
            Label { Text("Nueva: cambiada desde que la miraste") } icon: { WebPassportStopMark(status: .updated(at: "")) }
            Label { Text("Sin enviar") } icon: { WebPassportStopMark(status: .empty) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func refresh(collectFirst: Bool) async {
        if collectFirst {
            collecting = true
            collectError = await collect()
            collecting = false
        }
        progress = await load()
        loading = false
    }

    static func statusText(_ estado: WebPassportStopStatus) -> String {
        switch estado {
        case .empty: return "sin enviar"
        case .sent(let at): return "enviada el \(shortDate(at))"
        case .updated(let at): return "nueva, cambiada el \(shortDate(at))"
        }
    }

    static func shortDate(_ iso: String) -> String {
        let conFraccion = ISO8601DateFormatter()
        conFraccion.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let fecha = conFraccion.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return fecha.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Marca de una parada: ✓ relleno (enviada), punto con aro (nueva), círculo vacío.
struct WebPassportStopMark: View {
    let status: WebPassportStopStatus

    var body: some View {
        switch status {
        case .empty:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updated:
            Image(systemName: "smallcircle.filled.circle")
                .foregroundStyle(.green)
        }
    }
}

/// Ficha de un alumno: sus respuestas por parada, de solo lectura.
struct WebPassportStudentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let row: WebPassportStudentRow
    let stops: [WebPassportStopInfo]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(row.name)
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { indice, parada in
                        stopSection(indice: indice, parada: parada)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder
    private func stopSection(indice: Int, parada: WebPassportStopInfo) -> some View {
        let estado = row.statuses.indices.contains(indice) ? row.statuses[indice] : .empty
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Parada \(indice + 1) · \(parada.title)")
                    .font(.headline)
                switch estado {
                case .empty:
                    EmptyView()
                case .sent(let at):
                    Text(WebPassportProgressSheet.shortDate(at))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .updated(let at):
                    Text(WebPassportProgressSheet.shortDate(at))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Nueva")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.14), in: Capsule())
                }
            }
            let lineas = row.answersBySection[parada.sectionId] ?? []
            if lineas.isEmpty {
                Text("Aún no ha enviado esta parada.")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(lineas) { linea in
                        GridRow {
                            Text(linea.title)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 160, alignment: .leading)
                            Text(linea.value)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout)
            }
        }
    }
}
