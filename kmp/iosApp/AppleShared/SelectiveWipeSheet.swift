import SwiftUI
import MiGestorKit
#if os(macOS)
import AppKit
#endif

struct SelectiveWipeSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategories: Set<WipeCategory> = [.classes]
    @State private var createEmergencyBackup: Bool = true
    @State private var showingConfirmationAlert: Bool = false
    @State private var confirmationText: String = ""
    @State private var isProcessing: Bool = false
    @State private var isRestarting: Bool = false
    @State private var statusFeedback: String? = nil

    private var allCategories: [WipeCategory] {
        let vals = WipeCategory.values()
        var list: [WipeCategory] = []
        for i in 0..<vals.size {
            if let cat = vals.get(index: i) as? WipeCategory {
                list.append(cat)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header Banner
                        headerBanner

                        // Card: Backup Previsto
                        backupSectionCard

                        // Card: Presets Rápidos
                        presetsSectionCard

                        // Card: Categorías
                        categoriesSectionCard
                    }
                    .padding(20)
                }

                if isProcessing || isRestarting {
                    processingOverlay
                }
            }
            .navigationTitle("Borrado Seleccionable")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .disabled(isProcessing || isRestarting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        confirmationText = ""
                        showingConfirmationAlert = true
                    } label: {
                        Text(selectedCategories.isEmpty ? "Eliminar" : "Eliminar (\(selectedCategories.count))")
                            .bold()
                    }
                    .disabled(selectedCategories.isEmpty || isProcessing || isRestarting)
                }
            }
            .alert("Confirmar borrado selectivo", isPresented: $showingConfirmationAlert) {
                TextField("Escribe BORRAR", text: $confirmationText)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .autocorrectionDisabled(true)

                Button("Confirmar Borrado", role: .destructive) {
                    if confirmationText == "BORRAR" {
                        executeSelectiveWipe()
                    } else {
                        statusFeedback = "El texto introducido no es correcto."
                    }
                    confirmationText = ""
                }
                Button("Cancelar", role: .cancel) {
                    confirmationText = ""
                }
            } message: {
                Text("Se eliminarán las siguientes categorías: \(selectedCategories.map { $0.displayName }.joined(separator: ", ")).\n\n\(createEmergencyBackup ? "Se creará una copia de seguridad automática antes de proceder." : "No has seleccionado copia de seguridad previa.")\n\nEscribe 'BORRAR' en mayúsculas para continuar.")
            }
            .alert(item: Binding(
                get: { statusFeedback.map { IdentifiableString(value: $0) } },
                set: { statusFeedback = $0?.value }
            )) { message in
                Alert(title: Text("Aviso"), message: Text(message.value), dismissButton: .default(Text("OK")) {
                    if !isRestarting {
                        dismiss()
                    }
                })
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 660, idealHeight: 740)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Subviews

    private var headerBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Borrado modular y personalizado")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Text("Selecciona únicamente la información que deseas eliminar. Los elementos no marcados se mantendrán intactos.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var backupSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $createEmergencyBackup) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Guardar copia de seguridad automática previa")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)

                    Text("Genera una copia completa en disco (.sqlite) inmediatamente antes de aplicar el borrado.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Tus copias de seguridad en disco nunca se borrarán desde esta pantalla.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var presetsSectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets de selección rápida")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button {
                    selectedCategories = [.classes]
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.minus")
                        Text("Solo Cursos y Notas")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    selectedCategories = Set(allCategories).subtracting([.rubrics, .learningSituations])
                } label: {
                    HStack {
                        Image(systemName: "bookmark.slash")
                        Text("Todo menos Rúbricas y SA")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.purple)

                Button {
                    selectedCategories = Set(allCategories)
                } label: {
                    HStack {
                        Image(systemName: "checkmark.square.stack.fill")
                        Text("Seleccionar Todo")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    selectedCategories.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "square.dashed")
                        Text("Desmarcar Todo")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
    }

    private var categoriesSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categorías de información (\(allCategories.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                ForEach(allCategories, id: \.self) { category in
                    let isSelected = selectedCategories.contains(category)
                    Button {
                        if isSelected {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundColor(isSelected ? .red : .secondary.opacity(0.5))
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(category.displayName)
                                        .font(.body.weight(.bold))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text(isSelected ? "Se eliminará" : "Se conservará")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                                        )
                                        .foregroundColor(isSelected ? .red : .green)
                                }

                                Text(category.description_)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.red.opacity(0.04) : Color.primary.opacity(0.02))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? Color.red.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)

                Text(isRestarting ? "Reiniciando aplicación..." : "Ejecutando borrado selectivo...")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(isRestarting ? "La app se relanzará automáticamente en unos segundos." : "Guardando estado y limpiando tablas seleccionadas...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    #if os(macOS)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                    #else
                    .fill(Color(UIColor.systemBackground).opacity(0.95))
                    #endif
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
        }
    }

    // MARK: - Logic & Auto-Restart

    private func executeSelectiveWipe() {
        isProcessing = true
        Task { @MainActor in
            let backupService = AppleBackupService.shared

            // 0. Marcar reinicio preventivo
            backupService.needsRestart = true

            // 1. Parar background sync
            bridge.stopBackgroundSyncWork()
            await bridge.unpairLanSync()

            #if os(macOS)
            NotificationCenter.default.post(name: .appleCommandCenterStopRequested, object: nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            #endif

            // 2. Si se solicitó backup previo automático, crearlo antes de borrar
            if createEmergencyBackup {
                let _ = try? await backupService.createBackup(note: "Copia previa a borrado selectivo")
            }

            // 3. Ejecutar vaciado SQL por categorías
            do {
                try bridge.wipeSelectiveDatabaseData(categories: selectedCategories)

                #if os(macOS)
                isProcessing = false
                isRestarting = true
                scheduleAutomaticRelaunch()
                #else
                isProcessing = false
                statusFeedback = "El borrado selectivo se ha completado correctamente."
                #endif
            } catch {
                backupService.needsRestart = false
                isProcessing = false
                statusFeedback = "Error durante el borrado: \(error.localizedDescription)"
            }
        }
    }

    #if os(macOS)
    private func scheduleAutomaticRelaunch() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }
    #endif
}
