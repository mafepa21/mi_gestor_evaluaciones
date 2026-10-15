import SwiftUI
import SwiftData

struct NewNotebookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\NotebookGroup.sortOrder), SortDescriptor(\NotebookGroup.createdAt)])
    private var groups: [NotebookGroup]
    /// Recibe el cuaderno nuevo y su grupo (`nil` = suelto). El cuaderno aún no está insertado.
    let onCreate: (Notebook, NotebookGroup?) -> Void

    @State private var title = ""
    @State private var color: CoverColor = .defaultColor
    @State private var paper: PaperStyle = .ruled
    @State private var groupID: UUID?
    @FocusState private var titleFocused: Bool

    /// `initialGroupID`: grupo preseleccionado (al crear desde una balda o un montón).
    init(initialGroupID: UUID? = nil, onCreate: @escaping (Notebook, NotebookGroup?) -> Void) {
        self.onCreate = onCreate
        _groupID = State(initialValue: initialGroupID)
    }

    private let coverWidth: CGFloat = 200
    /// Ancho de cada muestra de papel: cuatro por fila ocupan lo mismo que la fila antigua.
    private let paperTileWidth: CGFloat = 72

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 44) {
                    // Vista previa: el cuaderno tal como quedará en la mesa.
                    VStack(spacing: 14) {
                        NotebookCoverView(title: title.isEmpty ? "Libreta" : title,
                                          color: color,
                                          size: CGSize(width: coverWidth, height: coverWidth / Theme.coverAspect))
                            .animation(.easeInOut(duration: 0.2), value: color)
                        Text(verbatim: previewCaption)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    VStack(alignment: .leading, spacing: 28) {
                        field("Título") {
                            TextField("Libreta", text: $title)
                                .font(Theme.Fonts.serif(22))
                                .foregroundStyle(Theme.ink)
                                .focused($titleFocused)
                                .submitLabel(.done)
                                .padding(.bottom, 6)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(titleFocused ? Theme.accent : Theme.hairline)
                                        .frame(height: titleFocused ? 1.5 : 1)
                                }
                        }

                        field("Tapa") {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 10), count: 4),
                                      alignment: .leading, spacing: 10) {
                                ForEach(CoverColor.allCases) { c in
                                    Button { color = c } label: {
                                        ColorSwatch(color: c.color, isSelected: c == color, diameter: 32)
                                    }
                                    .buttonStyle(PressableButtonStyle(scale: 0.9))
                                    .accessibilityLabel(c.label)
                                    .accessibilityAddTraits(c == color ? .isSelected : [])
                                }
                            }
                        }

                        if !groups.isEmpty {
                            field("Grupo") {
                                Picker("Grupo", selection: $groupID) {
                                    Text("Sin grupo (suelto)").tag(UUID?.none)
                                    ForEach(groups) { g in
                                        Text(g.displayName).tag(UUID?.some(g.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }

                        field("Papel") {
                            // Dos filas de cuatro: papeles básicos arriba, plantillas abajo.
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(paperTileWidth), spacing: 8), count: 4),
                                      alignment: .leading, spacing: 16) {
                                ForEach(PaperStyle.allCases) { style in
                                    Button { paper = style } label: { paperTile(style) }
                                        .buttonStyle(PressableButtonStyle(scale: 0.95))
                                        .accessibilityLabel(style.label)
                                        .accessibilityAddTraits(style == paper ? .isSelected : [])
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(32)
            }
            .background(ShelfBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.desk, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Nueva libreta").font(Theme.Fonts.headline).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(Notebook(title: t.isEmpty ? "Libreta" : t,
                                          coverColorRaw: color.rawValue,
                                          paperStyle: paper),
                                 groups.first { $0.id == groupID })
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.large])
    }

    private var previewCaption: String {
        let base = "\(color.label) · \(paper.label)"
        guard let g = groups.first(where: { $0.id == groupID }) else { return base }
        return "\(base) · \(g.displayName)"
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.inkSecondary)
            content()
        }
    }

    /// Muestra de papel en miniatura.
    private func paperTile(_ style: PaperStyle) -> some View {
        let selected = style == paper
        return VStack(spacing: 8) {
            PaperBackground(style: style)
                .frame(width: 54, height: 54 / Theme.pageAspect)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Theme.paperEdgeLine, lineWidth: 0.5)
                )
                .shadow(color: Theme.shadow, radius: 2, y: 1)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .opacity(selected ? 1 : 0)
                )
            Text(style.label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: paperTileWidth)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
