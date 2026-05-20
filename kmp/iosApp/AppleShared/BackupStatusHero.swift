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
                color: AppleDesignSystem.danger,
                icon: "exclamationmark.shield.fill"
            )
        }
        
        let newest = service.backups[0].manifest.createdAt
        let daysAgo = Calendar.current.dateComponents([.day], from: newest, to: Date()).day ?? 0
        
        if daysAgo > 7 {
            return (
                title: "Protección desactualizada",
                subtitle: "Tu última copia tiene más de 7 días (\(daysAgo) días). Te sugerimos realizar un respaldo reciente.",
                color: AppleDesignSystem.warning,
                icon: "shield.dotted"
            )
        }
        
        return (
            title: "Datos protegidos",
            subtitle: "Tus datos están a salvo. Tienes una copia reciente y válida realizada hace menos de una semana.",
            color: AppleDesignSystem.success,
            icon: "checkmark.shield.fill"
        )
    }

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    // Modern pulsing / glowing status icon
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
                            .font(.title3.weight(.bold))
                            .foregroundStyle(safetyStatus.color)
                        
                        if let lastBackup = service.backups.first {
                            Text("Última: \(lastBackup.manifest.createdAt.formattedRelativeText) · \(lastBackup.sizeText)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Sin historial de copias")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                Text(safetyStatus.subtitle)
                    .font(.subheadline)
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
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    } else {
                        Button(action: {
                            backupNote = ""
                            showingCreateDialog = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.shield")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Crear Copia en 1 Clic")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(contrastingTextColor(for: AppleDesignSystem.accent))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius, style: .continuous)
                                    .fill(AppleDesignSystem.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingCreateDialog) {
            CreateBackupSheet(isPresented: $showingCreateDialog, note: $backupNote) {
                Task {
                    let finalNote = backupNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try? await service.createBackup(note: finalNote.isEmpty ? nil : finalNote)
                }
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
struct CreateBackupSheet: View {
    @Binding var isPresented: Bool
    @Binding var note: String
    var onConfirm: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        #if os(macOS)
        mainContent
            .frame(width: 420, height: 260)
            .padding()
        #else
        NavigationView {
            mainContent
                .navigationTitle("Nueva copia")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { isPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Crear") {
                            onConfirm()
                            isPresented = false
                        }
                        .fontWeight(.bold)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            TextField("Ej. Antes de importar alumnos de 3º A", text: $note)
                .textFieldStyle(.roundedBorder)
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
                Button("Crear") {
                    onConfirm()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            #endif
        }
        .padding()
        .background(AppleDesignSystem.pageBackground(for: colorScheme))
    }
}
