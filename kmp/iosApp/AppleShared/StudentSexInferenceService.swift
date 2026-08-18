import Foundation
import SwiftUI
import MiGestorKit

enum StudentSexInferenceConfidence: String, Equatable {
    case high = "Confianza alta"
    case review = "Revisar"
    case unavailable = "Sin propuesta"
}

struct StudentSexInferenceNameResult {
    let sex: StudentSex?
    let confidence: StudentSexInferenceConfidence
    let reason: String
}

/// Conservative, local name heuristic. It is intentionally a suggestion engine,
/// not a claim about a student's identity: ambiguous names remain untouched.
enum StudentSexNameInference {
    static func infer(firstName: String) -> StudentSexInferenceNameResult {
        let tokens = normalizedTokens(firstName)
        guard !tokens.isEmpty else {
            return StudentSexInferenceNameResult(
                sex: nil,
                confidence: .unavailable,
                reason: "No hay un nombre utilizable."
            )
        }

        if tokens.contains(where: ambiguousNames.contains) {
            return StudentSexInferenceNameResult(
                sex: nil,
                confidence: .review,
                reason: "El nombre puede corresponder a más de un sexo."
            )
        }

        let maleMatches = tokens.filter(maleNames.contains)
        let femaleMatches = tokens.filter(femaleNames.contains)
        if !maleMatches.isEmpty && !femaleMatches.isEmpty {
            return StudentSexInferenceNameResult(
                sex: nil,
                confidence: .review,
                reason: "El nombre compuesto contiene señales contradictorias."
            )
        }

        if !maleMatches.isEmpty {
            return StudentSexInferenceNameResult(
                sex: .male,
                confidence: .high,
                reason: "Coincide con un nombre tradicionalmente masculino."
            )
        }

        if !femaleMatches.isEmpty {
            return StudentSexInferenceNameResult(
                sex: .female,
                confidence: .high,
                reason: "Coincide con un nombre tradicionalmente femenino."
            )
        }

        return StudentSexInferenceNameResult(
            sex: nil,
            confidence: .unavailable,
            reason: "No hay una coincidencia suficientemente fiable."
        )
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static let ambiguousNames: Set<String> = [
        "alex", "alexis", "cameron", "cruz", "francis", "noel", "sam"
    ]

    private static let maleNames: Set<String> = [
        "adrian", "alejandro", "alberto", "alvaro", "andres", "angel", "antonio",
        "bruno", "carlos", "daniel", "david", "diego", "emilio", "enrique",
        "ernesto", "fernando", "francisco", "gabriel", "gonzalo", "guillermo",
        "hugo", "ignacio", "ivan", "jaime", "javier", "jesus", "joaquin", "jorge",
        "jose", "juan", "leonardo", "luis", "manuel", "marcos", "mario", "martin",
        "mateo", "miguel", "nicolas", "oscar", "pablo", "pedro", "rafael", "raul",
        "roberto", "rodrigo", "ruben", "samuel", "santiago", "sergio", "victor"
    ]

    private static let femaleNames: Set<String> = [
        "aina", "ainhoa", "alba", "alejandra", "alicia", "ana", "angela", "beatriz",
        "blanca", "carla", "carmen", "carolina", "celia", "clara", "claudia",
        "cristina", "daniela", "elena", "elisa", "emma", "esther", "eva", "gabriela",
        "ines", "irene", "isabel", "julia", "laura", "leticia", "lucia", "manuela",
        "maria", "marta", "martina", "monica", "natalia", "noelia", "nuria", "olga",
        "patricia", "paula", "raquel", "rebeca", "rocio", "sara", "silvia", "sofia",
        "teresa", "valentina", "valeria", "vanesa", "veronica", "victoria"
    ]
}

struct StudentSexInferenceSuggestion: Identifiable {
    let student: Student
    let suggestedSex: StudentSex?
    let confidence: StudentSexInferenceConfidence
    let reason: String

    var id: Int64 { student.id }

    var isEligible: Bool {
        student.sex == .unspecified && student.sexSource == .unknown
    }

