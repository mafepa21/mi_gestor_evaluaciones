import SwiftUI

// MARK: - Estado de protección

/// Resumen del estado de las copias locales, compartido por Ajustes y el centro de copias.
struct BackupProtectionStatus {
    enum Level { case protected, stale, unprotected }

    let level: Level
    let title: String
    let detail: String

    /// La copia de referencia es la más reciente que se puede usar: una copia vacía o
    /// dañada no protege nada aunque sea la última.
    init(backups: [AppleBackupDescriptor], now: Date = Date()) {
        let usable = backups.first { backup in
            !backup.hasEmptyDatabase && !(backup.isVerified && backup.verificationError != nil)
        }
        guard let usable else {
            level = .unprotected
            title = "Aún no tienes ninguna copia"
            detail = "Crea una ahora para no perder tu trabajo."
            return
        }
        let lastText = "Última copia \(usable.manifest.createdAt.formattedRelativeText) · \(usable.sizeText)"
        let daysAgo = Calendar.current.dateComponents([.day], from: usable.manifest.createdAt, to: now).day ?? 0
        if daysAgo > 7 {
            level = .stale
            title = "Tu última copia tiene \(daysAgo) días"
            detail = lastText
        } else {
            level = .protected
            title = "Tus datos están protegidos"
            detail = lastText
        }
    }

    var tint: Color {
        switch level {
        case .protected: return IOSAppStyle.success
        case .stale: return IOSAppStyle.warning
        case .unprotected: return IOSAppStyle.danger
        }
    }

    var systemImage: String {
        switch level {
        case .protected: return "checkmark.shield.fill"
        case .stale: return "exclamationmark.shield.fill"
        case .unprotected: return "xmark.shield.fill"
        }
    }
}

// MARK: - BackupStatusSummary

/// Fila de estado de una línea: símbolo, título y detalle. El control opcional va a la derecha.
struct BackupStatusSummary<Accessory: View>: View {
    @ObservedObject var service: AppleBackupService
    var detailOverride: String?
    @ViewBuilder var accessory: () -> Accessory

    @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 40

    private var status: BackupProtectionStatus { BackupProtectionStatus(backups: service.backups) }
    private var isCreating: Bool { service.operationState == .creating }
    private var isScanning: Bool { service.operationState == .scanning && service.backups.isEmpty }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(status.tint.opacity(0.15))
                if isCreating || isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: status.systemImage)
                        .font(.title3)
                        .foregroundStyle(status.tint)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.headline)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            accessory()
        }
        .padding(.vertical, 8)
        .animation(.smooth(duration: 0.25), value: service.operationState)
    }

    private var titleText: String {
        if isCreating { return "Creando copia…" }
        if isScanning { return "Comprobando copias…" }
        return status.title
    }

    private var detailText: String {
        if isCreating { return "Puedes seguir usando la app." }
        if isScanning { return " " }
        return detailOverride ?? status.detail
    }
}

extension BackupStatusSummary where Accessory == EmptyView {
    init(service: AppleBackupService, detailOverride: String? = nil) {
        self.init(service: service, detailOverride: detailOverride) { EmptyView() }
    }
}

// MARK: - Relative Date Formatting Helper
extension Date {
    fileprivate var formattedRelativeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - CreateBackupSheet
enum CreateBackupCopy {
    static let failure = "No se pudo crear la copia. Sigue en esta pantalla."
}

struct CreateBackupSheet: View {
    @Binding var isPresented: Bool
    @Binding var note: String
    var onConfirm: () async throws -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        #if os(macOS)
        mainContent
            .frame(width: 420, height: 260)
            .padding()
        #else
        NavigationStack {
            mainContent
                .navigationTitle("Nueva copia")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { isPresented = false }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Creando…" : "Crear") {
                            confirm()
                        }
                        .fontWeight(.bold)
                        .disabled(isSaving)
                    }
                }
        }
        .presentationDetents([.height(280)])
        #endif
    }
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            Text("Crear copia de seguridad manual")
                .font(.headline)
            #endif
            
            Text("Añade una descripción o nota (opcional) para identificar esta copia de seguridad en el historial.")
                .font(IOSAppStyle.bodyText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            TextField("Ej. Antes de importar alumnos de 3º A", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(IOSAppStyle.bodyText)
                .focused($isTextFieldFocused)
                .appWritingToolsDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .onAppear {
                    // Auto-focus field on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isTextFieldFocused = true
                    }
                }
            
            Spacer()
            
            #if os(macOS)
            HStack {
                Spacer()
                Button("Cancelar") { isPresented = false }
                    .disabled(isSaving)
                Button(isSaving ? "Creando…" : "Crear") {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            #endif
        }
        .padding()
        .background(IOSAppStyle.pageBackground)
    }

    private func confirm() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await onConfirm()
                errorMessage = nil
                isPresented = false
            } catch {
                errorMessage = CreateBackupCopy.failure
            }
            isSaving = false
        }
    }
}
