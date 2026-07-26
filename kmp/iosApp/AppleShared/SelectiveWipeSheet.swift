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
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Borrado modular y personalizado", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Selecciona únicamente la información que deseas eliminar. Los elementos no marcados se mantendrán intactos en tu base de datos.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Copia de seguridad previa") {
                    Toggle(isOn: $createEmergencyBackup) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Guardar copia de seguridad automática")
                                .font(.body.weight(.medium))
                            Text("Genera una copia en disco (.sqlite) inmediatamente antes de proceder al borrado")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.blue)

                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkmark.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Tus copias de seguridad en disco nunca se borrarán desde esta pantalla.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Presets de selección rápida") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("Solo Cursos y Notas") {
                                selectedCategories = [.classes]
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            Button("Todo excepto Rúbricas y SA") {
                                selectedCategories = Set(allCategories).subtracting([.rubrics, .learningSituations])
                            }
                            .buttonStyle(.bordered)
                            .tint(.purple)

                            Button("Seleccionar todo") {
                                selectedCategories = Set(allCategories)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)

                            Button("Desmarcar todo") {
                                selectedCategories.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Categorías de información") {
                    ForEach(allCategories, id: \.self) { category in
                        let isSelected = selectedCategories.contains(category)
                        Button {
                            if isSelected {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(isSelected ? .red : .gray)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(category.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(isSelected ? "Se eliminará" : "Se conservará")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(isSelected ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                                            .foregroundColor(isSelected ? .red : .green)
                                            .cornerRadius(6)
                                    }

                                    Text(category.description_)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmationText = ""
                        showingConfirmationAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Procesando borrado...")
                            } else {
                                Label(
                                    selectedCategories.isEmpty ? "Selecciona al menos una categoría" : "Eliminar \(selectedCategories.count) categoría\(selectedCategories.count == 1 ? "" : "s")",
                                    systemImage: "trash.fill"
                                )
                                .font(.body.weight(.bold))
                            }
                            Spacer()
                        }
                    }
                    .disabled(selectedCategories.isEmpty || isProcessing)
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
                    dismiss()
                })
            }
        }
    }

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
                statusFeedback = "El borrado selectivo se ha completado correctamente."
            } catch {
                backupService.needsRestart = false
                statusFeedback = "Error durante el borrado: \(error.localizedDescription)"
            }
            isProcessing = false
        }
    }
}
