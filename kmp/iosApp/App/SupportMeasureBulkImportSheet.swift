import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

/// Importación masiva de medidas Nivel III desde una tabla Excel propia del docente
/// (un grupo entero de una vez). Comparte estilo con `StudentImportSheet`: cabecera,
/// resumen, lista revisable fila a fila y confirmación explícita antes de guardar nada.
///
/// Ninguna fila se importa hasta que el alumno queda confirmado: una coincidencia
/// exacta de nombre completo se preselecciona, pero cualquier coincidencia parcial
/// (nombres/apellidos abreviados) o ambigua exige que el docente elija a mano en un
/// desplegable — asignar una medida NEE al alumno equivocado es un error grave.
struct SupportMeasureBulkImportSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let classId: Int64
    let roster: [Student]
    let onImported: () -> Void

    @State private var isPickingFile = false
    @State private var result: SupportMeasureBulkImportResult?
    @State private var claseFilter: String?
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var visibleRows: [SupportMeasureImportRow] {
        guard let result else { return [] }
        guard let claseFilter, !claseFilter.isEmpty else { return result.rows }
        return result.rows.filter { $0.claseValue == claseFilter }
    }

    private var confirmedCount: Int { visibleRows.filter { $0.confirmedStudent != nil }.count }
    private var needsReviewCount: Int { visibleRows.filter { $0.confirmedStudent == nil }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let result {
                ScrollView {
                    summary(result)
                    rowsList
                }
                .background(appSecondarySystemBackgroundColor().opacity(0.35))
            } else {
                emptyState
            }

            Divider()
            footer
        }
        .background(appPageBackground(for: colorScheme))
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 680)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.xlsx],
            allowsMultipleSelection: false
        ) { fileResult in
            handlePickedFile(fileResult)
        }
        .alert("No se pudo importar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Importar medidas Nivel III")
                    .font(.title2.weight(.bold))
                Text("Alumnos en filas, medidas marcadas con 'x' en columnas. Confirma cada alumno antes de guardar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Selecciona el archivo Excel del grupo")
                .font(.headline)
            Text("Debe tener una columna 'Clase' y una columna por alumno con las medidas marcadas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                isPickingFile = true
            } label: {
                Label("Elegir archivo…", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func summary(_ result: SupportMeasureBulkImportResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                importMetric("Filas detectadas", "\(visibleRows.count)")
                importMetric("Confirmados", "\(confirmedCount)")
                importMetric("Por revisar", "\(needsReviewCount)")
                Spacer()
            }

            if result.claseValues.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filtrar por columna 'Clase'")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Clase", selection: $claseFilter) {
                        Text("Todas las filas").tag(Optional<String>.none)
                        ForEach(result.claseValues, id: \.self) { value in
                            Text(value).tag(Optional(value))
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if result.hadUnrecognizedColumns {
                Label("Algunas columnas del archivo no se han reconocido y se han ignorado.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if needsReviewCount > 0 {
                Label("Las filas sin alumno confirmado no se importarán. Elige el alumno correcto en el desplegable de cada fila.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        }
        .padding(24)
    }

    private var rowsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(visibleRows) { row in
                importRow(row)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func importRow(_ row: SupportMeasureImportRow) -> some View {
        let isConfirmed = row.confirmedStudent != nil
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isConfirmed ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(isConfirmed ? .green : .orange)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(row.rawName)
                        .font(.body.weight(.medium))
                    if isConfirmed {
                        Text("→ \(row.confirmedStudent!.fullName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                studentPicker(for: row)

                if !row.measures.isEmpty {
                    WorkspaceFlowLayout(spacing: 6) {
                        ForEach(row.measures) { measure in
                            WorkspaceTag(text: measure.displayName, systemImage: "checkmark.seal")
                        }
                    }
                }
                if !row.notes.isEmpty {
                    Text(row.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.softBorder.opacity(0.8), lineWidth: 1)
        }
    }

    /// Desplegable de confirmación: prioriza los candidatos sugeridos por el emparejador
    /// (nombre parcial/abreviado) y debajo ofrece el resto del roster, para que el
    /// docente pueda corregir a mano cualquier caso — ambiguo, sin coincidencia o mal
    /// interpretado por el algoritmo.
    private func studentPicker(for row: SupportMeasureImportRow) -> some View {
        let suggested: [Student]
        if case .suggested(let candidates) = row.matchStatus {
            suggested = candidates
        } else {
            suggested = []
        }
        let suggestedIds = Set(suggested.map(\.id))
        let others = roster.filter { !suggestedIds.contains($0.id) }.sorted { $0.fullName < $1.fullName }

        return Menu {
            if !suggested.isEmpty {
                Section("Sugerencias") {
                    ForEach(suggested, id: \.id) { student in
                        Button(student.fullName) { setConfirmedStudent(student, for: row.id) }
                    }
                }
            }
            Section(suggested.isEmpty ? "Alumnado del grupo" : "Otros alumnos del grupo") {
                ForEach(others, id: \.id) { student in
                    Button(student.fullName) { setConfirmedStudent(student, for: row.id) }
                }
            }
            if row.confirmedStudent != nil {
                Button("Quitar coincidencia", role: .destructive) { setConfirmedStudent(nil, for: row.id) }
            }
        } label: {
            Label(
                row.confirmedStudent == nil ? "Asignar alumno…" : "Cambiar alumno",
                systemImage: "person.crop.circle.badge.questionmark"
            )
            .font(.caption.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func setConfirmedStudent(_ student: Student?, for rowID: UUID) {
        guard let index = result?.rows.firstIndex(where: { $0.id == rowID }) else { return }
        result?.rows[index].confirmedStudent = student
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(confirmedCount == 0 ? "Confirma al menos un alumno para importar." : "\(confirmedCount) alumnos listos para importar.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                Task { await confirmImport() }
            } label: {
                Label(isImporting ? "Importando…" : "Importar", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(confirmedCount == 0 || isImporting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private func importMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
        }
        .frame(minWidth: 112, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handlePickedFile(_ fileResult: Result<[URL], Error>) {
        do {
            guard let url = try fileResult.get().first else { return }
            var parsed = try SupportMeasureBulkImport.parse(url: url)
            parsed.rows = SupportMeasureBulkImport.match(rows: parsed.rows, against: roster)
            result = parsed
            claseFilter = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmImport() async {
        isImporting = true
        defer { isImporting = false }

        let nowIso = AppDateTimeSupport.isoDateFormatter.string(from: Date())
        for row in visibleRows {
            guard let student = row.confirmedStudent else { continue }
            for measure in row.measures {
                var draft = SupportMeasureDraft(
                    studentId: student.id,
                    level: .iii,
                    measureType: measure,
                    startDateIso: nowIso
                )
                draft.followUpNotes = row.notes
                _ = try? await bridge.saveSupportMeasure(draft: draft)
            }
        }
        onImported()
        dismiss()
    }
}
