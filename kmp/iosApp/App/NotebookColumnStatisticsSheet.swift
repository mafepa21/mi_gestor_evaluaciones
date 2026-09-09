import SwiftUI
import MiGestorKit

// MARK: - Modelo y Motor de Cálculo de Estadísticas de Columna
struct StudentColumnScore: Identifiable {
    let id: Int64
    let student: Student
    let name: String
    let score: Double
}

enum LomloeBandKind: String, CaseIterable, Identifiable {
    case sobresaliente
    case notable
    case bien
    case suficiente
    case insuficiente

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sobresaliente: return "Sobresaliente"
        case .notable: return "Notable"
        case .bien: return "Bien"
        case .suficiente: return "Suficiente"
        case .insuficiente: return "Insuficiente"
        }
    }

    var rangeLabel: String {
        switch self {
        case .sobresaliente: return "9.0 – 10.0"
        case .notable: return "7.0 – 8.9"
        case .bien: return "6.0 – 6.9"
        case .suficiente: return "5.0 – 5.9"
        case .insuficiente: return "0.0 – 4.9"
        }
    }

    var icon: String {
        switch self {
        case .sobresaliente: return "star.fill"
        case .notable: return "sparkles"
        case .bien: return "checkmark.seal.fill"
        case .suficiente: return "checkmark.circle.fill"
        case .insuficiente: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .sobresaliente:
            return Color(red: 0.14, green: 0.62, blue: 0.40) // Verde Esmeralda intenso
        case .notable:
            return Color(red: 0.16, green: 0.46, blue: 0.88) // Azul Cobalto
        case .bien:
            return Color(red: 0.16, green: 0.64, blue: 0.74) // Turquesa
        case .suficiente:
            return Color(red: 0.86, green: 0.52, blue: 0.16) // Ámbar Cálido
        case .insuficiente:
            return Color(red: 0.84, green: 0.24, blue: 0.28) // Rojo Coral
        }
    }

    static func band(for score: Double) -> LomloeBandKind {
        if score >= 9.0 { return .sobresaliente }
        if score >= 7.0 { return .notable }
        if score >= 6.0 { return .bien }
        if score >= 5.0 { return .suficiente }
        return .insuficiente
    }
}

struct LomloeBandDistribution: Identifiable {
    let band: LomloeBandKind
    let students: [StudentColumnScore]
    let totalEvaluated: Int

    var id: String { band.id }
    var count: Int { students.count }

    var percentage: Double {
        guard totalEvaluated > 0 else { return 0.0 }
        return (Double(count) / Double(totalEvaluated)) * 100.0
    }
}

@MainActor
struct NotebookColumnStatisticsReport {
    let column: NotebookColumnDefinition
    let classTitle: String
    let totalStudents: Int
    let evaluatedScores: [StudentColumnScore]
    let pendingStudents: [Student]

    var evaluatedCount: Int { evaluatedScores.count }
    var pendingCount: Int { pendingStudents.count }

    var evaluatedPercentage: Double {
        guard totalStudents > 0 else { return 0.0 }
        return (Double(evaluatedCount) / Double(totalStudents)) * 100.0
    }

    // Media aritmética
    var mean: Double? {
        guard !evaluatedScores.isEmpty else { return nil }
        let sum = evaluatedScores.reduce(0.0) { $0 + $1.score }
        return sum / Double(evaluatedScores.count)
    }

