import SwiftUI
import UniformTypeIdentifiers

struct BackupCenterView: View {
    @StateObject private var service = AppleBackupService.shared

    @State private var searchText = ""
    @State private var backupForRestore: AppleBackupDescriptor?
    @State private var backupToExport: AppleBackupDescriptor?
    @State private var backupToDelete: AppleBackupDescriptor?

    @State private var showCreateSheet = false
    @State private var backupNote = ""

    @State private var showImportPicker = false
    @State private var importSelection: ApplePortableBackupImportSelection?
    @State private var importError: String?

    private var filteredBackups: [AppleBackupDescriptor] {
        service.backups.filter { $0.matches(search: searchText) }
    }

    private var isBusy: Bool {
        switch service.operationState {
        case .creating, .importing, .verifying, .restoring: return true
        default: return false
        }
    }

    private var isInitialScan: Bool {
        service.operationState == .scanning && service.backups.isEmpty
    }

    var body: some View {
        List {
            if let error = service.lastError {
                Section { errorRow(error) }
            }

            if !service.backups.isEmpty {
                Section {
                    BackupStatusSummary(service: service, detailOverride: summaryDetail)
                }
            }

            if isInitialScan {
                Section("Hoy") {
                    ForEach(0..<3, id: \.self) { _ in BackupPlaceholderRow() }
                }
            } else {
                let groups = BackupDayGroup.groups(from: filteredBackups)
                ForEach(groups) { group in
                    Section {
                        ForEach(group.backups) { backup in
                            BackupRowView(
                                backup: backup,
                                onOpen: { backupForRestore = backup },
                                onVerify: { Task { _ = await service.verifyBackup(backup) } },
                                onExport: { backupToExport = backup },
                                onDelete: { backupToDelete = backup }
                            )
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group.id == groups.first?.id {
                            Text("Pulsa una copia para ver qué contiene antes de restaurarla.")
                        }
                    }
                }
            }
        }
        .backupCenterListStyle()
        .overlay { emptyState }
        .searchable(text: $searchText, prompt: "Buscar copias")
        .refreshable { await service.scanBackups() }
        .navigationTitle("Copias de seguridad")
        .appInlineNavigationBarTitleDisplayMode()
        .toolbar { toolbarContent }
        .task { await service.scanBackups() }
        .sheet(isPresented: $showCreateSheet) {
            CreateBackupSheet(isPresented: $showCreateSheet, note: $backupNote) {
                let finalNote = backupNote.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await service.createBackup(note: finalNote.isEmpty ? nil : finalNote)
            }
        }
        .sheet(item: $backupForRestore) { backup in
            BackupRestorePreviewSheet(service: service, backup: backup)
        }
        .sheet(item: $backupToExport) { backup in
            EncryptedBackupExportSheet(backup: backup) { destinationURL, password in
                try await service.exportEncryptedBackup(backup, to: destinationURL, password: password)
            }
        }
        .sheet(item: $importSelection) { selection in
            PortableBackupImportSheet(selection: selection) { url, password in
                _ = try await service.importPortableBackup(from: url, password: password)
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.miGestorEncryptedBackup, .miGestorLegacyBackup, .folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let hasSecurityScope = url.startAccessingSecurityScopedResource()
                defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
                let format = try ApplePortableBackupFormat.detect(at: url)
                importSelection = ApplePortableBackupImportSelection(url: url, format: format)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert(
            "No se pudo abrir la copia",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("Aceptar", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "Error desconocido")
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { backupToDelete != nil },
                set: { if !$0 { backupToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: backupToDelete
        ) { backup in
            Button("Eliminar", role: .destructive) {
                Task { try? await service.deleteBackup(backup) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { backup in
            Text("\(backup.sizeText). No se puede deshacer.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button {
                    Task {
                        for backup in service.backups {
                            _ = await service.verifyBackup(backup)
                        }
                    }
                } label: {
                    Label("Validar todas", systemImage: "checkmark.shield")
                }
                .disabled(service.backups.isEmpty || isBusy)

                Button {
                    Task { await service.scanBackups() }
                } label: {
                    Label("Actualizar lista", systemImage: "arrow.clockwise")
                }
            } label: {
                Label("Más", systemImage: "ellipsis.circle")
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Importar copia", systemImage: "square.and.arrow.down")
            }
            .disabled(isBusy)
            .help("Importar copia")

            Button {
                backupNote = ""
                showCreateSheet = true
            } label: {
                Label("Crear copia", systemImage: "plus")
            }
            .disabled(isBusy)
            .help("Crear copia")
        }
    }

    // MARK: - Partes

    private var summaryDetail: String {
        let total = service.backups.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        let count = service.backups.count
        var text = "\(count) \(count == 1 ? "copia" : "copias") · \(size) en este dispositivo"
        let validated = service.backups.filter(\.isValidated).count
        if validated > 0 {
            text += " · \(validated) \(validated == 1 ? "validada" : "validadas")"
        }
        return text
    }

    private var deleteTitle: String {
        guard let backup = backupToDelete else { return "¿Eliminar esta copia?" }
        return "¿Eliminar la copia del \(backup.longDateText)?"
    }

    private func errorRow(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(error)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Reintentar") {
                service.lastError = nil
                Task { await service.scanBackups() }
            }
            Button {
                service.lastError = nil
            } label: {
                Label("Cerrar aviso", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var emptyState: some View {
        if service.backups.isEmpty && !isInitialScan && service.lastError == nil {
            ContentUnavailableView {
                Label("Aún no hay copias", systemImage: "externaldrive")
            } description: {
                Text("Crea la primera para proteger tu cuaderno, alumnado y rúbricas.")
            } actions: {
                Button("Crear copia") {
                    backupNote = ""
                    showCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
                Button("Importar…") { showImportPicker = true }
            }
        } else if !service.backups.isEmpty && filteredBackups.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

private extension View {
    @ViewBuilder
    func backupCenterListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.insetGrouped)
        #endif
    }
}
