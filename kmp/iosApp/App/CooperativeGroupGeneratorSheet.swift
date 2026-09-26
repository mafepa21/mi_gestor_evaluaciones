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
                VStack(alignment: .leading, spacing: 18) {
                    headerView

                    parametersSection

                    if let result = generatedResult {
                        previewSection(result: result)
                    } else {
                        emptyPromptView
                    }
                }
                .padding(20)
            }
            .navigationTitle("Generador de Equipos")
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
                        .buttonStyle(.borderedProminent)
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
        .frame(minWidth: 540, minHeight: 520)
        #endif
    }

    // MARK: - Componentes de Vista

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NotebookStyle.primaryTint)
                Text("Agrupamiento Cooperativo On-Device")
                    .font(.title3.weight(.bold))
            }
            Text("Distribuye a los \(candidates.count) alumnos de la clase en equipos equilibrados mediante algoritmos pedagógicos multidimensionales.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Criterio y Parámetros")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Selector de estrategia
            Picker("Estrategia", selection: $strategy) {
                ForEach(CooperativeGroupingStrategy.allCases) { strat in
                    Label(strat.title, systemImage: strat.systemImage).tag(strat)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: strategy) { _ in generate() }

            Text(strategy.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 16) {
                // Selector de número de grupos
                Stepper(value: $groupCount, in: 2...max(2, candidates.count / 2)) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3")
                            .foregroundStyle(.secondary)
                        Text("\(groupCount) equipos")
                            .font(.subheadline.weight(.medium))
                        if !candidates.isEmpty {
                            Text("(~\(Int(ceil(Double(candidates.count) / Double(groupCount)))) por grupo)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: groupCount) { _ in generate() }

                Spacer()

                // Botón regenerar
                Button(action: generate) {
                    Label("Regenerar", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
            }

            Toggle("Equilibrar género en los equipos si consta", isOn: $balanceGender)
                .font(.subheadline)
                .onChange(of: balanceGender) { _ in generate() }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func previewSection(result: CooperativeGroupingResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Equipos Generados (\(result.groups.count))")
                    .font(.subheadline.weight(.bold))

                Spacer()

                // Métrica de varianza entre grupos
                let variance = result.betweenGroupVariance
                HStack(spacing: 4) {
                    Image(systemName: variance < 0.6 ? "checkmark.circle.fill" : "chart.bar.xaxis")
                        .font(.caption2)
                    Text(variance < 0.6 ? "Equilibrio excelente" : "Equilibrio estándar")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(variance < 0.6 ? Color.green : Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    (variance < 0.6 ? Color.green : Color.orange).opacity(0.12),
                    in: Capsule()
                )

                // Botón copiar
                Button {
                    copyToClipboard(result: result)
                } label: {
                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copiar lista de equipos al portapapeles")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
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
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let avg = group.averageScore {
                    Text("Media: \(String(format: "%.1f", avg))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }
            }

            if let gender = group.genderSummary {
                Text("Género: \(gender)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.members) { member in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(NotebookStyle.primaryTint.opacity(0.8))
                            .frame(width: 5, height: 5)
                        Text(member.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let avg = member.average {
                            Text(String(format: "%.1f", avg))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            Color.secondary.opacity(0.04)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                )
        )
        .cornerRadius(10)
    }

    private var emptyPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Pulsa 'Generar' para crear equipos cooperativos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
