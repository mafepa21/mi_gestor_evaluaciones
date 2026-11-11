import SwiftUI
import MiGestorKit

struct FlexibleTagRow: View {
    let items: [String]
    let selected: String
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    tagContent(for: item)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected == item ? NotebookStyle.primaryTint.opacity(0.16) : NotebookStyle.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func tagContent(for item: String) -> some View {
        if item.contains(".") {
            Image(systemName: item)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        } else {
            Text(item.isEmpty ? "Sin icono" : item)
                .font(.system(size: item.isEmpty ? 11 : 18, weight: .bold, design: .rounded))
        }
    }
}

struct NotebookContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    init(_ title: String, systemImage: String, description: String) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}

struct NotebookStateCard<Accessory: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = NotebookStyle.primaryTint
    @ViewBuilder var accessory: Accessory

    init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = NotebookStyle.primaryTint,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 28) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    accessory
                }
                .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}


// MARK: - Aviso de guardado

/// Aviso de guardado del Cuaderno, visible en todos los modos de barra
/// (iPad ancho, iPad estrecho y Mac). Observa solo el store del Cuaderno para
/// no repintar el módulo entero cuando cambia el estado de guardado.
struct NotebookSaveStatusOverlay: View {
    @ObservedObject var store: NotebookBridgeStore
    /// Error de asistencia pendiente, si lo hay. No tiene "Reintentar": se
    /// reintenta pulsando otra vez la celda.
    let attendanceError: String?
    let onRetry: () -> Void

    /// Solo se enseña "Guardando…" si el guardado tarda: así no parpadea en
    /// cada nota, que normalmente se guarda en milisegundos.
    @State private var showsSlowSave = false
    private static let slowSaveDelay: UInt64 = 600_000_000

    private var isFailed: Bool {
        NotebookSaveBadge.showsFailure(
            splitFailed: store.notebookSplitSaveState.state == .failed,
            inlineFailed: store.notebookSaveState == .failed
        )
    }

    private var isBusy: Bool {
        !isFailed && (store.notebookSplitSaveState.isSaving || store.notebookSplitSaveState.isDirty)
    }

    var body: some View {
        VStack(spacing: 8) {
            if isFailed {
                failureBanner(
                    message: "No se pudo guardar. Tus últimos cambios aún no están guardados.",
                    showsRetry: true
                )
            }
            if let attendanceError {
                failureBanner(message: attendanceError, showsRetry: false)
            }
            if showsSlowSave && isBusy {
                savingChip
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFailed)
        .animation(.easeInOut(duration: 0.2), value: attendanceError)
        .animation(.easeInOut(duration: 0.2), value: showsSlowSave && isBusy)
        .task(id: isBusy) {
            guard isBusy else {
                showsSlowSave = false
                return
            }
            try? await Task.sleep(nanoseconds: Self.slowSaveDelay)
            if !Task.isCancelled { showsSlowSave = true }
        }
        .appOnChange(of: isFailed) { failed in
            guard failed else { return }
            AccessibilityNotification.Announcement("No se pudo guardar el cuaderno").post()
        }
        .appOnChange(of: attendanceError) { message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private func failureBanner(message: String, showsRetry: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .notebookFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if showsRetry {
                Button(action: onRetry) {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NotebookStyle.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var savingChip: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
            Text("Guardando…")
                .notebookFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(NotebookStyle.surface))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Guardando cambios")
        .transition(.opacity)
    }
}
