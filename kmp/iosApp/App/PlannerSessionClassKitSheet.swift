import SwiftUI

/// Hoja «Kit de clase»: la sesión preparada para darla en el aula.
/// Las tareas se ven desde el principio y el apoyo de IA va llegando tarea a tarea.
struct PlannerSessionClassKitSheet: View {
    @Environment(\.dismiss) private var dismiss

    let input: PlannerClassKitInput

    @State private var kit: PlannerClassKit
    @State private var phase: Phase = .generating(done: 0)
    @State private var pdfURL: URL?

    enum Phase: Equatable {
        case generating(done: Int)
        case ready
        /// Sin Apple Intelligence: tareas del plan y parte fija.
        case withoutAI
    }

    init(input: PlannerClassKitInput) {
        self.input = input
        _kit = State(initialValue: PlannerClassKit(input: input))
    }

    var body: some View {
        NavigationStack {
            Group {
                if input.tasks.isEmpty {
                    ContentUnavailableView(
                        "Esta sesión no tiene guion",
                        systemImage: "list.bullet.rectangle",
                        description: Text("El kit se prepara a partir de las tareas del plan. Importa o escribe el guion de la sesión y vuelve a abrirlo.")
                    )
                } else {
                    ScrollView {
                        content
                            .frame(maxWidth: 820, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Kit de clase")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 860, minHeight: 600, idealHeight: 900)
        #endif
        .task { await generate() }
    }

    // MARK: Contenido

    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
            statusLine
            if let header = kit.header {
                boardSection(header)
            }
            if !input.setup.isEmpty {
                section("Montaje (5 minutos antes)") {
                    bulletList(input.setup)
                }
            }
            ForEach(Array(kit.tasks.enumerated()), id: \.element.id) { index, task in
                taskSection(task, number: index + 1)
            }
            if let header = kit.header, !header.closingQuestion.isEmpty {
                section("Cierre por parejas") {
                    labelled("Pregunta", header.closingQuestion, english: true)
                    if !header.closingSentence.isEmpty {
                        labelled("Frase para completar", header.closingSentence, english: true)
                    }
                }
            }
            if !kit.cards.isEmpty {
                section("Tarjetas para imprimir · \(kit.cards.count)") {
                    Text("Van en el PDF, una por página. Plastificadas sirven todo el curso.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            fixedSections
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(input.title)
                .font(.title2.weight(.bold))
            if !input.meta.isEmpty {
                Text(input.meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !input.objective.isEmpty {
                Text(input.objective)
                    .font(.body)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .generating(let done):
            HStack(spacing: 12) {
                ProgressView()
                Text("Preparando el apoyo de clase · \(done) de \(input.tasks.count + 1)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .withoutAI:
            Label(
                "Apple Intelligence no está disponible. El kit lleva las tareas del plan y la parte fija, sin guion en inglés ni tarjetas.",
                systemImage: "exclamationmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        case .ready:
            Label("Revisa las frases en inglés antes de clase.", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func boardSection(_ header: PlannerClassKitHeaderDraft) -> some View {
        section("En la pizarra") {
            if !header.boardWords.isEmpty {
                Text(header.boardWords.joined(separator: " · "))
                    .font(.title.weight(.black))
                    .textSelection(.enabled)
            }
            if !header.sessionCue.isEmpty {
                labelled(
                    "Corrección de la sesión",
                    header.cueGesture.isEmpty ? "“\(header.sessionCue)”" : "“\(header.sessionCue)” · \(header.cueGesture)",
                    english: false
                )
            }
        }
    }

    private func taskSection(_ task: PlannerClassKit.Task, number: Int) -> some View {
        let source = task.source
        let title = source.minutes.map { "\(source.title) · \($0) min" } ?? source.title
        return section("Tarea \(number) · \(title)") {
            if let coaching = task.coaching {
                if !coaching.show.isEmpty { labelled("Muestra", coaching.show, english: false) }
                if !coaching.say.isEmpty {
                    labelled("Di", coaching.say.map { "“\($0)”" }.joined(separator: "\n"), english: true)
                }
                if !coaching.rule.isEmpty {
                    labelled("Regla que corrige", coaching.rule.map { "• \($0)" }.joined(separator: "\n"), english: false)
                }
                if !coaching.checks.isEmpty {
                    labelled(
                        "Comprueba",
                        coaching.checks.map { $0.answer.isEmpty ? "“\($0.question)”" : "“\($0.question)” → \($0.answer)" }.joined(separator: "\n"),
                        english: true
                    )
                }
                if !coaching.cue.isEmpty { labelled("Corrección", "“\(coaching.cue)”", english: true) }
            } else if !source.detail.isEmpty {
                Text(source.detail)
                    .font(.body)
                    .textSelection(.enabled)
                    .redacted(reason: isPending(task) ? .placeholder : [])
            }
        }
    }

    private func isPending(_ task: PlannerClassKit.Task) -> Bool {
        if case .generating = phase { return task.coaching == nil }
        return false
    }

    private var fixedSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup("Cómo usar el kit") {
                bulletList(PlannerClassKitFixedContent.howToUse)
                    .padding(.top, 8)
            }
            DisclosureGroup("Banco de frases fijas") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(PlannerClassKitFixedContent.phraseBank, id: \.phrase) { phrase in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phrase.phrase).font(.body.weight(.semibold))
                            Text("\(phrase.gesture) · \(phrase.meaning)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .font(.headline)
    }

    // MARK: Piezas

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelled(_ label: String, _ text: String, english: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(english ? .body.weight(.medium) : .body)
                .textSelection(.enabled)
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.body)
            }
        }
    }

    // MARK: Generación

    private func generate() async {
        guard !input.tasks.isEmpty, pdfURL == nil else { return }
        let service = AppleFoundationClassKitService()
        guard service.isAvailable else {
            phase = .withoutAI
            pdfURL = PlannerClassKitPDFRenderer.writeToTemporaryFile(kit: kit)
            return
        }
        // En serie: el modelo del dispositivo atiende una petición cada vez.
        kit.header = await service.generateHeader(for: input)
        phase = .generating(done: 1)
        for index in kit.tasks.indices {
            if Task.isCancelled { return }
            kit.tasks[index].coaching = await service.generateCoaching(for: kit.tasks[index].source, in: input)
            phase = .generating(done: index + 2)
        }
        phase = kit.hasCoaching ? .ready : .withoutAI
        pdfURL = PlannerClassKitPDFRenderer.writeToTemporaryFile(kit: kit)
    }
}
