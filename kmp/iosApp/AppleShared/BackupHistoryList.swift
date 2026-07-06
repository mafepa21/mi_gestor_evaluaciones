import SwiftUI
#if os(iOS)
import UIKit
#endif

struct BackupHistoryList: View {
    @ObservedObject var service: AppleBackupService
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var searchText = ""
    @State private var selectedBackupForRestore: AppleBackupDescriptor?
    @State private var backupToExport: AppleBackupDescriptor?
    @State private var showingShareSheet = false
    @State private var backupToDelete: AppleBackupDescriptor?
    @State private var showingDeleteAlert = false
    
    var filteredBackups: [AppleBackupDescriptor] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return service.backups
        }
        return service.backups.filter { backup in
            let noteMatch = backup.manifest.note?.localizedCaseInsensitiveContains(searchText) ?? false
            let deviceMatch = backup.manifest.deviceName.localizedCaseInsensitiveContains(searchText)
            let platformMatch = backup.manifest.platform.localizedCaseInsensitiveContains(searchText)
            let dateMatch = backup.manifest.createdAt.formattedDateText.localizedCaseInsensitiveContains(searchText)
            return noteMatch || deviceMatch || platformMatch || dateMatch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search field
            IOSSearchField(text: $searchText, placeholder: "Buscar copias…")
            
            if filteredBackups.isEmpty {
                IOSEmptyState(
                    title: "No se encontraron copias",
                    subtitle: searchText.isEmpty
                        ? "Aún no has creado ninguna copia de seguridad local. Tu historial aparecerá aquí."
                        : "No hay copias que coincidan con la búsqueda.",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(height: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredBackups) { backup in
                            BackupRowView(
                                backup: backup,
                                onVerify: {
                                    Task {
                                        _ = await service.verifyBackup(backup)
                                    }
                                },
                                onRestore: {
                                    selectedBackupForRestore = backup
                                },
                                onExport: {
                                    triggerExport(backup)
                                },
                                onDelete: {
                                    backupToDelete = backup
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .sheet(item: $selectedBackupForRestore) { backup in
            BackupRestorePreviewSheet(service: service, backup: backup)
        }
        .sheet(isPresented: $showingShareSheet) {
            #if os(iOS)
            if let exportUrl = backupToExport?.url {
                ShareSheet(activityItems: [exportUrl])
            } else {
                EmptyView()
            }
            #else
            EmptyView()
            #endif
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("¿Eliminar copia de seguridad?"),
                message: Text("Esta acción es irreversible y se perderán los datos contenidos en esta copia de seguridad."),
                primaryButton: .destructive(Text("Eliminar")) {
                    if let backup = backupToDelete {
                        Task {
                            try? await service.deleteBackup(backup)
                        }
                    }
                },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
    }
    
    private func triggerExport(_ backup: AppleBackupDescriptor) {
        #if os(iOS)
        self.backupToExport = backup
        self.showingShareSheet = true
        #else
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.directory]
        panel.nameFieldStringValue = backup.url.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let targetURL = panel.url {
            Task {
                try? await service.exportBackup(backup, to: targetURL)
            }
        }
        #endif
    }
}

// MARK: - BackupRowView
struct BackupRowView: View {
    let backup: AppleBackupDescriptor
    var onVerify: () -> Void
    var onRestore: () -> Void
    var onExport: () -> Void
    var onDelete: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        PremiumCard.section {
            VStack(alignment: .leading, spacing: 14) {
                // Top Header Row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(backup.displayName)
                            .font(IOSAppStyle.cardTitle)
                            .lineLimit(2)
                        
                        Text("\(backup.manifest.createdAt.formattedDateText) · \(backup.manifest.platform) (\(backup.manifest.deviceName))")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Verification Status Badge
                    HStack(spacing: 4) {
                        if backup.isVerified {
                            if backup.verificationError != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(IOSAppStyle.danger)
                                Text("Corrupta")
                                    .font(IOSAppStyle.captionText)
                                    .foregroundStyle(IOSAppStyle.danger)
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(IOSAppStyle.success)
                                Text("Válida")
                                    .font(IOSAppStyle.captionText)
                                    .foregroundStyle(IOSAppStyle.success)
                            }
                        } else {
                            Image(systemName: "questionmark.shield")
                                .foregroundStyle(.secondary)
                            Text("Sin verificar")
                                .font(IOSAppStyle.captionText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                backup.isVerified
                                    ? (backup.verificationError != nil ? IOSAppStyle.danger.opacity(0.12) : IOSAppStyle.success.opacity(0.12))
                                    : Color.secondary.opacity(0.12)
                            )
                    )
                }
                
                // Summary Counts
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            CountPill(label: "Clases", count: backup.manifest.summary.classCount, systemImage: "folder")
                            CountPill(label: "Alumnos", count: backup.manifest.summary.studentCount, systemImage: "person.3")
                            CountPill(label: "Columnas", count: backup.manifest.summary.notebookColumnCount, systemImage: "tablecells")
                            CountPill(label: "Rúbricas", count: backup.manifest.summary.rubricCount, systemImage: "doc.plaintext")
                            CountPill(label: "Asistencias", count: backup.manifest.summary.attendanceRecordCount, systemImage: "checkmark.circle")
                        }
                    }
                }
                
                Divider()
                
                // Action Buttons
                HStack(spacing: 12) {
                    Text(backup.sizeText)
                        .font(IOSAppStyle.captionText)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button(action: onVerify) {
                        Label("Validar", systemImage: "shield.checkerboard")
                            .font(IOSAppStyle.captionText)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Validar copia")
                    
                    Button(action: onExport) {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                            .font(IOSAppStyle.captionText)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Exportar copia")
                    
                    Button(action: onRestore) {
                        Label("Restaurar", systemImage: "arrow.clockwise.to.line")
                            .font(IOSAppStyle.captionText.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Restaurar copia")
                }
            }
        }
        .contextMenu {
            Button(action: onVerify) {
                Label("Validar Integridad", systemImage: "shield.checkerboard")
            }
            Button(action: onExport) {
                Label("Compartir/Exportar", systemImage: "square.and.arrow.up")
            }
            Button(action: onRestore) {
                Label("Restaurar", systemImage: "arrow.clockwise.to.line")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

// MARK: - CountPill
struct CountPill: View {
    let label: String
    let count: Int
    let systemImage: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - iOS ShareSheet Representable
#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Local Date Formatter Helper
extension Date {
    fileprivate var formattedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: self)
    }
}
