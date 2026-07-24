import SwiftUI

/// Banco cerrado de estrategias didácticas basadas en evidencia. Las claves son
/// estables: se guardan en `planner_week_plan.strategies` y no deben cambiar
/// aunque cambie la etiqueta. El icono es SF Symbols.
enum TeachingStrategy: String, CaseIterable, Identifiable {
    case retrievalPractice = "retrieval_practice"
    case spacedPractice = "spaced_practice"
    case interleaving = "interleaving"
    case dualCoding = "dual_coding"
    case workedExamples = "worked_examples"
    case concreteExamples = "concrete_examples"
    case elaboration = "elaboration"
    case metacognition = "metacognition"
    case feedback = "feedback"
    case scaffolding = "scaffolding"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .retrievalPractice: return "Práctica de recuperación"
        case .spacedPractice: return "Práctica espaciada"
        case .interleaving: return "Intercalado"
        case .dualCoding: return "Codificación dual"
        case .workedExamples: return "Ejemplos resueltos"
        case .concreteExamples: return "Ejemplos múltiples y concretos"
        case .elaboration: return "Interrogación elaborativa"
        case .metacognition: return "Metacognición y autorregulación"
        case .feedback: return "Feedback formativo"
        case .scaffolding: return "Andamiaje"
        }
    }

    var caption: String {
        switch self {
        case .retrievalPractice: return "Evocar lo aprendido sin mirar (evocación)."
        case .spacedPractice: return "Distribuir el repaso en el tiempo."
        case .interleaving: return "Alternar tipos de problema o contenido."
        case .dualCoding: return "Combinar palabra e imagen."
        case .workedExamples: return "Modelar la resolución paso a paso."
        case .concreteExamples: return "Varios ejemplos concretos del concepto."
        case .elaboration: return "Preguntar el porqué y el cómo."
        case .metacognition: return "Que el alumno planifique y revise su aprendizaje."
        case .feedback: return "Devolución que orienta la mejora."
        case .scaffolding: return "Apoyos que se retiran de forma gradual."
        }
    }

    var systemImage: String {
        switch self {
        case .retrievalPractice: return "brain.head.profile"
        case .spacedPractice: return "calendar.badge.clock"
        case .interleaving: return "shuffle"
        case .dualCoding: return "photo.on.rectangle.angled"
        case .workedExamples: return "list.number"
        case .concreteExamples: return "square.stack.3d.up"
        case .elaboration: return "questionmark.bubble"
        case .metacognition: return "arrow.triangle.2.circlepath"
        case .feedback: return "bubble.left.and.bubble.right"
        case .scaffolding: return "stairs"
        }
    }
}

/// Banco cerrado de instrumentos de evaluación. Mismas reglas de clave estable.
enum EvaluationInstrument: String, CaseIterable, Identifiable {
    case rubric = "rubric"
    case checklist = "checklist"
    case observation = "observation"
    case exitTicket = "exit_ticket"
    case quiz = "quiz"
    case portfolio = "portfolio"
    case oral = "oral"
    case project = "project"
    case selfAssessment = "self_assessment"
    case peerAssessment = "peer_assessment"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rubric: return "Rúbrica"
        case .checklist: return "Lista de cotejo"
        case .observation: return "Observación en aula"
        case .exitTicket: return "Ticket de salida"
        case .quiz: return "Cuestionario o control"
        case .portfolio: return "Portafolio"
        case .oral: return "Prueba oral o exposición"
        case .project: return "Proyecto o producto"
        case .selfAssessment: return "Autoevaluación"
        case .peerAssessment: return "Coevaluación"
        }
    }

    var systemImage: String {
        switch self {
        case .rubric: return "tablecells"
        case .checklist: return "checklist"
        case .observation: return "eye"
        case .exitTicket: return "ticket"
        case .quiz: return "doc.questionmark"
        case .portfolio: return "folder"
        case .oral: return "mic"
        case .project: return "hammer"
        case .selfAssessment: return "person.crop.circle.badge.checkmark"
        case .peerAssessment: return "person.2.badge.gearshape"
        }
    }
}

/// Estado del plan pedagógico de una semana, ya resuelto contra los bancos.
struct WeekPlanRow {
    /// `nil` si aún no hay fila persistida para esta (clase, año, semana).
    let id: Int64?
    let classId: Int64
    let year: Int
    let week: Int
    var strategies: Set<TeachingStrategy>
    var instruments: Set<EvaluationInstrument>
    var notes: String

    var isEmpty: Bool {
        strategies.isEmpty && instruments.isEmpty && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedCount: Int { strategies.count + instruments.count }
}

extension KmpBridge.WeekPlanSnapshot {
    var asRow: WeekPlanRow {
        WeekPlanRow(
            id: id,
            classId: classId,
            year: year,
            week: week,
            strategies: Set(strategyKeys.compactMap(TeachingStrategy.init(rawValue:))),
            instruments: Set(instrumentKeys.compactMap(EvaluationInstrument.init(rawValue:))),
            notes: notes
        )
    }
}

/// Colocación en flujo (chips que hacen wrap). `Layout` existe en iOS 16 / macOS 13,
/// que son los mínimos del proyecto.
struct PlannerFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Sección "Plan de la semana" para el detalle del Planner. Carga el plan de la
/// (clase, año, semana) activa, muestra un resumen de lo marcado y abre el editor.
/// Vale para iPad y macOS: el pane que la aloja es el mismo en ambas plataformas.
struct PlannerWeekPlanSection: View {
    let bridge: KmpBridge
    let classId: Int64
    let year: Int
    let week: Int

