import SwiftUI

enum OnboardingActionKind {
    case importDocument
    case manual
}

/// Lista de "Primeros pasos": el recorrido real de configuración.
///
/// Es una lista y no un asistente lineal a propósito. Un docente no configura
/// todo esto de una sentada: mete el horario un día, el alumnado cuando le llega
/// la lista, y las situaciones cuando las tiene escritas. La lista sobrevive al
/// cierre de la app y se reabre desde Ajustes → General. Cuando se completa,
/// ofrece una salida directa al cockpit de Hoy para que la primera sesión de
/// trabajo no termine en una pantalla de configuración.
///
/// Cada fila ofrece siempre los dos caminos por separado y con nombre propio
/// ("Importar Excel" / "Escribir nombres"), en vez de esconder el manual detrás
/// de un enlace secundario.
struct OnboardingChecklistView: View {
    @ObservedObject var store: OnboardingStore
    @Environment(\.colorScheme) private var colorScheme

    let onAction: (OnboardingStep, OnboardingActionKind) -> Void
    let onClose: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(OnboardingStep.allCases) { step in
                        stepRow(step)
                    }
                    if store.isDone {
                        finishedNote
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .background(appPageBackground(for: colorScheme))
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 580, idealHeight: 680)
        #endif
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Primeros pasos")
                        .font(.title2.weight(.bold))
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Label("Cerrar", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cerrar primeros pasos")
            }

            progressBar
        }
        .padding(20)
    }

    private var headerSubtitle: String {
        if store.isDone {
            return "Todo listo. Ya puedes trabajar con la app en el día a día."
        }
        if let next = store.nextStep {
            return "Vas por el paso \(next.number) de \(store.totalCount): \(next.title.lowercased())."
        }
        return "Configura lo mínimo para empezar a dar clase."
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(EvaluationDesign.accent)
                        .frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 8)

            Text("\(store.completedCount) de \(store.totalCount) hechos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Progreso: \(store.completedCount) de \(store.totalCount) pasos hechos")
    }

    private var progressFraction: CGFloat {
        guard store.totalCount > 0 else { return 0 }
        return CGFloat(store.completedCount) / CGFloat(store.totalCount)
    }

    private var footer: some View {
        HStack {
            // El texto dice exactamente lo que hace el botón: al cerrar, la
            // lista no vuelve a saltar sola; se reabre desde Ajustes.
            Text("Puedes cerrar y volver cuando quieras desde Ajustes → General.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(store.isDone ? "Abrir Hoy" : "Seguir luego", action: store.isDone ? onFinish : onClose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(20)
    }

    private var finishedNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppleDesignSystem.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Configuración terminada")
                    .font(.subheadline.weight(.semibold))
                Text("Ya puedes abrir Hoy: tus grupos y tu alumnado estarán listos para el primer día de trabajo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppleDesignSystem.success.opacity(0.10))
        )
    }

    // MARK: - Filas

    private func stepRow(_ step: OnboardingStep) -> some View {
        let isDone = store.isCompleted(step)
        let isAvailable = store.isAvailable(step)
        let blockedReason = store.blockedReason(for: step)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                stepBadge(step, isDone: isDone, isAvailable: isAvailable)

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    Text(step.whyItMatters)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let blockedReason {
                        Label(blockedReason, systemImage: "lock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppleDesignSystem.warning)
                            .padding(.top, 2)
                    } else if let detail = statusDetail(for: step), isDone {
                        Label(detail, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppleDesignSystem.success)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }

            if isAvailable {
                HStack(spacing: 10) {
                    if let importTitle = step.importActionTitle {
                        Button(importTitle) { onAction(step, .importDocument) }
                            .buttonStyle(.borderedProminent)
                        Button(step.manualActionTitle) { onAction(step, .manual) }
                            .buttonStyle(.bordered)
                    } else {
                        // Sin camino de importación, el manual es la acción
                        // principal y se pinta como tal.
                        Button(step.manualActionTitle) { onAction(step, .manual) }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appCardBackground(for: colorScheme).opacity(isAvailable ? 1 : 0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isDone ? AppleDesignSystem.success.opacity(0.35) : AppleDesignSystem.border,
                            lineWidth: 1
                        )
                )
        )
    }

    private func stepBadge(_ step: OnboardingStep, isDone: Bool, isAvailable: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isDone
                        ? AppleDesignSystem.success.opacity(0.16)
                        : EvaluationDesign.accent.opacity(isAvailable ? 0.12 : 0.06)
                )
                .frame(width: 42, height: 42)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppleDesignSystem.success)
            } else {
                Text("\(step.number)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(isAvailable ? EvaluationDesign.accent : Color.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    /// Cifra concreta en vez de un "hecho" genérico: confirma al docente que lo
    /// que la app dio por bueno es de verdad lo suyo.
    private func statusDetail(for step: OnboardingStep) -> String? {
        switch step {
        case .course:
            return "Fechas confirmadas"
        case .schedule:
            return store.slotCount == 1 ? "1 franja en el horario" : "\(store.slotCount) franjas en el horario"
        case .groups:
            return store.groupCount == 1 ? "1 grupo" : "\(store.groupCount) grupos"
        case .students:
            return store.studentCount == 1 ? "1 alumno" : "\(store.studentCount) alumnos"
        case .learningSituations:
            return "Al menos una situación creada"
        }
    }
}
