import SwiftUI

enum ExportScope {
    case notebook(Notebook, currentPage: Page?)
    /// Toda la biblioteca: cuadernos y grupos (también los vacíos).
    case library([Notebook], groups: [NotebookGroup])
}

/// Genera un PDF o una copia de seguridad y la ofrece para compartir / guardar en Archivos.
@MainActor
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let scope: ExportScope

    @State private var fileURL: URL?
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch scope {
                    case .notebook(let nb, let current):
                        Button { makePDF(nb, pages: nb.sortedPages, name: nb.title) } label: {
                            ExportRow(title: "PDF de la libreta completa",
                                      detail: nb.pageList.count == 1 ? "1 hoja" : "\(nb.pageList.count) hojas, lista para imprimir o enviar",
                                      systemImage: "doc.richtext")
                        }
                        if let current {
                            Button { makePDF(nb, pages: [current], name: "\(nb.title) – hoja \(current.index + 1)") } label: {
                                ExportRow(title: "PDF de esta hoja",
                                          detail: "Solo la hoja \(current.index + 1)",
                                          systemImage: "doc")
                            }
                        }
                        Button { makeBackup([nb], name: "\(nb.title).cuaderno") } label: {
                            ExportRow(title: "Copia de seguridad de la libreta",
                                      detail: "Archivo que se puede restaurar desde la biblioteca",
                                      systemImage: "archivebox")
                        }
                    case .library(let all, let groups):
                        Button { makeBackup(all, groups: groups, name: "Libretas-\(Date.now.formatted(.iso8601.year().month().day()))") } label: {
                            ExportRow(title: "Copia de seguridad de la biblioteca",
                                      detail: libraryDetail(notebooks: all.count, groups: groups.count),
                                      systemImage: "archivebox")
                        }
                    }
                } header: {
                    sectionHeader("Exportar")
                }
                .disabled(busy)
                .listRowBackground(Theme.paper)

                if busy || errorMessage != nil || fileURL != nil {
                    Section {
                        if busy {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Preparando…")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.paperInkSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.ribbon)
                        }
                        if let fileURL {
                            ShareLink(item: fileURL) {
                                HStack {
                                    Spacer()
                                    Label("Compartir o guardar en Archivos…", systemImage: "square.and.arrow.up")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Theme.accent)
                                .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        sectionHeader(fileURL != nil ? "Listo" : "")
                    }
                    .listRowBackground(Theme.paper)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShelfBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.desk, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Exportar").font(Theme.Fonts.headline).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
            .animation(.easeOut(duration: 0.2), value: busy)
            .animation(.easeOut(duration: 0.2), value: fileURL)
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.inkSecondary)
            .textCase(nil)
    }

    private func makePDF(_ nb: Notebook, pages: [Page], name: String) {
        run {
            fileURL = await PageRenderer.writePDF(pages: pages, notebook: nb, name: name)
            if fileURL == nil { errorMessage = "No se pudo crear el PDF." }
        }
    }

    private func libraryDetail(notebooks: Int, groups: Int) -> String {
        let nbs = notebooks == 1 ? "1 libreta" : "\(notebooks) libretas"
        switch groups {
        case 0: return notebooks == 1 ? nbs : "\(nbs), con tinta y objetos"
        case 1: return "\(nbs) y 1 grupo, con tinta y objetos"
        default: return "\(nbs) y \(groups) grupos, con tinta y objetos"
        }
    }

    private func makeBackup(_ notebooks: [Notebook], groups: [NotebookGroup] = [], name: String) {
        run {
            do { fileURL = try Backup.write(notebooks, groups: groups, name: name) }
            catch { errorMessage = "No se pudo crear la copia: \(error.localizedDescription)" }
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true; fileURL = nil; errorMessage = nil
        Task { await work(); busy = false }
    }
}

/// Fila de exportación: icono en el acento, título y una línea de detalle.
private struct ExportRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.paperInk)
                Text(detail)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.paperInkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
