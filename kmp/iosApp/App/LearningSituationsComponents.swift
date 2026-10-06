import SwiftUI
import MiGestorKit

// Componentes compartidos de Situaciones de Aprendizaje: estado, avisos en línea,
// tarjetas editoriales, chips de filtro, búsqueda y esqueletos de carga.
// Lenguaje visual único: EvaluationDesign editorial para el contenido; el vidrio queda
// reservado al chrome del sistema.

// MARK: - Estado

enum LearningSituationStatusStyle {
    static func label(_ status: LearningSituationStatus) -> String {
        switch status {
        case .draft: return "Borrador"
        case .active: return "Activa"
        case .archived: return "Archivada"
        default: return "Sin estado"
        }
    }

    static func icon(_ status: LearningSituationStatus) -> String {
        switch status {
        case .draft: return "pencil.circle"
        case .active: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        default: return "circle.dashed"
        }
    }

    static func tint(_ status: LearningSituationStatus) -> Color {
        switch status {
        case .draft: return IOSAppStyle.warning
        case .active: return EvaluationDesign.success
        case .archived: return .secondary
        default: return .secondary
        }
    }
}

/// Estado con icono y texto (nunca solo color).
struct LearningSituationStatusBadge: View {
    let status: LearningSituationStatus

    var body: some View {
        let tint = LearningSituationStatusStyle.tint(status)
        Label(LearningSituationStatusStyle.label(status), systemImage: LearningSituationStatusStyle.icon(status))
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Estado: \(LearningSituationStatusStyle.label(status))")
    }
}

// MARK: - Aviso en línea

enum LearningSituationNoticeKind {
    case error
    case warning
    case info

    var tint: Color {
        switch self {
        case .error: return EvaluationDesign.danger
        case .warning: return IOSAppStyle.warning
        case .info: return EvaluationDesign.accent
        }
    }

    var icon: String {
        switch self {
        case .error: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// Aviso breve y recuperable dentro del contenido (sustituye a alertas bloqueantes).
struct LearningSituationInlineNotice: View {
    let kind: LearningSituationNoticeKind
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var minimumTapSize: CGFloat = 44

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                messageLabel
                Spacer(minLength: 8)
                actionButton
            }
            VStack(alignment: .leading, spacing: 8) {
                messageLabel
                actionButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var messageLabel: some View {
        Label {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
        }
        .frame(minHeight: minimumTapSize - 8)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .tint(kind.tint)
                .frame(minHeight: minimumTapSize)
        }
    }
}

// MARK: - Tarjeta editorial

struct LearningSituationCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        }
    }
}

// MARK: - Distribución en varias líneas

/// Coloca los elementos en filas y salta de línea cuando no caben (chips, botones).
struct LearningSituationFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let width = min(size.width, maxWidth)
            if rowWidth > 0 && rowWidth + spacing + width > maxWidth {
                totalHeight += rowHeight + spacing
                widest = max(widest, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        widest = max(widest, rowWidth)
        return CGSize(width: proposal.width ?? widest, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let width = min(size.width, bounds.width)
            if origin.x > bounds.minX && origin.x + width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(width: width, height: size.height))
            origin.x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Chip de filtro

/// Chip con menú. Inactivo: neutro («Grupo»). Activo: acento con su valor y botón para quitarlo.
struct LearningSituationFilterChip<MenuContent: View>: View {
    let title: String
    let valueLabel: String?
    let onClear: () -> Void
    @ViewBuilder var menuContent: MenuContent
    @ScaledMetric(relativeTo: .body) private var minimumTapSize: CGFloat = 44

    private var isActive: Bool { valueLabel != nil }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                menuContent
            } label: {
                HStack(spacing: 4) {
                    Text(valueLabel.map { "\(title): \($0)" } ?? title)
                        .lineLimit(1)
                    if !isActive {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.leading, 12)
                .padding(.trailing, isActive ? 4 : 12)
                .frame(minHeight: minimumTapSize)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(valueLabel.map { "Filtro \(title): \($0)" } ?? "Filtrar por \(title)")

            if isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(minWidth: minimumTapSize - 8, minHeight: minimumTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quitar filtro \(title)")
            }
        }
        .foregroundStyle(isActive ? EvaluationDesign.accent : Color.primary)
        .background(
            Capsule(style: .continuous)
                .fill(isActive ? EvaluationDesign.accentSoft : Color.clear)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(isActive ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - Búsqueda

/// Campo de búsqueda propio del módulo. No se usa `.searchable` porque la vista vive
/// dentro del shell, que ya instala su propio buscador global: saldrían dos.
struct LearningSituationSearchField: View {
    @Binding var text: String
    var prompt: String
    @ScaledMetric(relativeTo: .body) private var minimumTapSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled()
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: minimumTapSize - 12, minHeight: minimumTapSize - 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: minimumTapSize)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous))
    }
}

// MARK: - Esqueletos de carga

struct LearningSituationSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Situación de aprendizaje de ejemplo")
                .font(.headline)
            Text("Materia · Curso · Trimestre")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

struct LearningSituationSkeletonBlock: View {
    var lines: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { index in
                Text(index == 0 ? "Título del bloque de contenido" : "Línea de contenido de ejemplo para reservar espacio")
                    .font(index == 0 ? .headline : .subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
