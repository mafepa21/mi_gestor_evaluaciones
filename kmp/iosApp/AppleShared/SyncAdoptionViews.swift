import SwiftUI
import MiGestorKit

// MARK: - Banner de Divergencia de Sincronización

public struct SyncDivergenceBanner: View {
    let divergence: SyncDivergenceReport
    @State private var showingAdoptionSheet = false

    public init(divergence: SyncDivergenceReport) {
        self.divergence = divergence
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: divergence.isSchemaMismatch ? "exclamationmark.octagon.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title2)
                    .foregroundStyle(divergence.isSchemaMismatch ? Color.red : Color.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(divergence.isSchemaMismatch ? "Versiones de app incompatibles" : "Diferencia de datos detectada")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !divergence.isSchemaMismatch {
                    Button {
                        showingAdoptionSheet = true
                    } label: {
                        Text("Igualar…")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(divergence.isSchemaMismatch ? Color.red.opacity(0.1) : Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(divergence.isSchemaMismatch ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showingAdoptionSheet) {
            SyncAdoptionSheet(divergence: divergence)
        }
    }

    private var summaryText: String {
        switch divergence.kind {
        case let .schemaMismatch(local, remote):
            return "El esquema local es v\(local) y el remoto es v\(remote). Actualiza ambas apps a la misma versión."
        case .datasetDifference:
            let localClasses = divergence.localFingerprint.countsByEntity["class"] ?? 0
            let remoteClasses = divergence.remoteFingerprint.countsByEntity["class"] ?? 0
            let localStudents = divergence.localFingerprint.countsByEntity["student"] ?? 0
            let remoteStudents = divergence.remoteFingerprint.countsByEntity["student"] ?? 0

            if localClasses != remoteClasses {
                return "Diferencia en clases (\(localClasses) aquí, \(remoteClasses) en el otro dispositivo). Se recomienda igualar."
            } else if localStudents != remoteStudents {
                return "Diferencia en alumnado (\(localStudents) aquí, \(remoteStudents) en el otro dispositivo). Se recomienda igualar."
            } else {
                let count = divergence.divergentEntities.count
                return "Hay \(count) entidad\(count == 1 ? "" : "es") con contenidos diferentes entre dispositivos."
            }
        }
    }
}

// MARK: - Hoja de Adopción de Dataset ("Igualar dispositivos")

public struct SyncAdoptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bridge: KmpBridge

    let divergence: SyncDivergenceReport?

    @State private var localFp: LanDatasetFingerprint?
    @State private var remoteFp: LanDatasetFingerprint?
    @State private var selectedSource: KmpBridge.SyncAdoptionSource? = nil
    @State private var step: AdoptionStep = .compare
    @State private var isProcessing = false
    @State private var progressMessage = ""
    @State private var errorMessage: String? = nil
    @State private var backupPathResult: String? = nil
    @State private var needsRestartHint: String? = nil

    private enum AdoptionStep {
        case compare
        case choose
        case confirm
        case completed
    }

    public init(divergence: SyncDivergenceReport? = nil) {
        self.divergence = divergence
        _localFp = State(initialValue: divergence?.localFingerprint)
        _remoteFp = State(initialValue: divergence?.remoteFingerprint)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case .compare:
                            compareStepView
                        case .choose:
                            chooseStepView
                        case .confirm:
                            confirmStepView
                        case .completed:
                            completedStepView
                        }
                    }
                    .padding(20)
                }

                Divider()

                bottomBarView
                    .padding(16)
                    .background(.bar)
            }
            .navigationTitle("Igualar dispositivos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .completed && !isProcessing {
                        Button("Cancelar") {
                            dismiss()
                        }
                    }
                }
            }
            .task {
                if localFp == nil || remoteFp == nil {
                    await refreshFingerprints()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    // MARK: - Paso 1: Comparativa

    private var compareStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Comparación del estado actual")
                    .font(.title2.weight(.bold))
                Text("Revisa las diferencias entre este dispositivo y el dispositivo emparejado antes de decidir cuál conservar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let local = localFp, let remote = remoteFp {
                HStack(alignment: .top, spacing: 16) {
                    deviceDatasetCard(
                        title: thisDeviceTitle,
                        subtitle: "Este dispositivo",
                        systemImage: thisDeviceIcon,
                        fingerprint: local,
                        tint: .blue
                    )

                    deviceDatasetCard(
                        title: pairedDeviceTitle,
                        subtitle: "Emparejado por LAN",
                        systemImage: pairedDeviceIcon,
                        fingerprint: remote,
                        tint: .purple
                    )
                }

                entitiesComparisonTable(local: local, remote: remote)
            } else {
                HStack {
                    Spacer()
                    ProgressView("Calculando huella de integridad de ambos dispositivos…")
                        .padding(40)
                    Spacer()
                }
            }
        }
    }

    private func deviceDatasetCard(
        title: String,
        subtitle: String,
        systemImage: String,
        fingerprint: LanDatasetFingerprint,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 6) {
                metricRow(label: "Clases", count: fingerprint.countsByEntity["class"] ?? 0)
                metricRow(label: "Alumnado", count: fingerprint.countsByEntity["student"] ?? 0)
                metricRow(label: "Evaluaciones", count: fingerprint.countsByEntity["evaluation"] ?? 0)
                metricRow(label: "Notas", count: fingerprint.countsByEntity["grade"] ?? 0)
                metricRow(label: "Situaciones de aprendizaje", count: fingerprint.countsByEntity["learning_situation"] ?? 0)
            }

            Divider()

            HStack {
                Text("Digest:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(fingerprint.digest.prefix(8) + "…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.adoptionCardBackground)
        )
    }

    private func metricRow(label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func entitiesComparisonTable(local: LanDatasetFingerprint, remote: LanDatasetFingerprint) -> some View {
        let keys = ["class", "student", "evaluation", "grade", "notebook_tab", "notebook_column", "teaching_unit", "learning_situation", "planning_session"]
        let titles: [String: String] = [
            "class": "Clases",
            "student": "Alumnado",
            "evaluation": "Evaluaciones",
            "grade": "Calificaciones",
            "notebook_tab": "Pestañas cuaderno",
            "notebook_column": "Columnas cuaderno",
            "teaching_unit": "Unidades didácticas",
            "learning_situation": "Situaciones aprendizaje",
            "planning_session": "Sesiones agendadas"
        ]

        return VStack(alignment: .leading, spacing: 8) {
            Text("Detalle por entidad")
                .font(.headline)

            VStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    let lCount = local.countsByEntity[key] ?? 0
                    let rCount = remote.countsByEntity[key] ?? 0
                    let isDivergent = lCount != rCount

                    HStack {
                        Text(titles[key] ?? key)
                            .font(.subheadline)
                            .foregroundStyle(isDivergent ? .primary : .secondary)

                        Spacer()

                        Text("\(lCount)")
                            .font(.subheadline.weight(isDivergent ? .bold : .regular))
                            .foregroundStyle(isDivergent ? Color.blue : Color.secondary)

                        Text("vs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("\(rCount)")
                            .font(.subheadline.weight(isDivergent ? .bold : .regular))
                            .foregroundStyle(isDivergent ? Color.purple : Color.secondary)

                        if isDivergent {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(isDivergent ? Color.orange.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.adoptionTertiaryBackground)
        )
    }

    // MARK: - Paso 2: Elección

    private var chooseStepView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("¿Qué datos deseas mantener?")
                    .font(.title2.weight(.bold))
                Text("Selecciona el dispositivo que actuará como fuente maestra. Sus datos sustituirán por completo a los del otro dispositivo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                selectionCard(
                    source: .thisDevice,
                    title: "Conservar los datos de \(thisDeviceTitle)",
                    description: "Los datos de este dispositivo se copiarán íntegramente al otro equipo. Los datos que existieran en el otro equipo se sobrescribirán tras crear una copia de seguridad.",
                    icon: thisDeviceIcon,
                    tint: .blue
                )

                selectionCard(
                    source: .pairedMac,
                    title: "Conservar los datos de \(pairedDeviceTitle)",
                    description: "Se adoptará la base de datos completa del equipo emparejado. Los datos actuales de este dispositivo se reemplazarán tras crear un respaldo automático.",
                    icon: pairedDeviceIcon,
                    tint: .purple
                )
            }
        }
    }

    private func selectionCard(
        source: KmpBridge.SyncAdoptionSource,
        title: String,
        description: String,
        icon: String,
        tint: Color
    ) -> some View {
        let isSelected = selectedSource == source

        return Button {
            selectedSource = source
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? tint : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(tint.opacity(0.8))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color.adoptionCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Paso 3: Confirmación

    private var confirmStepView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Confirmación de adopción")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.red)

                Text("Esta operación igualará ambos dispositivos sustituyendo la base de datos del equipo receptor.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Se realizará una copia de seguridad automática y obligatoria antes de sobrescribir cualquier dato.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "shield.checkmark.fill")
                        .foregroundStyle(.green)
                }

                Label {
                    Text("Los contadores y registros del dispositivo adoptado serán exactamente idénticos a los del dispositivo fuente.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "equal.circle.fill")
                        .foregroundStyle(.blue)
                }

                Label {
                    Text("Para garantizar la integridad y evitar bloqueos en la base de datos SQLite, la aplicación se reiniciará para aplicar los cambios.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.adoptionCardBackground)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Paso 4: Completado

    private var completedStepView: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Adopción preparada")
                .font(.title.weight(.bold))

            Text(completionExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let backup = backupPathResult {
                VStack(spacing: 4) {
                    Text("Copia de seguridad guardada en:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(backup)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color.adoptionCardBackground)
                .cornerRadius(8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var completionExplanation: String {
        if selectedSource == .thisDevice {
            return "La base de datos se ha enviado al Mac emparejado. El Mac aplicará la adopción al reiniciarse."
        } else {
            return "La base de datos se ha descargado y preparado en este dispositivo. Reinicia la aplicación para que el cambio surta efecto."
        }
    }

    // MARK: - Barra inferior

    private var bottomBarView: some View {
        HStack {
            if isProcessing {
                ProgressView(progressMessage)
                    .font(.subheadline)
                Spacer()
            } else {
                switch step {
                case .compare:
                    Spacer()
                    Button("Continuar a selección") {
                        step = .choose
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(localFp == nil || remoteFp == nil)

                case .choose:
                    Button("Atrás") {
                        step = .compare
                    }
                    Spacer()
                    Button("Continuar") {
                        step = .confirm
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSource == nil)

                case .confirm:
                    Button("Atrás") {
                        step = .choose
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task {
                            await executeAdoption()
                        }
                    } label: {
                        Text("Igualar dispositivos")
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                case .completed:
                    Spacer()
                    #if os(macOS)
                    Button("Reiniciar app ahora") {
                        MacCommandCenterCoordinator.relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                    #else
                    Button("Entendido") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    #endif
                }
            }
        }
    }

    // MARK: - Lógica de adopción

    private func refreshFingerprints() async {
        do {
            let (local, remote) = try await bridge.fetchDatasetFingerprints()
            await MainActor.run {
                self.localFp = local
                self.remoteFp = remote
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "No se pudieron obtener las huellas de los dispositivos: \(error.localizedDescription)"
            }
        }
    }

    private func executeAdoption() async {
        guard let source = selectedSource else { return }
        isProcessing = true
        errorMessage = nil
        progressMessage = "Preparando adopción de datos..."

        do {
            let outcome = try await bridge.adoptDataset(from: source)
            await MainActor.run {
                isProcessing = false
                switch outcome {
                case let .needsRestart(hint):
                    self.needsRestartHint = hint
                    self.backupPathResult = hint
                case .stagedOnMac:
                    self.backupPathResult = "Mac (Application Support/backups)"
                }
                self.step = .completed
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                self.errorMessage = "Error durante la adopción: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers visuales

    private var thisDeviceTitle: String {
        #if os(macOS)
        return "Este Mac"
        #else
        return "Este iPad"
        #endif
    }

    private var thisDeviceIcon: String {
        #if os(macOS)
        return "macmini"
        #else
        return "ipad"
        #endif
    }

    private var pairedDeviceTitle: String {
        #if os(macOS)
        return "iPad"
        #else
        return "Mac"
        #endif
    }

    private var pairedDeviceIcon: String {
        #if os(macOS)
        return "ipad"
        #else
        return "macmini"
        #endif
    }
}

// MARK: - Color cross-platform helper

private extension Color {
    static var adoptionCardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var adoptionTertiaryBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
    }
}
