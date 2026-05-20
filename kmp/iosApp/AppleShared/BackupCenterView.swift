import SwiftUI

struct BackupCenterView: View {
    @StateObject private var service = AppleBackupService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            BackupBackdrop()
            
            ScrollView {
                VStack(alignment: .leading, spacing: AppleDesignSystem.sectionSpacing) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MÓDULO DE SEGURIDAD")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(AppleDesignSystem.accent)
                        
                        Text("Copias de Seguridad")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Protege, valida y restaura tus datos locales de forma segura.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    // Error Banner if any
                    if let error = service.lastError {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(AppleDesignSystem.danger)
                                .font(.title3)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Button(action: { service.lastError = nil }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(AppleDesignSystem.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: AppleDesignSystem.controlRadius).stroke(AppleDesignSystem.danger.opacity(0.18), lineWidth: 1))
                    }
                    
                    // Status Hero (Protected Card)
                    BackupStatusHero(service: service)
                    
                    // History Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Copias Guardadas")
                            .font(.title3.weight(.bold))
                            .padding(.horizontal, 4)
                        
                        BackupHistoryList(service: service)
                    }
                }
                .padding(AppleDesignSystem.pagePadding)
            }
        }
        .navigationTitle("Copias de Seguridad")
        .appInlineNavigationBarTitleDisplayMode()
        .task {
            await service.scanBackups()
        }
    }
}

// MARK: - Safe Cross-Platform Backdrop
struct BackupBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            appPageBackground(for: colorScheme)
            
            // Glowing mesh design bubbles
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppleDesignSystem.accent.opacity(colorScheme == .dark ? 0.08 : 0.04), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: -180, y: -220)
                .blur(radius: 40)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(colorScheme == .dark ? 0.06 : 0.03), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: 180, y: 260)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
    }
}