    @State private var plan: WeekPlanRow
    @State private var isLoading = true
    @State private var showEditor = false
    @State private var errorMessage: String?

    init(bridge: KmpBridge, classId: Int64, year: Int, week: Int) {
        self.bridge = bridge
        self.classId = classId
        self.year = year
        self.week = week
        _plan = State(initialValue: WeekPlanRow(
            id: nil, classId: classId, year: year, week: week,
            strategies: [], instruments: [], notes: ""
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Plan de la semana", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button {
                    showEditor = true
                } label: {
                    Label(plan.isEmpty ? "Elegir" : "Editar", systemImage: plan.isEmpty ? "plus.circle" : "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(EvaluationDesign.danger)
            }

            if isLoading {
                ProgressView().controlSize(.small)
            } else if plan.isEmpty {
                Text("Marca las estrategias didácticas y los instrumentos de evaluación previstos para esta semana.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !plan.strategies.isEmpty {
                    chipGroup(
                        title: "Estrategias",
                        chips: TeachingStrategy.allCases.filter { plan.strategies.contains($0) }
                            .map { ($0.displayName, $0.systemImage) }
                    )
                }
                if !plan.instruments.isEmpty {
                    chipGroup(
                        title: "Instrumentos",
                        chips: EvaluationInstrument.allCases.filter { plan.instruments.contains($0) }
                            .map { ($0.displayName, $0.systemImage) }
                    )
                }
                if !plan.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(plan.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .task(id: "\(classId)-\(year)-\(week)") { await load() }
        .sheet(isPresented: $showEditor) {
            PlannerWeekPlanEditorSheet(plan: plan) { updated in
                Task { await save(updated) }
            }
        }
    }

    private func chipGroup(title: String, chips: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            PlannerFlowLayout(spacing: 6) {
                ForEach(chips, id: \.0) { chip in
                    Label(chip.0, systemImage: chip.1)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let snapshot = try await bridge.weekPlan(classId: classId, year: year, week: week) {
                plan = snapshot.asRow
            } else {
                plan = WeekPlanRow(id: nil, classId: classId, year: year, week: week,
                                   strategies: [], instruments: [], notes: "")
            }
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo cargar el plan de la semana."
        }
    }

    private func save(_ updated: WeekPlanRow) async {
        do {
            let draft = KmpBridge.WeekPlanDraft(
                classId: classId,
                year: year,
                week: week,
                strategyKeys: updated.strategies.map { $0.rawValue },
                instrumentKeys: updated.instruments.map { $0.rawValue },
                notes: updated.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let savedId = try await bridge.saveWeekPlan(id: plan.id, draft: draft)
            var stored = updated
            stored = WeekPlanRow(id: savedId, classId: classId, year: year, week: week,
                                 strategies: updated.strategies, instruments: updated.instruments,
                                 notes: draft.notes)
            plan = stored
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo guardar el plan de la semana."
        }
    }
}

/// Editor del plan semanal: checklist completo de los dos bancos cerrados + nota.
struct PlannerWeekPlanEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var strategies: Set<TeachingStrategy>
    @State private var instruments: Set<EvaluationInstrument>
    @State private var notes: String
    let onSave: (WeekPlanRow) -> Void
    private let base: WeekPlanRow

    init(plan: WeekPlanRow, onSave: @escaping (WeekPlanRow) -> Void) {
        self.base = plan
        self.onSave = onSave
        _strategies = State(initialValue: plan.strategies)
        _instruments = State(initialValue: plan.instruments)
        _notes = State(initialValue: plan.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan de la semana")
                        .font(.title3.weight(.bold))
                    Text("Estrategias e instrumentos previstos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Guardar") {
                    onSave(WeekPlanRow(id: base.id, classId: base.classId, year: base.year, week: base.week,
                                       strategies: strategies, instruments: instruments, notes: notes))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    checklist(
                        title: "Estrategias didácticas",
                        items: TeachingStrategy.allCases,
                        isOn: { strategies.contains($0) },
                        toggle: { s in if strategies.contains(s) { strategies.remove(s) } else { strategies.insert(s) } },
                        name: { $0.displayName }, caption: { $0.caption }, icon: { $0.systemImage }
                    )
                    checklist(
                        title: "Instrumentos de evaluación",
                        items: EvaluationInstrument.allCases,
                        isOn: { instruments.contains($0) },
                        toggle: { i in if instruments.contains(i) { instruments.remove(i) } else { instruments.insert(i) } },
                        name: { $0.displayName }, caption: { _ in nil }, icon: { $0.systemImage }
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nota de la semana")
                            .font(.headline)
                        TextEditor(text: $notes)
                            .frame(minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    private func checklist<Item: Identifiable & Hashable>(
        title: String,
        items: [Item],
        isOn: @escaping (Item) -> Bool,
        toggle: @escaping (Item) -> Void,
        name: @escaping (Item) -> String,
        caption: @escaping (Item) -> String?,
        icon: @escaping (Item) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(items) { item in
                Button {
                    toggle(item)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isOn(item) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn(item) ? Color.accentColor : Color.secondary)
                        Image(systemName: icon(item))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(item))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            if let cap = caption(item) {
                                Text(cap)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOn(item) ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
