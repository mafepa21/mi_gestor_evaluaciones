import SwiftUI

struct BackupCenterView: View {
    @StateObject private var service = AppleBackupService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BackupBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {

                    // MARK: Page Header
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

                    // MARK: Error Banner
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
                        .background(
                            IOSAppStyle.danger.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius)
                                .stroke(IOSAppStyle.danger.opacity(0.18), lineWidth: 1)
                        )
                    }

                    // MARK: Status Hero
                    BackupStatusHero(service: service)

                    // MARK: Quick Actions Bar
                    BackupActionsBar(service: service)

                    // MARK: Security Summary Card
                    BackupSecurityCard(service: service)

                    // MARK: History
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Copias Guardadas")
                                .font(IOSAppStyle.sectionTitle)
                            Spacer()
                            if service.operationState == .scanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
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

// MARK: - Quick Actions Bar

struct BackupActionsBar: View {
    @ObservedObject var service: AppleBackupService
    @State private var showCreateSheet = false
    @State private var backupNote = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Crear — siempre disponible
                BackupActionChip(
                    label: service.operationState == .creating ? "Creando…" : "Crear copia",
                    systemImage: "plus.shield.fill",
                    tint: IOSAppStyle.info,
                    style: .primary,
                    isLoading: service.operationState == .creating
                ) {
                    backupNote = ""
                    showCreateSheet = true
                }
                .disabled(service.operationState == .creating)

                // Verificar todo
                BackupActionChip(
                    label: service.operationState == .verifying ? "Verificando…" : "Verificar todo",
                    systemImage: "shield.checkerboard",
                    tint: IOSAppStyle.success,
                    style: .secondary,
                    isLoading: service.operationState == .verifying
                ) {
                    Task {
                        for backup in service.backups {
                            _ = await service.verifyBackup(backup)
                        }
                    }
                }
                .disabled(service.backups.isEmpty || service.operationState == .verifying)

                // Escanear
                BackupActionChip(
                    label: "Actualizar lista",
                    systemImage: "arrow.clockwise",
                    tint: .secondary,
                    style: .ghost
                ) {
                    Task { await service.scanBackups() }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateBackupSheet(isPresented: $showCreateSheet, note: $backupNote) {
                Task {
                    let finalNote = backupNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try? await service.createBackup(note: finalNote.isEmpty ? nil : finalNote)
                }
            }
        }
    }
}

// MARK: - Action Chip

private enum BackupChipStyle { case primary, secondary, ghost }

private struct BackupActionChip: View {
    let label: String
    let systemImage: String
    let tint: Color
    var style: BackupChipStyle = .secondary
    var isLoading: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(style == .primary ? .white : tint)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(style == .primary ? .white : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous)
                    .fill(style == .primary
                          ? tint
                          : (style == .secondary ? tint.opacity(0.12) : IOSAppStyle.subtleFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous)
                            .stroke(tint.opacity(style == .ghost ? 0.1 : 0.2), lineWidth: 1)
                    )
                    .shadow(
                        color: (style == .primary ? tint : Color.clear).opacity(0.25),
                        radius: 6, x: 0, y: 3
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Security Card

struct BackupSecurityCard: View {
    @ObservedObject var service: AppleBackupService

    private var totalSizeText: String {
        let total = service.backups.reduce(0) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private var verifiedCount: Int {
        service.backups.filter { $0.isVerified && $0.verificationError == nil }.count
    }

    var body: some View {
        PremiumCard.section(title: "Estado de seguridad", systemImage: "lock.shield.fill") {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                SecurityMetric(
                    title: "Copias",
                    value: "\(service.backups.count)",
                    systemImage: "archivebox.fill",
                    tint: IOSAppStyle.info
                )
                SecurityMetric(
                    title: "Verificadas",
                    value: "\(verifiedCount)",
                    systemImage: "checkmark.shield.fill",
                    tint: IOSAppStyle.success
                )
                SecurityMetric(
                    title: "Tamaño total",
                    value: totalSizeText,
                    systemImage: "internaldrive.fill",
                    tint: .purple
                )
            }
        }
    }
}

private struct SecurityMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
    }
}

// MARK: - Backdrop (unchanged)

struct BackupBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            IOSAppStyle.pageBackground

            Circle()
                .fill(
                    RadialGradient(
                        colors: [IOSAppStyle.info.opacity(colorScheme == .dark ? 0.08 : 0.04), .clear],
                        center: .center, startRadius: 0, endRadius: 260
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: -180, y: -220)
                .blur(radius: 40)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(colorScheme == .dark ? 0.06 : 0.03), .clear],
                        center: .center, startRadius: 0, endRadius: 220
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: 180, y: 260)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
    }
}