    // Mediana
    var median: Double? {
        guard !evaluatedScores.isEmpty else { return nil }
        let sorted = evaluatedScores.map(\.score).sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        } else {
            return (sorted[(count / 2) - 1] + sorted[count / 2]) / 2.0
        }
    }

    // Moda (con redondeo a 1 decimal)
    var mode: Double? {
        guard !evaluatedScores.isEmpty else { return nil }
        var frequency: [Double: Int] = [:]
        for s in evaluatedScores {
            let rounded = (s.score * 10.0).rounded() / 10.0
            frequency[rounded, default: 0] += 1
        }
        guard let maxFreq = frequency.values.max(), maxFreq > 1 || evaluatedScores.count == 1 else {
            return nil
        }
        return frequency.first(where: { $0.value == maxFreq })?.key
    }

    // Desviación típica (sigma)
    var standardDeviation: Double? {
        guard let mean, evaluatedScores.count > 1 else { return nil }
        let variance = evaluatedScores.reduce(0.0) { acc, next in
            acc + pow(next.score - mean, 2)
        } / Double(evaluatedScores.count)
        return sqrt(variance)
    }

    // Aprobados (score >= 5.0)
    var passedScores: [StudentColumnScore] {
        evaluatedScores.filter { $0.score >= 5.0 }
    }

    var passedCount: Int { passedScores.count }

    var passedPercentage: Double {
        guard evaluatedCount > 0 else { return 0.0 }
        return (Double(passedCount) / Double(evaluatedCount)) * 100.0
    }

    // Suspensos (score < 5.0)
    var failedScores: [StudentColumnScore] {
        evaluatedScores.filter { $0.score < 5.0 }
    }

    var failedCount: Int { failedScores.count }

    var failedPercentage: Double {
        guard evaluatedCount > 0 else { return 0.0 }
        return (Double(failedCount) / Double(evaluatedCount)) * 100.0
    }

    // Nota Máxima y Mínima
    var maxScore: Double? {
        evaluatedScores.map(\.score).max()
    }

    var studentsWithMaxScore: [StudentColumnScore] {
        guard let maxScore else { return [] }
        return evaluatedScores.filter { abs($0.score - maxScore) < 0.001 }
    }

    var minScore: Double? {
        evaluatedScores.map(\.score).min()
    }

    var studentsWithMinScore: [StudentColumnScore] {
        guard let minScore else { return [] }
        return evaluatedScores.filter { abs($0.score - minScore) < 0.001 }
    }

    // Distribución por tramos LOMLOE
    var lomloeDistributions: [LomloeBandDistribution] {
        LomloeBandKind.allCases.map { band in
            let matching = evaluatedScores.filter { LomloeBandKind.band(for: $0.score) == band }
            return LomloeBandDistribution(band: band, students: matching, totalEvaluated: evaluatedCount)
        }
    }

    // Calificación cualitativa de la media
    var meanQualitativeLabel: String {
        guard let mean else { return "Sin calificar" }
        return LomloeBandKind.band(for: mean).title
    }

    // Generador de texto para actas y claustro
    func generateSummaryText() -> String {
        let meanText = mean.map { String(format: "%.2f", $0) } ?? "N/D"
        let medianText = median.map { String(format: "%.2f", $0) } ?? "N/D"
        let modeText = mode.map { String(format: "%.2f", $0) } ?? "N/D"
        let stdDevText = standardDeviation.map { String(format: "±%.2f", $0) } ?? "N/D"
        let maxText = maxScore.map { String(format: "%.2f", $0) } ?? "N/D"
        let minText = minScore.map { String(format: "%.2f", $0) } ?? "N/D"

        let topStudents = studentsWithMaxScore.map(\.name).joined(separator: ", ")
        let bottomStudents = studentsWithMinScore.map(\.name).joined(separator: ", ")

        var lines: [String] = []
        lines.append("📊 ESTADÍSTICAS DE EVALUACIÓN: \(column.title.uppercased())")
        lines.append("Grupo: \(classTitle) | Tipo: \(NotebookColumnStatisticsSheet.columnTypeTitle(for: column))")
        if column.countsTowardAverage {
            lines.append("Ponderación en la media: \(String(format: "%.1f", column.weight))%")
        } else {
            lines.append("Ponderación: Excluida de la media")
        }
        lines.append("Alumnado evaluado: \(evaluatedCount) de \(totalStudents) (\(String(format: "%.0f", evaluatedPercentage))%)")
        lines.append("")
        lines.append("• Media aritmética: \(meanText) (\(meanQualitativeLabel))")
        lines.append("• Mediana: \(medianText) | Moda: \(modeText) | Desv. típica: \(stdDevText)")
        lines.append("• Tasa de aprobados: \(String(format: "%.1f", passedPercentage))% (\(passedCount) aptos / \(failedCount) no aptos)")
        lines.append("• Calificación máxima: \(maxText)\(topStudents.isEmpty ? "" : " (\(topStudents))")")
        lines.append("• Calificación mínima: \(minText)\(bottomStudents.isEmpty ? "" : " (\(bottomStudents))")")
        lines.append("")
        lines.append("Distribución LOMLOE:")
        for dist in lomloeDistributions {
            lines.append("- \(dist.band.title) (\(dist.band.rangeLabel)): \(dist.count) al. (\(String(format: "%.0f", dist.percentage))%)")
        }
        if pendingCount > 0 {
            lines.append("- Sin calificar / NP: \(pendingCount) al. (\(String(format: "%.0f", 100.0 - evaluatedPercentage))%)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Extractor de Notas
@MainActor
enum NotebookStatisticsExtractor {
    static func buildReport(
        column: NotebookColumnDefinition,
        rows: [NotebookRow],
        bridge: KmpBridge?,
        classTitle: String
    ) -> NotebookColumnStatisticsReport {
        var evaluatedScores: [StudentColumnScore] = []
        var pendingStudents: [Student] = []

        for row in rows {
            let fullName = "\(row.student.firstName) \(row.student.lastName)".trimmingCharacters(in: .whitespaces)
            if let score = extractScore(from: row, column: column, bridge: bridge) {
                // Clamping de seguridad al intervalo 0.0 - 10.0
                let clamped = min(max(score, 0.0), 10.0)
                evaluatedScores.append(StudentColumnScore(
                    id: row.student.id,
                    student: row.student,
                    name: fullName.isEmpty ? "Alumno #\(row.student.id)" : fullName,
                    score: clamped
                ))
            } else {
                pendingStudents.append(row.student)
            }
        }

        return NotebookColumnStatisticsReport(
            column: column,
            classTitle: classTitle,
            totalStudents: rows.count,
            evaluatedScores: evaluatedScores,
            pendingStudents: pendingStudents
        )
    }

    private static func extractScore(
        from row: NotebookRow,
        column: NotebookColumnDefinition,
        bridge: KmpBridge?
    ) -> Double? {
        // 1. Nota numérica directa persistida
        if let value = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
            return value
        }

        // 2. Columna tipo check / binaria
        if column.type == .check,
           let value = row.persistedCells.first(where: { $0.columnId == column.id })?.boolValue?.boolValue {
            return value ? 10.0 : 0.0
        }

        // 3. Celda de evaluación vinculada
        if let evaluationId = column.evaluationId?.int64Value,
           let value = row.cells.first(where: { $0.evaluationId == evaluationId })?.value?.doubleValue {
            return value
        }

        // 4. Rúbrica evaluada a través de KmpBridge
        if column.type == .rubric, let bridge {
            let raw = bridge.rubricGradeOnTenText(studentId: row.student.id, column: column)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let parsed = Double(raw) {
                return parsed
            }
        }

        // 5. Nota numérica o fórmula a través de KmpBridge
        if (column.type == .numeric || column.type == .calculated), let bridge {
            let raw = bridge.numericGradeText(studentId: row.student.id, column: column)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let parsed = Double(raw) {
                return parsed
            }
        }

        return nil
    }
}

// MARK: - Vista Principal de Estadísticas de Columna
@MainActor
struct NotebookColumnStatisticsSheet: View {
    let column: NotebookColumnDefinition
    let rows: [NotebookRow]
    let bridge: KmpBridge?
    let classTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBandDetail: LomloeBandKind? = nil
    @State private var isCopied = false

    private var report: NotebookColumnStatisticsReport {
        NotebookStatisticsExtractor.buildReport(
            column: column,
            rows: rows,
            bridge: bridge,
            classTitle: classTitle
        )
    }

    private var columnColor: Color {
        if let hex = column.colorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return EvaluationDesign.accent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Cabecera temática enriquecida
                    headerCard

                    if report.evaluatedCount == 0 {
                        emptyStateCard
                    } else {
                        // Tarjetas de resumen de métricas clave (KPIs)
                        kpisSection

                        // Gráfico de distribución de notas LOMLOE (Histograma)
                        distributionSection

                        // Tarjetas de extremos (máx/mín)
                        extremesSection
                    }
                }
                .padding(20)
            }
            .background(sheetBackground)
            .navigationTitle("Estadísticas")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hecho") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyReportToClipboard()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "Copiado" : "Copiar informe")
                        }
                        .font(.system(size: 14, weight: .medium))
                    }
                    .disabled(report.evaluatedCount == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 580, idealWidth: 620, minHeight: 640, idealHeight: 700)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Cabecera Temática
    private var headerCard: some View {
        HStack(spacing: 16) {
            // Icono del instrumento
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(columnColor.opacity(0.14))
                    .frame(width: 54, height: 54)

                Image(systemName: columnSystemIcon(for: column))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(columnColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(column.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    if column.countsTowardAverage {
                        HStack(spacing: 3) {
                            Image(systemName: "percent")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(String(format: "%.0f", column.weight))%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(EvaluationDesign.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(EvaluationDesign.accent.opacity(0.12))
                        )
                    } else {
                        Text("No pondera")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }

                HStack(spacing: 6) {
                    Text(classTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    Text("·")
                        .foregroundStyle(Color.secondary.opacity(0.5))

                    Text(Self.columnTypeTitle(for: column))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.secondary)
                }

                // Barra de cobertura de evaluados
                HStack(spacing: 6) {
                    Text("\(report.evaluatedCount) de \(report.totalStudents) evaluados (\(String(format: "%.0f", report.evaluatedPercentage))%)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(report.evaluatedPercentage >= 80 ? EvaluationDesign.success : Color.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Tarjetas KPI
    private var kpisSection: some View {
        VStack(spacing: 12) {
            // Tarjeta grande de Media Aritmética
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEDIA DEL GRUPO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    if let mean = report.mean {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.2f", mean))
                                .font(.system(size: 38, weight: .black, design: .rounded))
                                .foregroundStyle(RubricsStyle.gradeColor(forScoreOutOfTen: mean))

                            Text(report.meanQualitativeLabel.uppercased())
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(RubricsStyle.gradeColor(forScoreOutOfTen: mean))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(RubricsStyle.gradeColor(forScoreOutOfTen: mean).opacity(0.15))
                                )
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                // Barra de aprobados vs suspensos
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(EvaluationDesign.success)
                            .frame(width: 8, height: 8)
                        Text("\(String(format: "%.0f", report.passedPercentage))% Aprobados")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                    }

                    Text("\(report.passedCount) aptos · \(report.failedCount) no aptos")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    // Barra visual biseccionada
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            Rectangle()
                                .fill(EvaluationDesign.success)
                                .frame(width: max(0, geo.size.width * CGFloat(report.passedPercentage / 100.0) - 1))

                            Rectangle()
                                .fill(EvaluationDesign.danger)
                                .frame(width: max(0, geo.size.width * CGFloat(report.failedPercentage / 100.0) - 1))
                        }
                        .clipShape(Capsule())
                    }
                    .frame(width: 140, height: 7)
                    .padding(.top, 2)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
            )

            // Sub-grid de 3 métricas estadísticas
            HStack(spacing: 12) {
                metricSubCard(
                    title: "MEDIANA",
                    value: report.median.map { String(format: "%.2f", $0) } ?? "—",
                    icon: "arrow.left.and.right"
                )

                metricSubCard(
                    title: "MODA",
                    value: report.mode.map { String(format: "%.2f", $0) } ?? "—",
                    icon: "repeat"
                )

                metricSubCard(
                    title: "DESV. TÍPICA",
                    value: report.standardDeviation.map { String(format: "±%.2f", $0) } ?? "—",
                    icon: "chart.line.uptrend.xyaxis"
                )
            }
        }
    }

    private func metricSubCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.secondary)

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        )
    }

    // MARK: - Gráfico de Distribución LOMLOE (Histograma)
    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Distribución por Tramos LOMLOE")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Spacer()

                Text("Toca un tramo para ver alumnos")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
            }

            VStack(spacing: 10) {
                let maxCount = report.lomloeDistributions.map(\.count).max() ?? 1
                let effectiveMax = max(maxCount, 1)

                ForEach(report.lomloeDistributions) { dist in
                    VStack(spacing: 6) {
                        Button {
                            AppleInteractionFeedback.play(.selection)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if selectedBandDetail == dist.band {
                                    selectedBandDetail = nil
                                } else {
                                    selectedBandDetail = dist.band
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                // Etiqueta del tramo con icono
                                HStack(spacing: 5) {
                                    Image(systemName: dist.band.icon)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(dist.band.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(dist.band.color)
                                .frame(width: 125, alignment: .leading)

                                // Barra horizontal animada
                                GeometryReader { geo in
                                    let barWidth = geo.size.width * CGFloat(dist.count) / CGFloat(effectiveMax)

                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(height: 20)

                                        if dist.count > 0 {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [dist.band.color, dist.band.color.opacity(0.85)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: max(16, barWidth), height: 20)
                                                .shadow(color: dist.band.color.opacity(0.3), radius: 3, x: 0, y: 1)
                                        }
                                    }
                                }
                                .frame(height: 20)

                                // Recuento y porcentaje
                                HStack(spacing: 4) {
                                    Text("\(dist.count)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text("(\(String(format: "%.0f", dist.percentage))%)")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.secondary)
                                }
                                .frame(width: 75, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Desglose de alumnos en el tramo seleccionado
                        if selectedBandDetail == dist.band && !dist.students.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(dist.students) { item in
                                    HStack {
                                        Circle()
                                            .fill(dist.band.color.opacity(0.2))
                                            .frame(width: 6, height: 6)
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.primary)
                                        Spacer()
                                        Text(String(format: "%.2f", item.score))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(dist.band.color)
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(dist.band.color.opacity(0.06))
                                    )
                                }
                            }
                            .padding(.leading, 135)
                            .padding(.vertical, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        )
    }

    // MARK: - Extremos (Máxima y Mínima)
    private var extremesSection: some View {
        HStack(spacing: 12) {
            // Nota máxima
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.90, green: 0.72, blue: 0.18)) // Dorado
                    Text("NOTA MÁXIMA")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }

                if let maxVal = report.maxScore {
                    Text(String(format: "%.2f", maxVal))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(EvaluationDesign.success)
                        .monospacedDigit()

                    let names = report.studentsWithMaxScore.map(\.name).joined(separator: ", ")
                    Text(names)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                } else {
                    Text("—")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
            )

            // Nota mínima
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(EvaluationDesign.danger)
                    Text("NOTA MÍNIMA")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }

                if let minVal = report.minScore {
                    Text(String(format: "%.2f", minVal))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(minVal < 5.0 ? EvaluationDesign.danger : EvaluationDesign.accent)
                        .monospacedDigit()

                    let names = report.studentsWithMinScore.map(\.name).joined(separator: ", ")
                    Text(names)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                } else {
                    Text("—")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
            )
        }
    }

    // MARK: - Estado Vacío
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .padding(.top, 10)

            Text("Sin calificaciones registradas")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)

            Text("Introduce notas en esta columna o evalúa alumnos para ver la media, la desviación y la distribución LOMLOE.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        )
    }

    // MARK: - Helpers Visuales
    private var cardBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    private var sheetBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    private func columnSystemIcon(for column: NotebookColumnDefinition) -> String {
        if let customIcon = column.iconName, !customIcon.isEmpty {
            return customIcon
        }
        switch column.type {
        case .numeric:
            return "doc.text.fill"
        case .rubric:
            return "sparkles"
        case .calculated:
            return "function"
        case .check:
            return "checklist"
        default:
            return "chart.bar.xaxis"
        }
    }

    static func columnTypeTitle(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric: return "Nota numérica"
        case .rubric: return "Rúbrica"
        case .calculated: return "Fórmula"
        case .check: return "Lista de control"
        case .text: return "Texto"
        case .attendance: return "Asistencia"
        case .icon: return "Icono"
        default: return "Evaluación"
        }
    }

    private func copyReportToClipboard() {
        AppleInteractionFeedback.play(.selection)
        let text = report.generateSummaryText()

        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
