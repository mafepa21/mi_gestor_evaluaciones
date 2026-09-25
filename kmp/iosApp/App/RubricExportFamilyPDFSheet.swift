import SwiftUI
import MiGestorKit

/// Hoja modal para configurar, generar y compartir el informe de evaluación individual por rúbrica en PDF.
struct RubricExportFamilyPDFSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let rubricDetail: RubricDetail
    let selectedLevelIds: [Int64: Int64]
    let studentName: String
    let className: String
    let currentScore: Double

    @State private var schoolName: String = "Centro Educativo"
    @State private var departmentName: String = "Departamento de Educación Física"
    @State private var teacherName: String = "Profesorado de Educación Física"
    @State private var teacherFeedback: String = ""
    @State private var proposalsForImprovement: String = ""

    @State private var isGenerating: Bool = false
    @State private var generatedPDFUrl: URL? = nil
    @State private var errorMessage: String? = nil

    private var criteriaEvaluationItems: [RubricFamilyReportPDFRenderer.CriterionEvaluationItem] {
        rubricDetail.criteria.compactMap { cWithLevels -> RubricFamilyReportPDFRenderer.CriterionEvaluationItem? in
            let criterion = cWithLevels.criterion
            guard let selectedLevelId = selectedLevelIds[criterion.id],
                  let level = cWithLevels.levels.first(where: { $0.id == selectedLevelId }) else {
                return nil
            }
            return RubricFamilyReportPDFRenderer.CriterionEvaluationItem(
                criterionName: sanitizeDomainText(criterion.description_, fallback: "Criterio"),
                weight: criterion.weight,
                selectedLevelOrder: Int(level.order),
                selectedLevelName: level.name,
                selectedLevelPoints: Int(level.points),
                selectedLevelDescription: level.description_ ?? ""
            )
        }
    }

    private var studentSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATOS DEL ALUMNO/A Y RÚBRICA")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("\(className) · \(rubricDetail.rubric.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", currentScore))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(RubricsStyle.gradeColor(forScoreOutOfTen: currentScore))
                    Text("sobre 10")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var institutionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATOS DEL CENTRO Y DOCENTE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nombre del Centro")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Centro Educativo", text: $schoolName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Departamento o Materia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Departamento / Materia", text: $departmentName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Docente Evaluador/a")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Docente Evaluador/a", text: $teacherName)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FEEDBACK FORMATIVO PARA LA FAMILIA")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Logros y puntos fuertes observados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $teacherFeedback)
                    .frame(height: 64)
                    .padding(4)
                    .background(appPageBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Propuestas de mejora y recomendaciones familiares")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $proposalsForImprovement)
                    .frame(height: 64)
                    .padding(4)
                    .background(appPageBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var exportActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPORTACIÓN OFICIAL A4")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if let generatedPDFUrl {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(EvaluationDesign.success)
                        Text("Informe PDF generado correctamente")
                            .font(.subheadline.weight(.semibold))
                    }

                    ShareLink(item: generatedPDFUrl) {
                        Label("Compartir o Imprimir Informe PDF", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isGenerating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Maquetando documento oficial...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                Button {
                    generatePDF()
                } label: {
                    Label("Generar Informe PDF Maquetado", systemImage: "doc.text.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(EvaluationDesign.danger)
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    studentSummaryCard
                    institutionCard
                    feedbackCard
                    exportActionCard
                }
                .padding(16)
            }
            .background(appPageBackground(for: colorScheme))
            .navigationTitle("Informe PDF para Familias")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 520)
        #endif
    }

    private func generatePDF() {
        isGenerating = true
        errorMessage = nil

        let options = RubricFamilyReportPDFRenderer.RenderOptions(
            schoolName: schoolName,
            departmentName: departmentName,
            studentName: studentName,
            className: className,
            rubricTitle: rubricDetail.rubric.name,
            score: currentScore,
            evaluationDate: Date(),
            teacherName: teacherName,
            teacherFeedback: teacherFeedback,
            proposalsForImprovement: proposalsForImprovement
        )

        let items = criteriaEvaluationItems

        DispatchQueue.global(qos: .userInitiated).async {
            let url = RubricFamilyReportPDFRenderer.writeToTemporaryFile(
                criteriaItems: items,
                options: options
            )

            DispatchQueue.main.async {
                self.isGenerating = false
                if let url {
                    self.generatedPDFUrl = url
                    AppleInteractionFeedback.play(.success)
                } else {
                    self.errorMessage = "No se pudo generar el archivo PDF."
                    AppleInteractionFeedback.play(.error)
                }
            }
        }
    }
}
