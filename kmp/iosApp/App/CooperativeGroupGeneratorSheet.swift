import SwiftUI
import MiGestorKit

/// Hoja interactiva para generar agrupamientos cooperativos inteligentes on-device.
struct CooperativeGroupGeneratorSheet: View {
    @ObservedObject var bridge: KmpBridge
    let onApply: ([ImportedNotebookGroup]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var strategy: CooperativeGroupingStrategy = .heterogeneous
    @State private var groupCount: Int = 4
    @State private var balanceGender: Bool = false
    @State private var groupPrefix: String = "Equipo"
    @State private var generatedResult: CooperativeGroupingResult? = nil
    @State private var copiedToClipboard: Bool = false

    private var data: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var candidates: [CooperativeCandidateStudent] {
        guard let data = data else { return [] }
        return data.sheet.rows.map { row in
            let student = row.student
            let avg = row.weightedAverage?.doubleValue
            let gender = student.sex == .male ? "M" : (student.sex == .female ? "F" : nil)
            return CooperativeCandidateStudent(
                id: student.id,
                name: "\(student.lastName), \(student.firstName)".trimmingCharacters(in: .whitespacesAndNewlines),
                average: avg,
                gender: gender
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    // Ancho (macOS / iPad): parámetros a la izquierda, equipos a la derecha.
                    HStack(alignment: .top, spacing: 24) {
                        parametersCard
                            .frame(width: 320)
                        resultsColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minWidth: 640)

                    // Estrecho (iPhone / ventana pequeña): una sola columna.
                    VStack(alignment: .leading, spacing: 24) {
                        parametersCard
                        resultsColumn
                    }
                }
                .padding(24)
            }
            .navigationTitle("Generador de equipos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                if let result = generatedResult, !result.groups.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Aplicar al Cuaderno") {
                            let imported = CooperativeGroupGeneratorService().toImportedNotebookGroups(result: result)
                            onApply(imported)
                            dismiss()
                        }
                        .groupGlassButton(prominent: true)
                    }
                }
            }
            .onAppear {
                if generatedResult == nil && !candidates.isEmpty {
                    generate()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 800, minHeight: 560)
        #endif
    }

    // MARK: - Componentes de Vista

    private var parametersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(candidates.count) alumnos", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(NotebookStyle.primaryTint)
                Text("Equipos equilibrados calculados en tu dispositivo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Estrategia", selection: $strategy) {
                ForEach(CooperativeGroupingStrategy.allCases) { strat in
                    Text(strat.shortTitle).tag(strat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .onChange(of: strategy) { _ in generate() }

            Text(strategy.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: $groupCount, in: 2...max(2, candidates.count / 2)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(groupCount) equipos")
                        .font(.body.weight(.semibold))
                    if !candidates.isEmpty {
                        Text("Unos \(Int(ceil(Double(candidates.count) / Double(groupCount)))) por equipo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: groupCount) { _ in generate() }

            Toggle("Equilibrar género si consta", isOn: $balanceGender)
                .onChange(of: balanceGender) { _ in generate() }

            Button(action: generate) {
                Label("Regenerar", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .groupGlassButton()
            .disabled(candidates.isEmpty)
        }
        .padding(16)
        .groupSolidCard()
    }

    @ViewBuilder
    private var resultsColumn: some View {
        if let result = generatedResult {
            previewSection(result: result)
        } else {
            emptyPromptView
        }
    }

    private func previewSection(result: CooperativeGroupingResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("\(result.groups.count) equipos")
                    .font(.headline)

                Spacer()

                // Métrica de varianza entre grupos (icono + texto, no solo color)
                let variance = result.betweenGroupVariance
                Label(
                    variance < 0.6 ? "Equilibrio excelente" : "Equilibrio estándar",
                    systemImage: variance < 0.6 ? "checkmark.circle.fill" : "chart.bar.xaxis"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(variance < 0.6 ? Color.green : Color.orange)

                Button {
                    copyToClipboard(result: result)
                } label: {
                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        .frame(minWidth: 32, minHeight: 32)
                }
                .groupGlassButton(circular: true)
                .help("Copiar lista de equipos al portapapeles")
                .accessibilityLabel("Copiar lista de equipos")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                ForEach(result.groups) { group in
                    groupCard(group: group)
                }
            }
        }
    }

    private func groupCard(group: CooperativeGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name)
                    .font(.headline)
                Spacer()
                if let avg = group.averageScore {
                    Text("Media \(String(format: "%.1f", avg))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }
            }

            if let gender = group.genderSummary {
                Text("Género: \(gender)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.members) { member in
                    HStack(spacing: 8) {
                        Text(member.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if let avg = member.average {
                            Text(String(format: "%.1f", avg))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .groupSolidCard()
        .accessibilityElement(children: .combine)
    }

    private var emptyPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(candidates.isEmpty
                 ? "No hay alumnado en esta clase. Añade alumnos para generar equipos."
                 : "Pulsa «Regenerar» para crear equipos cooperativos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Lógica

    private func generate() {
        let config = CooperativeGroupingConfiguration(
            strategy: strategy,
            targetGroupCount: groupCount,
            balanceGender: balanceGender,
            groupNamePrefix: groupPrefix
        )
        let service = CooperativeGroupGeneratorService()
        self.generatedResult = service.generateGroups(students: candidates, configuration: config)
        self.copiedToClipboard = false
    }

    private func copyToClipboard(result: CooperativeGroupingResult) {
        var text = "Equipos Cooperativos - \(result.strategy.title)\n\n"
        for group in result.groups {
            let avgStr = group.averageScore.map { " (Media: \(String(format: "%.1f", $0)))" } ?? ""
            text += "\(group.name)\(avgStr):\n"
            for member in group.members {
                let mAvg = member.average.map { " - \(String(format: "%.1f", $0))" } ?? ""
                text += "  • \(member.name)\(mAvg)\n"
            }
            text += "\n"
        }

        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        copiedToClipboard = true
    }
}

private extension CooperativeGroupingStrategy {
    /// Título corto para el selector segmentado (el largo va en la descripción).
    var shortTitle: String {
        switch self {
        case .heterogeneous: return "Heterogéneo"
        case .homogeneous: return "Homogéneo"
        case .balancedRandom: return "Azar"
        }
    }
}
