import SwiftUI
import MiGestorKit

enum NotebookStyle {
    static let outerPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let stackSpacing: CGFloat = 12
    static let controlSpacing: CGFloat = 8
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 14
    static let chipRadius: CGFloat = 16
    static let compactChipRadius: CGFloat = 12
    static let actionHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = 44
    static let microSpacing: CGFloat = 4
    static let border = Color.black.opacity(0.06)
    static let softBorder = Color.black.opacity(0.04)
    static let shadow = Color.black.opacity(0.08)
    static let primaryTint = EvaluationDesign.accent
    static let successTint = EvaluationDesign.success
    static let warningTint = Color(red: 0.86, green: 0.52, blue: 0.12)
    static let surface = appSecondarySystemBackgroundColor().opacity(0.92)
    static let surfaceMuted = appTertiarySystemBackgroundColor().opacity(0.88)
    static let surfaceSoft = appSecondarySystemBackgroundColor().opacity(0.78)
    static let track = appTertiarySystemFillColor().opacity(0.55)
}

struct NotebookSurface<Content: View>: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    var cornerRadius: CGFloat = NotebookStyle.cardRadius
    var fill: Color = NotebookStyle.surface
    var padding: CGFloat = NotebookStyle.stackSpacing
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                adaptiveSurfaceBackground(
                    accessibilityFallback: uiFeatureFlags.accessibilitySurfaceFallback,
                    fill: fill,
                    cornerRadius: cornerRadius
                )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(NotebookStyle.border, lineWidth: 1)
                    )
                    .shadow(color: NotebookStyle.shadow.opacity(0.65), radius: 18, x: 0, y: 10)
            )
    }
}

struct NotebookSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct NotebookIconButton: View {
    let systemImage: String
    let tint: Color
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: NotebookStyle.iconButtonSize, height: NotebookStyle.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                        .fill(tint.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                        .stroke(tint.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

struct NotebookPill: View {
    let label: String
    var systemImage: String? = nil
    var active: Bool = false
    var tint: Color = NotebookStyle.primaryTint
    var compact: Bool = false

    var body: some View {
        HStack(spacing: NotebookStyle.controlSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(label)
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(active ? contrastingTextColor(for: tint) : tint)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
        .background(
            Capsule(style: .continuous)
                .fill(active ? tint : tint.opacity(0.10))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(active ? tint : tint.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct NotebookStatusBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: NotebookStyle.controlSpacing) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.10))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

struct NotebookPrimaryButton: View {
    let title: String
    let systemImage: String
    var tint: Color = NotebookStyle.primaryTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NotebookStyle.controlSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(contrastingTextColor(for: tint))
            .frame(minHeight: NotebookStyle.actionHeight)
            .padding(.horizontal, 20)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
                    .shadow(color: tint.opacity(0.22), radius: 10, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

struct NotebookTopBar: View {
    @ObservedObject var bridge: KmpBridge

    private var selectedClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == bridge.notebookViewModel.currentClassId?.int64Value ?? 0 })
    }

    private var saveBadge: (text: String, icon: String, color: Color) {
        switch bridge.notebookSaveState {
        case .saved:
            return ("Guardado", "checkmark.circle.fill", NotebookStyle.successTint)
        case .saving:
            return ("Guardando", "arrow.clockwise.circle.fill", NotebookStyle.primaryTint)
        default:
            return ("Pendiente", "clock.fill", NotebookStyle.warningTint)
        }
    }

    var body: some View {
        NotebookSurface(padding: NotebookStyle.sectionSpacing) {
            HStack(alignment: .top, spacing: NotebookStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: NotebookStyle.stackSpacing) {
                    NotebookSectionLabel(text: "Notebook")

                    VStack(alignment: .leading, spacing: NotebookStyle.controlSpacing) {
                        Text("Cuaderno")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Edita una clase cada vez con un grid limpio, estable y enfocado.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Menu {
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Button {
                                bridge.selectClass(id: Int64(schoolClass.id))
                            } label: {
                                HStack {
                                    Text(schoolClass.name)
                                    if schoolClass.id == selectedClass?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: NotebookStyle.controlSpacing) {
                            VStack(alignment: .leading, spacing: NotebookStyle.microSpacing) {
                                Text("Clase activa")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(selectedClass?.name ?? "Seleccionar clase")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, NotebookStyle.stackSpacing)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 300, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                                .fill(NotebookStyle.surfaceSoft)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                                .stroke(NotebookStyle.softBorder, lineWidth: 1)
                        )
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: NotebookStyle.stackSpacing) {
                    NotebookStatusBadge(
                        text: saveBadge.text,
                        icon: saveBadge.icon,
                        color: saveBadge.color
                    )

                    NotebookPrimaryButton(title: "Guardar", systemImage: "square.and.arrow.down") {
                        bridge.saveNotebook()
                    }
                    .disabled(bridge.notebookSaveState == .saving)
                    .opacity(bridge.notebookSaveState == .saving ? 0.7 : 1)
                }
            }
        }
    }
}
