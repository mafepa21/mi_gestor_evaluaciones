import SwiftUI
import MiGestorKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct NotebookFormulaKeyboard: View {
    @Binding var formula: String
    let availableColumns: [NotebookColumnDefinition]

    private let formulaTokens = ["=", "+", "-", "*", "/", "(", ")", "SUMA", "PROMEDIO", "MAX", "MIN", "SI", ","]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("fx")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("=[columna]+[columna]", text: $formula)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.25))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(formulaTokens, id: \.self) { token in
                        Button(token) {
                            appendToken(token)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !availableColumns.isEmpty {
                        Divider()
                            .frame(height: 24)

                        ForEach(availableColumns, id: \.id) { column in
                            Button {
                                appendColumnReference(column)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: iconName(for: column))
                                        .font(.caption.weight(.bold))
                                    Text(column.title)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Insertar referencia [\(column.id)]")
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if !availableColumns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Columnas disponibles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(availableColumns, id: \.id) { column in
                            Button {
                                appendColumnReference(column)
                            } label: {
                                Label(column.title, systemImage: iconName(for: column))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func appendToken(_ token: String) {
        formula += token
    }

    private func appendColumnReference(_ column: NotebookColumnDefinition) {
        formula += "[\(column.id)]"
    }

    private func iconName(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric:
            return "number"
        case .rubric:
            return "checklist"
        case .attendance:
            return "person.crop.circle.badge.checkmark"
        case .check:
            return "checkmark.square"
        case .ordinal:
            return "list.number"
        default:
            return "tablecells"
        }
    }
}

struct NotebookNumericCellKeyboard: View {
    @Binding var value: String
    let tint: Color
    let onSave: () -> Void
    let onNavigate: (NotebookNavigationDirection) -> Void

    private let rows = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        [",", "0", "delete.left"]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.quaternary.opacity(0.24))
                    )

                Button("5") {
                    value = "5"
                    onSave()
                }
                .buttonStyle(.bordered)

                Button("10") {
                    value = "10"
                    onSave()
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                press(key)
                            } label: {
                                if key == "delete.left" {
                                    Image(systemName: key)
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                } else {
                                    Text(key)
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Limpiar") {
                    value = ""
                    onSave()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button {
                    onNavigate(.up)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    onNavigate(.down)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)

                Button("Guardar") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func press(_ key: String) {
        if key == "delete.left" {
            if !value.isEmpty {
                value.removeLast()
            }
            onSave()
            return
        }

        if key == "," {
            guard !value.contains(",") && !value.contains(".") else { return }
            value = value.isEmpty ? "0," : value + ","
            onSave()
            return
        }

        if value == "0" {
            value = key
        } else {
            value += key
        }
        onSave()
    }
}

enum NotebookFormulaAIError: LocalizedError {
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .emptyResponse:
            return "No se pudo generar una fórmula válida."
        }
    }
}

final class AppleFoundationFormulaService {
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private var formulaSession: LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Eres un asistente local para crear y corregir fórmulas de un cuaderno docente.
            Devuelve SOLO una fórmula, sin explicación, sin markdown y sin comillas.
            Usa referencias de columna exactamente con el formato [columnId].
            Funciones permitidas: SUMA, PROMEDIO, MIN, MAX, REDONDEAR, SI.
            Operadores permitidos: +, -, *, /, paréntesis y comparaciones.
            Si corriges una fórmula, conserva la intención docente.
            """
        )
    }
    #endif

    func generateFormula(
        request: String,
        currentFormula: String,
        availableColumns: [NotebookColumnDefinition]
    ) async throws -> String {
        if let deterministic = deterministicFormula(for: request, availableColumns: availableColumns) {
            return deterministic
        }

        let availability = AppleFoundationModelSupport.resolveAvailability(isEnabled: true)
        guard availability == .available else {
            throw NotebookFormulaAIError.unavailable(message(for: availability))
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let response = try await formulaSession.respond(
                to: prompt(request: request, currentFormula: currentFormula, availableColumns: availableColumns),
                generating: String.self,
                includeSchemaInPrompt: false,
                options: AppleFoundationModelSupport.generationOptions(temperature: 0.0)
            )
            let formula = sanitize(response.content)
            guard !formula.isEmpty else { throw NotebookFormulaAIError.emptyResponse }
            return formula
        }
        #endif

        throw NotebookFormulaAIError.unavailable("La generación de fórmulas requiere Apple Foundation Models en una versión compatible del sistema.")
    }

    private func prompt(
        request: String,
        currentFormula: String,
        availableColumns: [NotebookColumnDefinition]
    ) -> String {
        let columns = availableColumns.enumerated().map { index, column in
            "- Columna \(index + 1). Título: \"\(column.title)\". Referencia obligatoria: [\(column.id)]. Tipo: \(column.type)"
        }.joined(separator: "\n")

        return """
        Tarea: convierte una petición docente en UNA fórmula válida para el cuaderno.

        Petición literal del profesor:
        \(request)

        Fórmula actual:
        \(currentFormula.isEmpty ? "Sin fórmula" : currentFormula)

        Columnas disponibles:
        \(columns)

        Reglas:
        - Devuelve únicamente la fórmula final.
        - Usa solo las columnas disponibles.
        - Las referencias deben copiarse EXACTAMENTE como aparecen, por ejemplo [eval_71].
        - Si pide media/promedio simple de dos columnas: REDONDEAR(PROMEDIO([columna1],[columna2]),2)
        - Si pide media ponderada: usa (valor*peso + valor*peso) / sumaPesos.
        - Si dice que una columna pesa el doble que otra, usa peso 2 para esa columna y peso 1 para la otra.
        - Si dice "la segunda/el segundo/la nota tiene el doble de peso que la primera": REDONDEAR((([primera]*1)+([segunda]*2))/3,2)
        - NO uses SUMA para una media salvo que dividas por la suma de pesos.
        - No expliques nada.
        """
    }

    private func deterministicFormula(
        for request: String,
        availableColumns: [NotebookColumnDefinition]
    ) -> String? {
        let normalized = normalize(request)
        guard normalized.contains("media")
            || normalized.contains("promedio")
            || normalized.contains("ponderad")
            || normalized.contains("peso")
            || normalized.contains("pesa")
            || normalized.contains("doble")
            || normalized.contains("triple") else {
            return nil
        }

        var selected: [NotebookColumnDefinition] = []

        func append(_ column: NotebookColumnDefinition?) {
            guard let column, !selected.contains(where: { $0.id == column.id }) else { return }
            selected.append(column)
        }

        if normalized.contains("primera columna")
            || normalized.contains("primer columna")
            || normalized.contains("primera")
            || normalized.contains("primer") {
            append(availableColumns.first)
        }

        if normalized.contains("segunda columna")
            || normalized.contains("segundo columna")
            || normalized.contains("segunda")
            || normalized.contains("segundo") {
            append(availableColumns.dropFirst().first)
        }

        for column in availableColumns {
            let title = normalize(column.title)
            guard !title.isEmpty else { continue }
            if normalized.contains(title) {
                append(column)
            }
        }

        if selected.count < 2,
           normalized.contains("dos columnas") || normalized.contains("2 columnas") || normalized.contains("ambas") {
            append(availableColumns.first)
            append(availableColumns.dropFirst().first)
        }

        if selected.count < 2, availableColumns.count == 2 {
            append(availableColumns.first)
            append(availableColumns.dropFirst().first)
        }

        guard selected.count >= 2 else { return nil }

        var weights = Array(repeating: 1.0, count: selected.count)
        if normalized.contains("doble") {
            if let weightedIndex = weightedColumnIndex(in: normalized, selected: selected, keyword: "doble") {
                weights[weightedIndex] = 2
            } else if selected.count >= 2 {
                weights[1] = 2
            }
        } else if normalized.contains("triple") {
            if let weightedIndex = weightedColumnIndex(in: normalized, selected: selected, keyword: "triple") {
                weights[weightedIndex] = 3
            } else if selected.count >= 2 {
                weights[1] = 3
            }
        }

        return weightedAverageFormula(columns: selected, weights: weights)
    }

    private func weightedColumnIndex(
        in normalizedRequest: String,
        selected: [NotebookColumnDefinition],
        keyword: String
    ) -> Int? {
        if normalizedRequest.contains("primera") || normalizedRequest.contains("primer") {
            let beforeKeyword = normalizedRequest.components(separatedBy: keyword).first ?? ""
            if beforeKeyword.contains("primera") || beforeKeyword.contains("primer") {
                return 0
            }
        }
        if normalizedRequest.contains("segunda") || normalizedRequest.contains("segundo") {
            let beforeKeyword = normalizedRequest.components(separatedBy: keyword).first ?? ""
            if beforeKeyword.contains("segunda") || beforeKeyword.contains("segundo") {
                return min(1, selected.count - 1)
            }
        }
        let beforeKeyword = normalizedRequest.components(separatedBy: keyword).first ?? normalizedRequest
        for (index, column) in selected.enumerated().reversed() {
            if beforeKeyword.contains(normalize(column.title)) {
                return index
            }
        }
        return nil
    }

    private func weightedAverageFormula(columns: [NotebookColumnDefinition], weights: [Double]) -> String {
        if weights.allSatisfy({ $0 == 1 }) {
            let references = columns.map { "[\($0.id)]" }.joined(separator: ",")
            return "REDONDEAR(PROMEDIO(\(references)),2)"
        }
        let weightedTerms = zip(columns, weights).map { column, weight in
            let weightText = cleanWeight(weight)
            return "([\(column.id)]*\(weightText))"
        }
        let totalWeight = weights.reduce(0, +)
        let totalWeightText = cleanWeight(totalWeight)
        return "REDONDEAR((\(weightedTerms.joined(separator: "+")))/\(totalWeightText),2)"
    }

    private func cleanWeight(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "swift", with: "")
            .replacingOccurrences(of: "Fórmula:", with: "")
            .replacingOccurrences(of: "Formula:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func message(for availability: AppleFoundationModelAvailability) -> String {
        switch availability {
        case .disabled:
            return "La ayuda con IA local está desactivada."
        case .frameworkUnavailable:
            return "Apple Foundation Models no está disponible en este target."
        case .unsupportedOS:
            return "La ayuda con fórmulas requiere una versión compatible de macOS/iOS."
        case .unsupportedDevice:
            return "Este dispositivo no es compatible con Apple Intelligence local."
        case .notEnabled:
            return "Activa Apple Intelligence para generar fórmulas con lenguaje natural."
        case .modelLoading:
            return "El modelo local todavía se está preparando. Inténtalo de nuevo en unos segundos."
        case .available:
            return "Disponible."
        case .unavailable(let message):
            return message
        }
    }
}
