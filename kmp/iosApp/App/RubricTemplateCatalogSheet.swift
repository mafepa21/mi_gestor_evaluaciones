import SwiftUI
import MiGestorKit

/// Hoja modal para explorar, previsualizar e importar plantillas oficiales de rúbricas LOMLOE / EF.
struct RubricTemplateCatalogSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let targetClassId: Int64?
    var onTemplateImported: ((Int64) -> Void)? = nil

    @State private var selectedCategory: RubricTemplateCategory = .all
    @State private var searchText: String = ""
    @State private var previewTemplate: RubricTemplateItem? = nil
    @State private var isImporting: Bool = false
    @State private var errorMessage: String? = nil

    private var filteredTemplates: [RubricTemplateItem] {
        RubricTemplateCatalog.templates.filter { item in
            let matchesCategory = selectedCategory == .all || item.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesQuery = query.isEmpty || [
                item.title,
                item.description,
                item.subject,
                item.stage,
                item.criteria.map(\.name).joined(separator: " ")
            ].joined(separator: " ").lowercased().contains(query)
            return matchesCategory && matchesQuery
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Barra de Búsqueda y Filtros
                headerFiltersView

                Divider()

                if filteredTemplates.isEmpty {
                    ContentUnavailableView(
                        "No se encontraron plantillas",
                        systemImage: "magnifyingglass",
                        description: Text("Prueba a seleccionar otra categoría o cambiar los términos de búsqueda.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(filteredTemplates) { template in
                                RubricTemplateCard(
                                    template: template,
                                    onPreview: {
                                        previewTemplate = template
                                    },
                                    onImport: {
                                        importTemplate(template)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(appPageBackground(for: colorScheme))
            .navigationTitle("Catálogo Oficial de Rúbricas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $previewTemplate) { template in
                RubricTemplatePreviewModal(
                    template: template,
                    isImporting: isImporting,
                    onImport: {
                        importTemplate(template)
                    }
                )
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Importando plantilla...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 560)
        #endif
    }

    private var headerFiltersView: some View {
        VStack(spacing: 12) {
            // Buscador
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar por título, criterio o etapa...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Categorías con scroll horizontal
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RubricTemplateCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.systemImage)
                                Text(category.rawValue)
                            }
                            .font(.caption.weight(selectedCategory == category ? .bold : .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedCategory == category
                                    ? Color.accentColor
                                    : appCardBackground(for: colorScheme),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedCategory == category
                                    ? contrastingTextColor(for: Color.accentColor)
                                    : .primary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(appPageBackground(for: colorScheme))
    }

    private func importTemplate(_ template: RubricTemplateItem) {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let rubricId = try await RubricTemplateCatalog.importTemplate(
                    template,
                    into: bridge,
                    targetClassId: targetClassId
                )
                AppleInteractionFeedback.play(.success)
                isImporting = false
                previewTemplate = nil
                onTemplateImported?(rubricId)
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
                AppleInteractionFeedback.play(.error)
            }
        }
    }
}

/// Tarjeta de plantilla en el catálogo.
private struct RubricTemplateCard: View {
    let template: RubricTemplateItem
    let onPreview: () -> Void
    let onImport: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.category.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EvaluationDesign.accent)
                        Text(template.category.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EvaluationDesign.accent)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(template.stage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()

                Text("\(template.criteria.count) criterios")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            Text(template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Resumen de criterios
            HStack(spacing: 6) {
                ForEach(template.criteria.prefix(3)) { c in
                    Text("• \(c.name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if template.criteria.count > 3 {
                    Text("+\(template.criteria.count - 3) más")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Button(action: onPreview) {
                    Label("Ver niveles y matriz", systemImage: "eye")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: onImport) {
                    Label("Usar esta plantilla", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(contrastingTextColor(for: Color.accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

/// Modal de previsualización detallada de una plantilla oficial antes de importar.
private struct RubricTemplatePreviewModal: View {
    let template: RubricTemplateItem
    let isImporting: Bool
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Cabecera
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Label(template.category.rawValue, systemImage: template.category.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.accent)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(template.stage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(template.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(template.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Divider()

                    // Desglose de Criterios y Niveles LOMLOE
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Matriz Curricular de Criterios y Niveles (1 a 4)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)

                        ForEach(Array(template.criteria.enumerated()), id: \.element.id) { index, criterion in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Criterio \(index + 1): \(criterion.name)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                    Spacer()
                                    Text("Peso: \(String(format: "%.1f", criterion.weight))")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                VStack(spacing: 8) {
                                    ForEach(criterion.levels) { level in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(level.name)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(levelColor(for: level.order))
                                                .frame(width: 110, alignment: .leading)

                                            Text(level.description)
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(8)
                                        .background(levelColor(for: level.order).opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                            .padding(14)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .background(appPageBackground(for: colorScheme))
            .navigationTitle("Detalle de Plantilla")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onImport()
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("Usar esta plantilla")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isImporting)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 600)
        #endif
    }

    private func levelColor(for order: Int) -> Color {
        switch order {
        case 1:
            return EvaluationDesign.danger
        case 2:
            return Color.orange
        case 3:
            return Color.blue
        case 4:
            return EvaluationDesign.success
        default:
            return Color.accentColor
        }
    }
}
