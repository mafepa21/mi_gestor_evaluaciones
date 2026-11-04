#if os(macOS)
import SwiftUI

/// Resultados de una coevaluación: quién ha enviado, cuántas evaluaciones recibe
/// cada alumno, su media por criterio y las parejas que no casan. Desde aquí se
/// manda a cada alumno su media por correo.
///
/// Gemela de `WebPassportProgressSheet`: al abrirse recoge del buzón y después
/// pinta lo que hay guardado en este Mac.
struct WebPeerResultsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: WebSubmissionTaskInfo
    let load: () async -> WebPeerResults?
    /// Recoge del buzón. Devuelve un mensaje de error si no se pudo.
    let collect: () async -> String?

    @State private var results: WebPeerResults?
    @State private var loading = true
    @State private var collecting = false
    @State private var collectError: String?
    @State private var showingMail = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { await refresh(collectFirst: true) }
        .sheet(isPresented: $showingMail) {
            if let results {
                WebPeerResultsMailSheet(results: results)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.title2.weight(.bold))
                Text("\(task.groupName) · Coevaluación")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if collecting {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Recogiendo del buzón")
            }
            Button {
                Task { await refresh(collectFirst: true) }
            } label: {
                Label("Comprobar respuestas nuevas", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(collecting)
            Button("Enviar resultados…") { showingMail = true }
                .buttonStyle(.borderedProminent)
                .disabled((results?.evaluationCount ?? 0) == 0)
            Button("Cerrar") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if loading && results == nil {
            VStack(spacing: 12) {
                ProgressView()
                Text("Recogiendo del buzón…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let results {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let collectError {
                        Label("No se pudo abrir el buzón. Lo que ya tenías sigue aquí. (\(collectError))", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if results.evaluationCount == 0 {
                        emptyState
                    } else {
                        summary(results)
                        if !results.mismatches.isEmpty { mismatchNote(results.mismatches) }
                        table(results)
                    }
                }
                .padding(24)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No se pudo abrir esta coevaluación")
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
            Image(systemName: "person.2")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Todavía no ha llegado ninguna evaluación")
                .font(.headline)
            Text("Aparecen aquí solas cada vez que abres esta pantalla.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func summary(_ results: WebPeerResults) -> some View {
        HStack(spacing: 12) {
            tile("Han enviado algo", "\(results.studentsWhoSent) de \(results.rows.count)")
            tile("Evaluaciones recibidas", "\(results.evaluationCount)")
            tile("Parejas que no coinciden", "\(results.mismatches.count)", warning: !results.mismatches.isEmpty)
        }
    }

    private func tile(_ label: String, _ value: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(warning ? Color.orange : Color.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func mismatchNote(_ mismatches: [WebPeerResults.Mismatch]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Revisa estas parejas.")
                    .font(.callout.weight(.semibold))
                ForEach(mismatches) { m in
                    Text(m.targetHasNotSent
                         ? "\(m.evaluatorName) eligió a \(m.targetName), que todavía no ha enviado nada."
                         : "\(m.evaluatorName) evaluó a \(m.targetName), pero \(m.targetName) nunca evaluó a \(m.evaluatorName).")
                        .font(.callout)
                }
                Text("Cuentan en la media igualmente. Si alguna no te cuadra, habla con esa pareja en clase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func table(_ results: WebPeerResults) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("Alumno")
                Text("Evaluaciones")
                ForEach(results.criteria) { Text($0.title) }
                Text("Media 1-4")
                Text("Correo")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(results.rows) { fila in
                GridRow {
                    Text(fila.name)
                    Text("\(fila.evaluationCount)").monospacedDigit()
                    if fila.evaluationCount == 0 {
                        Text("Nadie le ha evaluado todavía")
                            .foregroundStyle(.secondary)
                            .gridCellColumns(results.criteria.count + 1)
                    } else {
                        ForEach(Array(fila.averages.enumerated()), id: \.offset) { _, media in
                            Text(media.map { WebPeerResultsMail.format($0, locale: "es") } ?? "–").monospacedDigit()
                        }
                        Text(fila.overall.map { WebPeerResultsMail.format($0, locale: "es") } ?? "–")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(WebSubmissionBulkMailPlanner.isPlausibleAddress(fila.email ?? "") ? "Sí" : "Sin correo")
                        .foregroundStyle(WebSubmissionBulkMailPlanner.isPlausibleAddress(fila.email ?? "") ? Color.primary : Color.orange)
                }
                .font(.callout)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Resultados por alumno")
    }

    private func refresh(collectFirst: Bool) async {
        if collectFirst {
            collecting = true
            collectError = await collect()
            collecting = false
        }
        results = await load()
        loading = false
    }
}

/// Manda a cada alumno su media por Mail: en Borradores (de serie) o enviada.
/// Nunca dice quién le evaluó.
struct WebPeerResultsMailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let results: WebPeerResults

    @AppStorage("webPeerResultsSignature") private var signature = ""
    @State private var delivery: WebSubmissionMailDelivery = .drafts
    @State private var selected: Set<Int64> = []
    @State private var previewId: Int64?
    @State private var confirmingSend = false
    @State private var sending = false
    @State private var progress = 0
    @State private var report: WebSubmissionBulkMailReport?

    private var plan: WebSubmissionMailPlan {
        WebPeerResultsMail.plan(results: results, selected: selected, signature: signature)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enviar resultados")
                    .font(.title2.weight(.bold))
                Text("Un correo por alumno con su media. Nunca dice quién le evaluó.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()

            HStack(alignment: .top, spacing: 0) {
                settings
                    .frame(width: 320)
                Divider()
                preview
            }

            Divider()
            footer
        }
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            selected = Set(results.rows
                .filter { $0.evaluationCount > 0 && WebSubmissionBulkMailPlanner.isPlausibleAddress($0.email ?? "") }
                .map(\.studentId))
            previewId = results.rows.first { $0.evaluationCount > 0 }?.studentId
        }
        .confirmationDialog(
            "¿Enviar \(plan.messages.count) correos ahora?",
            isPresented: $confirmingSend,
            titleVisibility: .visible
        ) {
            Button("Enviar \(plan.messages.count) correos") { Task { await deliver() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Salen en cuanto Mail los crea. Con «Borradores» puedes revisarlos antes.")
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cómo sale")
                        .font(.caption.weight(.semibold))
                    Picker("Cómo sale", selection: $delivery) {
                        ForEach(WebSubmissionMailDelivery.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(delivery.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Firma")
                        .font(.caption.weight(.semibold))
                    TextField("Tu nombre", text: $signature)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("A quién")
                        .font(.caption.weight(.semibold))
                    Text(countsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(results.rows) { fila in
                            studentRow(fila)
                            Divider()
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(20)
        }
    }

    private var countsText: String {
        let total = results.rows.count
        let sinCorreo = results.rows.filter { !WebSubmissionBulkMailPlanner.isPlausibleAddress($0.email ?? "") }.count
        let sinEvaluar = results.rows.filter { $0.evaluationCount == 0 }.count
        return "\(plan.messages.count) de \(total) · \(sinCorreo) sin correo · \(sinEvaluar) sin evaluaciones"
    }

    private func studentRow(_ fila: WebPeerResults.Row) -> some View {
        let puede = fila.evaluationCount > 0 && WebSubmissionBulkMailPlanner.isPlausibleAddress(fila.email ?? "")
        return HStack(spacing: 8) {
            Toggle(fila.name, isOn: Binding(
                get: { selected.contains(fila.studentId) },
                set: { if $0 { selected.insert(fila.studentId) } else { selected.remove(fila.studentId) } }
            ))
            .toggleStyle(.checkbox)
            .disabled(!puede)
            Spacer(minLength: 4)
            Text(fila.evaluationCount == 0
                 ? "Sin evaluaciones"
                 : (puede ? "\(fila.evaluationCount) \(fila.evaluationCount == 1 ? "evaluación" : "evaluaciones")" : "Sin correo"))
                .font(.caption)
                .foregroundStyle(puede ? Color.secondary : Color.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(previewId == fila.studentId ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if fila.evaluationCount > 0 { previewId = fila.studentId } }
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report {
                Label(report.summary, systemImage: report.permissionDenied || !report.failures.isEmpty ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(report.permissionDenied || !report.failures.isEmpty ? Color.orange : Color.green)
            }
            if let fila = results.rows.first(where: { $0.studentId == previewId }) {
                Text("Vista previa · \(fila.name)")
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Asunto: \(WebPeerResultsMail.subject(title: results.title, locale: results.locale))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    Text(WebPeerResultsMail.body(row: fila, criteria: results.criteria, locale: results.locale, signature: signature))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("El texto sale en el idioma del formulario. El punto fuerte y la meta salen del criterio más alto y del más bajo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Elige un alumno con evaluaciones para ver su correo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if sending {
                ProgressView(value: Double(progress), total: Double(max(plan.messages.count, 1)))
                    .frame(width: 160)
                Text("\(progress) de \(plan.messages.count)")
                    .font(.caption)
                    .monospacedDigit()
            }
            Spacer()
            Button(report == nil ? "Cancelar" : "Hecho") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(delivery == .drafts ? "Crear \(plan.messages.count) borradores" : "Enviar \(plan.messages.count) correos") {
                if delivery == .send { confirmingSend = true } else { Task { await deliver() } }
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.isEmpty || sending)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func deliver() async {
        let plan = plan
        sending = true
        progress = 0
        report = await WebSubmissionBulkMailer.deliver(plan: plan, delivery: delivery) { hechos in
            progress = hechos
        }
        sending = false
    }
}
#endif
