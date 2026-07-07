import SwiftUI

struct BackupRestorePreviewSheet: View {
    @ObservedObject var service: AppleBackupService
    let backup: AppleBackupDescriptor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var currentSummary: AppleBackupSummary?
    @State private var restoreStep: RestoreStep = .preview
    @State private var errorMessage: String? = nil
    
    enum RestoreStep {
        case preview
        case restoring(stepName: String, progress: Double)
        case completed
        case failed
    }

    var body: some View {
        #if os(macOS)
        mainContent
            .frame(width: 580, height: 480)
            .padding()
        #else
        NavigationStack {
            mainContent
                .navigationTitle("Restaurar copia")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if case .preview = restoreStep {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { dismiss() }
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            switch restoreStep {
            case .preview:
                previewView
            case .restoring(let stepName, let progress):
                restoringProgressView(stepName: stepName, progress: progress)
            case .completed:
                completedView
            case .failed:
                failedView
            }
        }
        .padding()
        .background(AppleDesignSystem.pageBackground(for: colorScheme))
        .onAppear {
            self.currentSummary = service.getCurrentDatabaseSummary()
        }
    }
    
    // MARK: - Subviews
    
    private var previewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Warning Banner
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(AppleDesignSystem.danger)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("ATENCIÓN: Reemplazo de datos")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppleDesignSystem.danger)
                    Text("Esta acción reemplazará toda tu base de datos actual. Crearemos una copia de seguridad de emergencia automática antes de proceder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(AppleDesignSystem.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius).stroke(AppleDesignSystem.danger.opacity(0.2), lineWidth: 1))
            
            Text("Comparación de datos:")
                .font(.headline)
            
            // Side-by-side comparison tables
            if let current = currentSummary {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ComparisonCard(title: "Base de Datos Actual", summary: current, isBackup: false)

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppleDesignSystem.accent)

                        ComparisonCard(title: "Copia a Restaurar", summary: backup.manifest.summary, isBackup: true)
                    }

                    VStack(spacing: 12) {
                        ComparisonCard(title: "Base de Datos Actual", summary: current, isBackup: false)

                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppleDesignSystem.accent)

                        ComparisonCard(title: "Copia a Restaurar", summary: backup.manifest.summary, isBackup: true)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 120)
            }
            
            Spacer()
            
            HStack {
                #if os(macOS)
                Button("Cancelar") { dismiss() }
                #endif
                Spacer()
                Button(action: startRestoration) {
                    HStack {
                        Image(systemName: "arrow.clockwise.to.line")
                            .font(.system(size: 14, weight: .bold))
                        Text("Confirmar y Restaurar")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(contrastingTextColor(for: AppleDesignSystem.accent))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius, style: .continuous)
                            .fill(AppleDesignSystem.accent)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func restoringProgressView(stepName: String, progress: Double) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(AppleDesignSystem.accent.opacity(0.12), lineWidth: 8)
                    .frame(width: 88, height: 88)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(progress))
                    .stroke(AppleDesignSystem.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 88, height: 88)
                    .rotationEffect(Angle(degrees: -90))
                    .animation(.easeInOut, value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
            }
            
            VStack(spacing: 8) {
                Text("Restaurando copia...")
                    .font(.title3.weight(.bold))
                
                Text(stepName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 44)
            }
            
            Spacer()
        }
    }
    
    private var completedView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppleDesignSystem.success.opacity(0.12))
                    .frame(width: 88, height: 88)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppleDesignSystem.success)
            }
            
            VStack(spacing: 8) {
                Text("¡Restauración Completada!")
                    .font(.title3.weight(.bold))
                
                Text("Los datos se han reemplazado con éxito.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let emergencyUrl = service.latestEmergencyBackupUrl {
                    Text("Copia de emergencia creada en: \n\(emergencyUrl.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)
            
            Spacer()
            
            // Critical Restart Notice
            VStack(alignment: .leading, spacing: 8) {
                Text("Reinicio obligatorio requerido")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppleDesignSystem.warning)
                
                Text("Para cargar la nueva base de datos sin corrupción de memoria en KMP, la aplicación debe cerrarse e iniciarse nuevamente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(AppleDesignSystem.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius).stroke(AppleDesignSystem.warning.opacity(0.2), lineWidth: 1))
            
            Button(action: quitApp) {
                Text("Entendido (Cerrar aplicación)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(contrastingTextColor(for: AppleDesignSystem.accent))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius, style: .continuous)
                            .fill(AppleDesignSystem.accent)
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var failedView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppleDesignSystem.danger.opacity(0.12))
                    .frame(width: 88, height: 88)
                
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppleDesignSystem.danger)
            }
            
            VStack(spacing: 8) {
                Text("Fallo en la restauración")
                    .font(.title3.weight(.bold))
                
                Text(errorMessage ?? "Error desconocido.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button("Cerrar") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    // MARK: - Actions
    
    private func startRestoration() {
        Task {
            do {
                // Step 1: Validate
                restoreStep = .restoring(stepName: "Validando integridad del archivo...", progress: 0.15)
                try await Task.sleep(nanoseconds: 500_000_000) // Visual timing
                let verified = await service.verifyBackup(backup)
                guard verified.isVerified else {
                    throw NSError(domain: "Restoration", code: 1, userInfo: [NSLocalizedDescriptionKey: verified.verificationError ?? "Fallo de validación."])
                }
                
                // Step 2: Emergency Backup
                restoreStep = .restoring(stepName: "Creando copia de seguridad de emergencia...", progress: 0.45)
                try await Task.sleep(nanoseconds: 500_000_000)
                
                // Step 3: File copy and overwrite
                restoreStep = .restoring(stepName: "Reemplazando archivos de base de datos y adjuntos...", progress: 0.80)
                try await Task.sleep(nanoseconds: 500_000_000)
                
                // Execute actual restoration
                try await service.restoreBackup(backup)
                
                restoreStep = .completed
            } catch {
                self.errorMessage = error.localizedDescription
                restoreStep = .failed
            }
        }
    }
    
    private func quitApp() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #else
        exit(0)
        #endif
    }
}

// MARK: - ComparisonCard Helper
struct ComparisonCard: View {
    let title: String
    let summary: AppleBackupSummary
    let isBackup: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            VStack(alignment: .leading, spacing: 6) {
                StatCompareRow(label: "Clases", value: summary.classCount)
                StatCompareRow(label: "Alumnos", value: summary.studentCount)
                StatCompareRow(label: "Columnas", value: summary.notebookColumnCount)
                StatCompareRow(label: "Rúbricas", value: summary.rubricCount)
                StatCompareRow(label: "Asistencias", value: summary.attendanceRecordCount)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isBackup ? AppleDesignSystem.accent.opacity(0.04) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isBackup ? AppleDesignSystem.accent.opacity(0.12) : AppleDesignSystem.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatCompareRow: View {
    let label: String
    let value: Int
    
    var body: some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}
