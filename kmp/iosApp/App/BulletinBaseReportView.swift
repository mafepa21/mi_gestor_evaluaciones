import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Panel de detalle de «Base para boletín»: texto anónimo de todo el grupo para pegarlo en una IA.
/// La clave código → nombre solo se muestra en una hoja y nunca entra en lo que se copia o comparte.
struct BulletinBaseReportView: View {
    let bridge: KmpBridge
    let classId: Int64?
    let className: String?
    let termLabel: String
    /// Cambia cuando la pantalla pide recargar (por ejemplo, tras una sincronización).
    let reloadToken: Int

    private enum LoadState {
        case loading
        case loaded(BulletinBaseReport)
        case failed
    }

    private struct LoadKey: Equatable {
        let classId: Int64?
        let termLabel: String
        let reloadToken: Int
        let retry: Int
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var state: LoadState = .loading
    @State private var retryCount = 0
    @State private var isKeyPresented = false
    @State private var showsCopiedNotice = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: LoadKey(classId: classId, termLabel: termLabel, reloadToken: reloadToken, retry: retryCount)) {
                await load()
            }
            .overlay(alignment: .bottom) {
                if showsCopiedNotice {
                    Label("Copiado. Sin nombres.", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .sheet(isPresented: $isKeyPresented) {
                if case .loaded(let report) = state {
                    BulletinBaseKeySheet(entries: report.key)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if classId == nil {
            WorkspaceEmptyState(
                title: "Elige una clase",
                subtitle: "El informe se prepara para todo el alumnado de la clase que elijas.",
                systemImage: "rectangle.3.group"
            )
        } else {
            switch state {
            case .loading:
                loadingView
            case .failed:
                WorkspaceEmptyState(
                    title: "No se pudieron leer los datos",
                    subtitle: "No se ha copiado nada. Prueba otra vez; si sigue fallando, cambia de clase y vuelve.",
                    systemImage: "exclamationmark.triangle",
                    actionTitle: "Reintentar",
                    action: { retryCount += 1 }
                )
            case .loaded(let report) where report.studentCount == 0:
                WorkspaceEmptyState(
                    title: "Esta clase no tiene alumnado",
                    subtitle: "Añade alumnos en Alumnado para poder preparar la base del boletín.",
                    systemImage: "person.3"
                )
            case .loaded(let report):
                loadedView(report)
            }
        }
    }

    // MARK: - Estados

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actionRow(report: nil)
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reuniendo los datos del grupo…")
                        .foregroundStyle(.secondary)
                }
                textCard(BulletinBaseReportBuilder.instructions.joined(separator: "\n") + "\n\n═══ Alumno 01 ═══\nAsistencia: …\nNotas: …")
                    .redacted(reason: .placeholder)
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cargando la base para boletín")
    }

    private func loadedView(_ report: BulletinBaseReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actionRow(report: report)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { metaItems(report) }
                    VStack(alignment: .leading, spacing: 8) { metaItems(report) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !report.lowDataCodes.isEmpty {
                    lowDataNotice(report.lowDataCodes)
                }

                textCard(report.text)
                    .accessibilityLabel("Texto del informe")

                Text("Lo que ves es exactamente lo que se copia. Sin nombres, correos, teléfonos ni datos de inclusión o salud. Revisa el texto antes de pegarlo: un nombre que no sea del grupo no se puede detectar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Base para boletín")
                    .font(.largeTitle.bold())
                Label("Anónimo", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text([className, termLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func actionRow(report: BulletinBaseReport?) -> some View {
        HStack(spacing: 8) {
            Button {
                if let report { copy(report.text) }
            } label: {
                Label("Copiar texto", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("c", modifiers: [.command, .shift])

            if let report {
                ShareLink(item: report.text) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {} label: { Label("Compartir", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Button {
                isKeyPresented = true
            } label: {
                Label("Ver clave", systemImage: "key")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Muestra los nombres reales, solo en pantalla")
        }
        .disabled(report == nil)
    }

    @ViewBuilder
    private func metaItems(_ report: BulletinBaseReport) -> some View {
        metaItem(report.studentCount, singular: "alumno", plural: "alumnos")
        metaItem(report.evaluableColumnCount, singular: "columna evaluable", plural: "columnas evaluables")
        metaItem(report.selfAssessmentCount, singular: "autoevaluación", plural: "autoevaluaciones")
        Text("Generado \(report.generatedAt.formatted(date: .omitted, time: .shortened))")
    }

    private func metaItem(_ count: Int, singular: String, plural: String) -> some View {
        Text("\(Text("\(count)").bold().foregroundStyle(.primary)) \(count == 1 ? singular : plural)")
    }

    private func lowDataNotice(_ codes: [String]) -> some View {
        let names = codes.count <= 6
            ? ListFormatter.localizedString(byJoining: codes)
            : codes.prefix(5).joined(separator: ", ") + " y \(codes.count - 5) más"
        let count = codes.count == 1 ? "1 alumno con pocos datos" : "\(codes.count) alumnos con pocos datos"
        return VStack(alignment: .leading, spacing: 8) {
            Label(count, systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("\(names). Saldrán marcados en el texto. «Pocos datos» = menos de \(BulletinBaseReportBuilder.minimumGrades) notas o menos de \(BulletinBaseReportBuilder.minimumAttendanceDays) días de asistencia en el trimestre.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func textCard(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }

    // MARK: - Acciones

    @MainActor
    private func load() async {
        guard let classId else { return }
        // Si cambia la clase o el trimestre se vuelve a «cargando»; si solo es una recarga, se deja el texto visible.
        if case .loaded(let current) = state, current.className == className, current.termLabel == termLabel {
        } else {
            state = .loading
        }
        let range = Self.period(for: termLabel)
        do {
            let report = try await bridge.buildBulletinBaseReport(classId: classId, termLabel: termLabel, period: range)
            guard !Task.isCancelled, self.classId == classId else { return }
            state = .loaded(report)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed
        }
    }

    static func period(for termLabel: String) -> (start: Date, end: Date) {
        (AttendanceMatrixRange(rawValue: termLabel) ?? .fullYear).dateRange()
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        AccessibilityNotification.Announcement("Copiado. Sin nombres.").post()
        withAnimation(.snappy) { showsCopiedNotice = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.snappy) { showsCopiedNotice = false }
        }
    }
}

/// Hoja con la clave código → nombre. Solo pantalla: no se puede copiar ni compartir.
struct BulletinBaseKeySheet: View {
    let entries: [BulletinBaseKeyEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.code)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.studentName)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Contiene nombres reales: son datos personales. Úsala para saber a quién es cada comentario. No se puede copiar ni se comparte.")
                }
            }
            .textSelection(.disabled)
            .navigationTitle("Clave del informe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
