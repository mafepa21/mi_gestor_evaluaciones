import SwiftUI

/// Miniaturas de todas las hojas: saltar, marcapáginas, plantilla, insertar, borrar y reordenar (arrastrando).
struct PageOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook
    let currentIndex: Int
    let onSelect: (Int) -> Void
    let onChanged: () -> Void

    @State private var onlyBookmarks = false
    @State private var pendingDelete: Page?

    private var pages: [Page] {
        notebook.sortedPages.filter { !onlyBookmarks || $0.isBookmarked }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Filtro", selection: $onlyBookmarks) {
                    Text("Todas las hojas").tag(false)
                    Label("Marcapáginas", systemImage: "bookmark.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .padding(.horizontal, 24).padding(.top, 12)

                if pages.isEmpty {
                    EmptyStateView("Sin marcapáginas", systemImage: "bookmark",
                                   message: "Marca una hoja con el icono del marcapáginas para encontrarla aquí.")
                        .padding(.top, 48)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 28)], spacing: 30) {
                        ForEach(pages) { page in cell(page) }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 24)
                }
            }
            .background(ShelfBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.desk, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Hojas").font(Theme.Fonts.headline).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Añadir hoja", systemImage: "plus") {
                        notebook.insertPage(after: notebook.pageList.count - 1)
                        onChanged()
                    }
                }
            }
            .confirmationDialog("¿Eliminar la hoja \((pendingDelete?.index ?? 0) + 1) y todo lo que contiene?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Eliminar hoja", role: .destructive) {
                    if let p = pendingDelete { notebook.delete(p); onChanged() }
                    pendingDelete = nil
                }
            }
        }
        .tint(Theme.accent)
    }

    private func cell(_ page: Page) -> some View {
        let isCurrent = page.index == currentIndex
        return Button { onSelect(page.index); dismiss() } label: {
            VStack(spacing: 10) {
                PageThumbnailView(page: page, style: page.style(in: notebook), width: 130)
                    .overlay(alignment: .topTrailing) {
                        if page.isBookmarked {
                            BookmarkRibbon()
                                .frame(width: 10, height: 28)
                                .offset(y: -3)
                                .padding(.trailing, 12)
                                .allowsHitTesting(false)
                        }
                    }
                    .background {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: Theme.pageCornerRadius + 5, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 2)
                                .padding(-6)
                        }
                    }
                Text(verbatim: "\(page.index + 1)")
                    .font(isCurrent ? Theme.Fonts.pageNumber.weight(.semibold) : Theme.Fonts.pageNumber)
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.inkSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Hoja \(page.index + 1)\(page.isBookmarked ? ", con marcapáginas" : "")\(isCurrent ? ", actual" : "")"))
        .draggable(page.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let id = UUID(uuidString: s) else { return false }
            notebook.move(pageID: id, before: page.id)
            onChanged()
            return true
        }
        .contextMenu {
            Button(page.isBookmarked ? "Quitar marcapáginas" : "Marcar hoja",
                   systemImage: page.isBookmarked ? "bookmark.slash" : "bookmark") {
                page.isBookmarked.toggle()
            }
            Button("Insertar hoja después", systemImage: "plus.square.on.square") {
                notebook.insertPage(after: page.index); onChanged()
            }
            PageTemplateMenu(page: page, notebookStyle: notebook.paperStyle)
            Button("Eliminar hoja", systemImage: "trash", role: .destructive) { pendingDelete = page }
                .disabled(notebook.pageList.count <= 2)
        }
    }
}
