import SwiftUI
import AppKit

struct MacPremiumHeaderAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    let handler: () -> Void
}

enum MacPremiumOperationStateKind: Equatable {
    case idle
    case loading(String)
    case saving(String)
    case saved(String)
    case warning(String)
    case failed(String)
    case pendingSync(Int)
}

struct MacPremiumOperationState: View {
    let kind: MacPremiumOperationStateKind

    var body: some View {
        if kind != .idle {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MacLiquidGlassStyle.statusFill(isActive: true, tint: tint), in: Capsule(style: .continuous))
                .help(label)
                .transition(MacAppStyle.smallStateTransition)
        }
    }

    private var label: String {
        switch kind {
        case .idle:
            return ""
        case .loading(let value), .saving(let value), .saved(let value), .warning(let value), .failed(let value):
            return value
        case .pendingSync(let count):
            return count == 1 ? "1 pendiente" : "\(count) pendientes"
        }
    }

    private var systemImage: String {
        switch kind {
        case .idle:
            return "circle"
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .saving:
            return "square.and.arrow.down"
        case .saved:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.octagon"
        case .pendingSync:
            return "icloud.and.arrow.up"
        }
    }

    private var tint: Color {
        switch kind {
        case .idle:
            return .secondary
        case .loading, .saving, .pendingSync:
            return MacAppStyle.infoTint
        case .saved:
            return MacAppStyle.successTint
        case .warning:
            return MacAppStyle.warningTint
        case .failed:
            return MacAppStyle.dangerTint
        }
    }
}

struct MacPremiumModuleHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var state: MacPremiumOperationStateKind? = nil
    var primaryAction: MacPremiumHeaderAction? = nil
    var secondaryActions: [MacPremiumHeaderAction] = []
    @ViewBuilder var trailingLayoutAction: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(MacAppStyle.pageTitle)
                    if let state {
                        MacPremiumOperationState(kind: state)
                    }
                }
                .animation(MacAppStyle.smallStateAnimation, value: state)

                Text(subtitle)
                    .font(MacAppStyle.bodyText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                trailingLayoutAction()
                secondaryActionsView
                if let primaryAction {
                    Button {
                        primaryAction.handler()
                    } label: {
                        Label(primaryAction.title, systemImage: primaryAction.systemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryAction.isDisabled)
                }
            }
        }
    }

    @ViewBuilder
    private var secondaryActionsView: some View {
        if secondaryActions.count == 1, let action = secondaryActions.first {
            Button {
                action.handler()
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .buttonStyle(.bordered)
            .disabled(action.isDisabled)
        } else if !secondaryActions.isEmpty {
            Menu {
                ForEach(secondaryActions) { action in
                    Button {
                        action.handler()
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(action.isDisabled)
                }
            } label: {
                Label("Acciones", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
        }
    }
}

extension MacPremiumModuleHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        state: MacPremiumOperationStateKind? = nil,
        primaryAction: MacPremiumHeaderAction? = nil,
        secondaryActions: [MacPremiumHeaderAction] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.state = state
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.trailingLayoutAction = { EmptyView() }
    }
}

struct MacPremiumFilterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            content()
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassPanel(.secondaryPanel)
    }
}

struct MacPremiumControlStrip<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            content()
        }
        .padding(.horizontal, MacAppStyle.innerPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassPanel(.secondaryPanel)
    }
}

struct MacPremiumTableContainer<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let count: Int
    var isLoading: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MacAppStyle.sectionTitle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                MacStatusPill(
                    label: count == 1 ? "1 registro" : "\(count) registros",
                    isActive: count > 0,
                    tint: MacAppStyle.infoTint
                )
            }

            ZStack(alignment: .topTrailing) {
                content()
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)

                if isLoading {
                    Label("Actualizando", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MacAppStyle.infoTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(MacLiquidGlassStyle.readableSurfaceFallback, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(MacAppStyle.cardBorder, lineWidth: MacLiquidGlassStyle.hairlineWidth)
                        }
                        .padding(12)
                        .transition(MacAppStyle.smallStateTransition)
                }
            }
            .animation(MacAppStyle.smallStateAnimation, value: isLoading)
        }
        .padding(MacAppStyle.innerPadding)
        .macLiquidGlassPanel(.primaryPanel)
    }
}

struct MacPremiumInspectorSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacAppStyle.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassPanel(.secondaryPanel)
    }
}

struct MacPremiumInspectorHeader<Badges: View>: View {
    let title: String
    let subtitle: String
    var onClose: (() -> Void)? = nil
    @ViewBuilder var badges: () -> Badges

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(MacAppStyle.subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Cerrar ficha")
                    .accessibilityLabel("Cerrar ficha")
                }
            }

            badges()
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassPanel(.secondaryPanel)
    }
}

struct MacPremiumInspectorMetricGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacAppStyle.cardSpacing) {
            content()
        }
    }
}

struct MacPremiumInspectorActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
