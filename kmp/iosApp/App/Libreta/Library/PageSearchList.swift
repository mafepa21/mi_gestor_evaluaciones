import SwiftUI

/// Resultados de búsqueda en el texto manuscrito (reconocido con Vision) y en las cajas de texto.
struct PageSearchList: View {
    let notebooks: [Notebook]
    let query: String
    let showNotebookTitle: Bool
    let onSelect: (Notebook, Int) -> Void

    private struct Hit: Identifiable {
        let notebook: Notebook
        let page: Page
        var id: UUID { page.id }
    }

    private struct NotebookHits: Identifiable {
        let notebook: Notebook
        let hits: [Hit]
        var id: UUID { notebook.id }
    }

    private var groups: [NotebookHits] {
        notebooks.compactMap { nb in
            let hits = nb.sortedPages
                .filter { SearchMatch.matches($0, query: query) }
                .map { Hit(notebook: nb, page: $0) }
            return hits.isEmpty ? nil : NotebookHits(notebook: nb, hits: hits)
        }
    }

    var body: some View {
        let found = groups
        if found.isEmpty {
            EmptyStateView("Sin resultados", systemImage: "magnifyingglass",
                           message: "No aparece «\(query)» en tus notas. Las hojas recién escritas tardan unos segundos en poder buscarse.")
                .padding(.top, 48)
        } else {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(found) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        if showNotebookTitle { header(group.notebook, count: group.hits.count) }
                        ForEach(group.hits) { hit in
                            row(hit)
                            if hit.id != group.hits.last?.id {
                                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                                    .padding(.leading, 96)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ nb: Notebook, count: Int) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CoverColor.from(nb.coverColorRaw).color)
                .frame(width: 10, height: 14)
            Text(nb.title.isEmpty ? "Sin título" : nb.title)
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if let group = nb.group {
                Text(verbatim: "· \(group.displayName)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: count == 1 ? "1 hoja" : "\(count) hojas")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private func row(_ hit: Hit) -> some View {
        Button { onSelect(hit.notebook, hit.page.index) } label: {
            HStack(alignment: .top, spacing: 18) {
                PageThumbnailView(page: hit.page, style: hit.page.style(in: hit.notebook), width: 64)
                    .padding(.leading, 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hoja \(hit.page.index + 1)")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.ink)
                    Text(highlighted(SearchMatch.snippet(hit.page, query: query)))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                    .padding(.top, 8)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(SearchRowStyle())
    }

    /// Resalta la coincidencia dentro del fragmento.
    private func highlighted(_ snippet: String) -> AttributedString {
        var text = AttributedString(snippet)
        if let r = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[r].foregroundColor = Theme.ink
            text[r].backgroundColor = Theme.accent.opacity(0.16)
        }
        return text
    }
}

private struct SearchRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.ink.opacity(configuration.isPressed ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

/// Hoja de búsqueda dentro de un cuaderno abierto.
struct NotebookSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook
    let onSelect: (Int) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyStateView("Busca en tus notas", systemImage: "magnifyingglass",
                                   message: "Se busca en tu letra y en las cajas de texto. Las hojas recién escritas tardan unos segundos en indexarse.")
                        .padding(.top, 60)
                } else {
                    PageSearchList(notebooks: [notebook], query: query, showNotebookTitle: false) { _, index in
                        onSelect(index); dismiss()
                    }
                    .padding(.top, 12)
                }
            }
            .background(ShelfBackground())
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.desk, for: .navigationBar)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar en \(notebook.title)")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Buscar").font(Theme.Fonts.headline).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }
}