    var isApplicable: Bool {
        isEligible && suggestedSex != nil
    }
}

struct StudentSexInferenceAssignment {
    let student: Student
    let sex: StudentSex
}

enum StudentSexInferenceService {
    static func suggestions(for students: [Student]) -> [StudentSexInferenceSuggestion] {
        students
            .map { student in
                let result = StudentSexNameInference.infer(firstName: student.firstName)
                return StudentSexInferenceSuggestion(
                    student: student,
                    suggestedSex: result.sex,
                    confidence: result.confidence,
                    reason: result.reason
                )
            }
            .sorted { lhs, rhs in
                lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
            }
    }
}

struct StudentSexInferenceSheet: View {
    let students: [Student]
    let onApply: ([StudentSexInferenceAssignment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<Int64>
    private let suggestions: [StudentSexInferenceSuggestion]

    init(students: [Student], onApply: @escaping ([StudentSexInferenceAssignment]) -> Void) {
        self.students = students
        self.onApply = onApply
        let suggestions = StudentSexInferenceService.suggestions(for: students)
        self.suggestions = suggestions
        _selectedIds = State(initialValue: Set(
            suggestions
                .filter { $0.isApplicable && $0.confidence == .high }
                .map(\.id)
        ))
    }

    private var highConfidence: [StudentSexInferenceSuggestion] {
        suggestions.filter { $0.isApplicable && $0.confidence == .high }
    }

    private var reviewSuggestions: [StudentSexInferenceSuggestion] {
        suggestions.filter { $0.isEligible && $0.confidence == .review }
    }

    private var withoutProposal: [StudentSexInferenceSuggestion] {
        suggestions.filter { $0.isEligible && $0.confidence == .unavailable }
    }

    private var protectedCount: Int {
        suggestions.filter { !$0.isEligible }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("La app propone una asignación local basada únicamente en el nombre. Revisa las sugerencias antes de aplicarlas.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("No se modifican valores manuales, importados o ya inferidos.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Label("Confianza alta", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("\(highConfidence.count)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if highConfidence.isEmpty {
                        Text("No hay coincidencias listas para aplicar.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(selectedIds.count == highConfidence.count ? "Deseleccionar todas" : "Seleccionar todas") {
                            if selectedIds.count == highConfidence.count {
                                selectedIds.removeAll()
                            } else {
                                selectedIds = Set(highConfidence.map(\.id))
                            }
                        }
                        .font(.subheadline.weight(.semibold))

                        ForEach(highConfidence) { suggestion in
                            Toggle(isOn: selectionBinding(for: suggestion.id)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.student.fullName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(sexLabel(suggestion.suggestedSex)) · \(suggestion.reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Aplicar automáticamente")
                }

                Section {
                    if reviewSuggestions.isEmpty {
                        Text("No hay nombres ambiguos en este grupo.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reviewSuggestions) { suggestion in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.student.fullName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(suggestion.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Revisión manual")
                } footer: {
                    Text("Los nombres ambiguos no se asignan automáticamente.")
                }

                Section {
                    if withoutProposal.isEmpty {
                        Text("Todos los nombres aptos tienen una propuesta.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(withoutProposal) { suggestion in
                            Label(suggestion.student.fullName, systemImage: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sin propuesta")
                } footer: {
                    Text("\(withoutProposal.count) sin coincidencia fiable · \(protectedCount) protegidos por tener un valor previo.")
                }
            }
            .navigationTitle("Sugerir sexo por nombre")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar \(selectedIds.count)") {
                        let assignments = highConfidence
                            .filter { selectedIds.contains($0.id) }
                            .compactMap { suggestion -> StudentSexInferenceAssignment? in
                                guard let sex = suggestion.suggestedSex else { return nil }
                                return StudentSexInferenceAssignment(student: suggestion.student, sex: sex)
                            }
                        onApply(assignments)
                        dismiss()
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 620)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func selectionBinding(for id: Int64) -> Binding<Bool> {
        Binding(
            get: { selectedIds.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedIds.insert(id)
                } else {
                    selectedIds.remove(id)
                }
            }
        )
    }

    private func sexLabel(_ sex: StudentSex?) -> String {
        switch sex {
        case .male: return "Hombre"
        case .female: return "Mujer"
        default: return "Sin asignar"
        }
    }
}
