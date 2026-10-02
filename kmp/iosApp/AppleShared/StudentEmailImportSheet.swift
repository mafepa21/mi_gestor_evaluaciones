//
//  StudentEmailImportSheet.swift
//  MiGestorKMP
//
//  Created for previewing and confirming corporate email imports for students.
//

import SwiftUI
import MiGestorKit

struct StudentEmailImportSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let preview: AppleStudentEmailImportPreview

    @State private var selectedRowIds: Set<Int>
    @State private var filterStatus: StudentEmailMatchStatus? = nil
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(preview: AppleStudentEmailImportPreview) {
        self.preview = preview
        // Por defecto seleccionamos las filas emparejadas con éxito
        let initialSelected = Set(
            preview.items
                .filter { $0.status == .matched && $0.matchedStudent != nil }
                .map(\.id)
        )
        _selectedRowIds = State(initialValue: initialSelected)
    }

    private var displayedItems: [StudentEmailRowMatch] {
        if let filter = filterStatus {
            return preview.items.filter { $0.status == filter }
        }
        return preview.items
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryMetrics
                    filterBar
                    itemsList
                }
                .padding(.vertical, 20)
            }
            .background(appSecondarySystemBackgroundColor().opacity(0.35))

            Divider()
            footer
        }
        .background(appPageBackground(for: colorScheme))
        #if os(macOS)
        .frame(minWidth: 740, minHeight: 620)
        #else
        .presentationDetents([.large])
        #endif
        .alert("No se pudieron guardar los correos", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header
    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Importar correos de alumnos")
                    .font(.title2.weight(.bold))
                Text("Asocia automáticamente correos corporativos al alumnado según su clase y nombre.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: - Métricas
    private var summaryMetrics: some View {
        HStack(spacing: 12) {
            metricCard(title: "Seleccionados", value: "\(selectedRowIds.count)", color: NotebookStyle.primaryTint)
            metricCard(title: "Emparejados", value: "\(preview.matchedCount)", color: .green)
            metricCard(title: "Dudosos", value: "\(preview.ambiguousCount)", color: .orange)
            metricCard(title: "No encontrados", value: "\(preview.notFoundCount)", color: .red)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 110, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Filtros rápidos
    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton(title: "Todos (\(preview.totalRows))", status: nil)
            filterButton(title: "Emparejados (\(preview.matchedCount))", status: .matched)
            filterButton(title: "Dudosos (\(preview.ambiguousCount))", status: .ambiguous)
            filterButton(title: "No encontrados (\(preview.notFoundCount))", status: .notFound)
            Spacer()

            Button(selectedRowIds.count == preview.items.filter { $0.matchedStudent != nil }.count ? "Deseleccionar todo" : "Seleccionar válidos") {
                let validIds = preview.items.filter { $0.matchedStudent != nil }.map(\.id)
                if selectedRowIds.count == validIds.count {
                    selectedRowIds.removeAll()
                } else {
                    selectedRowIds = Set(validIds)
                }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.borderless)
            .foregroundStyle(NotebookStyle.primaryTint)
        }
        .padding(.horizontal, 24)
    }

    private func filterButton(title: String, status: StudentEmailMatchStatus?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                filterStatus = status
            }
        } label: {
            Text(title)
                .font(.caption.weight(filterStatus == status ? .bold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    filterStatus == status ? NotebookStyle.primaryTint.opacity(0.18) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
                .foregroundStyle(filterStatus == status ? NotebookStyle.primaryTint : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lista de filas
    private var itemsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(displayedItems) { item in
                itemRow(item)
            }
        }
        .padding(.horizontal, 24)
    }

    private func itemRow(_ item: StudentEmailRowMatch) -> some View {
        let isSelectable = item.matchedStudent != nil
        let isSelected = selectedRowIds.contains(item.id)

        return HStack(alignment: .center, spacing: 14) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { value in
                    if value {
                        selectedRowIds.insert(item.id)
                    } else {
                        selectedRowIds.remove(item.id)
                    }
                }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .disabled(!isSelectable)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.rawEmail)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)

                    if !item.rawCourse.isEmpty {
                        Text(item.rawCourse)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Spacer()

                    statusBadge(for: item.status)
                }

                HStack(spacing: 12) {
                    if let student = item.matchedStudent {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(NotebookStyle.primaryTint)
                            Text(student.fullName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }

                        if let className = item.matchedClassName {
                            Text("(\(className))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Sin alumno vinculado")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let detail = item.detail {
                        Text("•  \(detail)")
                            .font(.caption)
                            .foregroundStyle(detailColor(for: item.status))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? NotebookStyle.primaryTint.opacity(0.6) : NotebookStyle.softBorder.opacity(0.8),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }

    private func statusBadge(for status: StudentEmailMatchStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 7, height: 7)
            Text(status.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(statusColor(for: status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor(for: status).opacity(0.12), in: Capsule())
    }

    private func statusColor(for status: StudentEmailMatchStatus) -> Color {
        switch status {
        case .matched: return .green
        case .ambiguous: return .orange
        case .notFound: return .red
        }
    }

    private func detailColor(for status: StudentEmailMatchStatus) -> Color {
        switch status {
        case .matched: return .secondary
        case .ambiguous: return .orange
        case .notFound: return .red.opacity(0.8)
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack(spacing: 16) {
            Text(selectedRowIds.isEmpty ? "Selecciona al menos un correo para aplicar." : "\(selectedRowIds.count) correos listos para vincular.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                Task { await confirmImport() }
            } label: {
                Label(isImporting ? "Guardando..." : "Vincular \(selectedRowIds.count) correos", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedRowIds.isEmpty || isImporting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    @MainActor
    private func confirmImport() async {
        isImporting = true
        defer { isImporting = false }

        let matchesToApply = preview.items.filter { selectedRowIds.contains($0.id) }
        do {
            try await bridge.confirmStudentEmailImport(matches: matchesToApply)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
