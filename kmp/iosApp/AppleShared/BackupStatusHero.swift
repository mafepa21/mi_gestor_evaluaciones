import SwiftUI

struct BackupStatusHero: View {
    @ObservedObject var service: AppleBackupService
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCreateDialog = false
    @State private var backupNote = ""

    private var safetyStatus: (title: String, subtitle: String, color: Color, icon: String) {
        if service.backups.isEmpty {
            return (
                title: "Datos desprotegidos",
                subtitle: "No se han detectado copias de seguridad locales. Crea una copia ahora para proteger tu trabajo diario.",
                color: IOSAppStyle.danger,
                icon: "exclamationmark.shield.fill"
            )
        }
        
        let newest = service.backups[0].manifest.createdAt
        let daysAgo = Calendar.current.dateComponents([.day], from: newest, to: Date()).day ?? 0
        
        if daysAgo > 7 {
            return (
                title: "Protección desactualizada",
                subtitle: "Tu última copia tiene más de 7 días (\(daysAgo) días). Te sugerimos realizar un respaldo reciente.",
                color: IOSAppStyle.warning,
                icon: "shield.dotted"
            )
        }
        
        return (
            title: "Datos protegidos",
            subtitle: "Tus datos están a salvo. Tienes una copia reciente y válida realizada hace menos de una semana.",
            color: IOSAppStyle.success,
            icon: "checkmark.shield.fill"
        )
    }

    var body: some View {
        PremiumCard.section {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    // Pulsing / glowing status icon
                    ZStack {
                        Circle()
                            .fill(safetyStatus.color.opacity(0.12))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: safetyStatus.icon)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(safetyStatus.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(safetyStatus.title)
                            .font(IOSAppStyle.sectionTitle.weight(.bold))
                            .foregroundStyle(safetyStatus.color)
                        
                        if let lastBackup = service.backups.first {
                            Text("Última: \(lastBackup.manifest.createdAt.formattedRelativeText) · \(lastBackup.sizeText)")
                                .font(IOSAppStyle.captionText)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Sin historial de copias")
                                .font(IOSAppStyle.captionText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                Text(safetyStatus.subtitle)
                    .font(IOSAppStyle.bodyText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Divider()
                    .padding(.vertical, 2)
                
                HStack {
                    if service.operationState == .creating {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Creando copia de seguridad...")
                                .font(IOSAppStyle.bodyText.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    } else {
                        PrimaryActionButton(
                            label: "Crear Copia en 1 Clic",
                            systemImage: "plus.shield",
                            tint: IOSAppStyle.info,
                            fullWidth: false
                        ) {
                            backupNote = ""
                            showingCreateDialog = true
                        }
                        .transition(.opacity)
                    }
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingCreateDialog) {
            CreateBackupSheet(isPresented: $showingCreateDialog, note: $backupNote) {
                let finalNote = backupNote.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await service.createBackup(note: finalNote.isEmpty ? nil : finalNote)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: service.operationState)
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
