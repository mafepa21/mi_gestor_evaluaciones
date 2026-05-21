import SwiftUI

struct BackupCenterView: View {
    @StateObject private var service = AppleBackupService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            BackupBackdrop()
            
            ScrollView {
                VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MÓDULO DE SEGURIDAD")
                            .font(IOSAppStyle.captionText)
                            .tracking(1.2)
                            .foregroundStyle(IOSAppStyle.info)
                        
                        Text("Copias de Seguridad")
                            .font(IOSAppStyle.pageTitle)
                            .foregroundStyle(.primary)
                        
                        Text("Protege, valida y restaura tus datos locales de forma segura.")
                            .font(IOSAppStyle.bodyText)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    // Error Banner if any
                    if let error = service.lastError {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(IOSAppStyle.danger)
                                .font(.title3)
                            
                            Text(error)
                                .font(IOSAppStyle.bodyText)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Button(action: { service.lastError = nil }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(IOSAppStyle.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius).stroke(IOSAppStyle.danger.opacity(0.18), lineWidth: 1))
                    }
                    
                    // Status Hero (Protected Card)
                    BackupStatusHero(service: service)
                    
                    // History Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Copias Guardadas")
                            .font(IOSAppStyle.sectionTitle)
                            .padding(.horizontal, 4)
                        
                        BackupHistoryList(service: service)
                    }
                }
                .padding(IOSAppStyle.pagePadding)
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
            IOSAppStyle.pageBackground
            
            // Glowing mesh design bubbles
            Circle()
                .fill(
                    RadialGradient(
                        colors: [IOSAppStyle.info.opacity(colorScheme == .dark ? 0.08 : 0.04), .clear],
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
