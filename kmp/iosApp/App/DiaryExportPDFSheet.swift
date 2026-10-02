import SwiftUI
import MiGestorKit
#if canImport(QuickLook)
import QuickLook
#endif

struct DiaryExportPDFSheet: View {
    let className: String
    let entries: [DiaryTimelineEntry]
    let aggregatesBySessionId: [Int64: SessionJournalAggregate]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedQuarter: DiaryTimelineQuarter = .all
    @State private var includeReflections: Bool = true
    @State private var includeIncidents: Bool = true
    @State private var onlyCompleted: Bool = false
    @State private var generatedPdfUrl: URL? = nil
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil

    private var filteredEntries: [DiaryTimelineEntry] {
        entries.filter { entry in
            let matchesQuarter = selectedQuarter.matches(date: entry.date)
            let matchesCompleted = !onlyCompleted || entry.isCompleted
            return matchesQuarter && matchesCompleted
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Alcance del informe") {
                        Picker("Periodo", selection: $selectedQuarter) {
                            ForEach(DiaryTimelineQuarter.allCases) { q in
                                Text(q.rawValue).tag(q)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("Sesiones incluidas")
                            Spacer()
                            Text("\(filteredEntries.count) de \(entries.count)")
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                        }
                    }

                    Section("Opciones de contenido") {
                        Toggle("Incluir reflexiones y desarrollo real", isOn: $includeReflections)
                        Toggle("Incluir incidencias y medidas de apoyo", isOn: $includeIncidents)
                        Toggle("Incluir solo sesiones completadas", isOn: $onlyCompleted)
                    }

                    if let generatedPdfUrl {
                        Section("Documento generado") {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.richtext.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(EvaluationDesign.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(generatedPdfUrl.lastPathComponent)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(filteredEntries.count) sesiones maquetadas · Formato A4")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                ShareLink(item: generatedPdfUrl) {
                                    Label("Compartir", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(AppleDesignSystem.danger)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        generatePDF()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Generar PDF", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(filteredEntries.isEmpty || isGenerating)
                }
                .padding(16)
                .background(appCardBackground(for: colorScheme))
            }
            .navigationTitle("Exportar Diario de Aula a PDF")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                generatePDF()
            }
            .appOnChange(of: selectedQuarter) { _ in generatePDF() }
            .appOnChange(of: includeReflections) { _ in generatePDF() }
            .appOnChange(of: includeIncidents) { _ in generatePDF() }
            .appOnChange(of: onlyCompleted) { _ in generatePDF() }
        }
        .frame(minWidth: 480, minHeight: 440)
    }

    private func generatePDF() {
        isGenerating = true
        errorMessage = nil

        let options = DiaryClassPDFRenderer.RenderOptions(
            schoolName: "Fundación Educativa Madre Micaela",
            teacherName: "Profesorado de Educación Física",
            className: className,
            academicYear: "2026-2027",
            periodTitle: selectedQuarter.rawValue,
            includeReflections: includeReflections,
            includeIncidents: includeIncidents,
            onlyCompleted: onlyCompleted
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let url = DiaryClassPDFRenderer.writeToTemporaryFile(
                entries: filteredEntries,
                aggregatesBySessionId: aggregatesBySessionId,
                options: options
            )

            DispatchQueue.main.async {
                self.isGenerating = false
                if let url {
                    self.generatedPdfUrl = url
                    AppleInteractionFeedback.play(.success)
                } else {
                    self.errorMessage = "No se pudo generar el documento PDF."
                    AppleInteractionFeedback.play(.error)
                }
            }
        }
    }
}
