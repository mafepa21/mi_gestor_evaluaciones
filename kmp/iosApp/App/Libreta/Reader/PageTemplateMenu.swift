import SwiftUI

/// Submenú «Plantilla de esta hoja»: «Como el cuaderno» (sin plantilla propia) y los
/// ocho papeles. Se usa en el menú «…» del lector y en el menú contextual de las miniaturas.
struct PageTemplateMenu: View {
    let page: Page
    let notebookStyle: PaperStyle

    private var selection: Binding<String> {
        Binding(get: { page.templateRaw }, set: { page.templateRaw = $0 })
    }

    var body: some View {
        Menu {
            Picker("Plantilla de esta hoja", selection: selection) {
                Label("Como el cuaderno (\(notebookStyle.label))", systemImage: "book.closed")
                    .tag("")
                ForEach(PaperStyle.allCases) { style in
                    Label(style.label, systemImage: style.systemImage)
                        .tag(style.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Plantilla de esta hoja", systemImage: "doc.text")
        }
    }
}
