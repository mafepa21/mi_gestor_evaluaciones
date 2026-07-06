import SwiftUI
import MiGestorKit

struct PlannerInlineBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(EvaluationDesign.success)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .plannerGlassPanel(.control, cornerRadius: 999)
    }
}

/// Coordina el flujo de arrastrar una sesión a otra celda del grid semanal:
/// previsualiza el movimiento en cascada, pide confirmación si arrastra
/// sesiones ya impartidas y expone el resultado para deshacer.
/// Compartido entre iPadOS y macOS para no duplicar la lógica de negocio.
@MainActor
final class PlannerCascadeDropCoordinator: ObservableObject {
    struct PendingDrop: Identifiable {
        let sessionId: Int64
        let day: Int
        let period: Int
        let completedCount: Int

        var id: Int64 { sessionId }
    }

    @Published var pendingConfirmation: PendingDrop?
    @Published var transientMessage: String?

    func handleDrop(sessionId: Int64, day: Int, period: Int, vm: PlannerWorkspaceViewModel) {
        Task {
            do {
                let preview = try await vm.previewCascadeMove(sessionId: sessionId, day: day, period: period)
                guard !preview.isNoOp else { return }
                if !preview.completedSessionIds.isEmpty {
                    pendingConfirmation = PendingDrop(
                        sessionId: sessionId,
                        day: day,
                        period: period,
                        completedCount: preview.completedSessionIds.count
                    )
                } else {
                    await commit(sessionId: sessionId, day: day, period: period, vm: vm)
                }
            } catch {
                transientMessage = "No se puede mover la sesión: \(error.localizedDescription)"
                AppleInteractionFeedback.play(.error)
            }
        }
    }

    func confirmPendingMove(vm: PlannerWorkspaceViewModel) {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        Task {
            await commit(sessionId: pending.sessionId, day: pending.day, period: pending.period, vm: vm)
        }
    }

    func cancelPendingMove() {
        pendingConfirmation = nil
        AppleInteractionFeedback.play(.warning)
    }

    func undoLastMove(vm: PlannerWorkspaceViewModel) {
        Task {
            do {
                try await vm.restoreLastCascadeMove()
                transientMessage = "Movimiento deshecho."
                AppleInteractionFeedback.play(.success)
            } catch {
                transientMessage = "No se pudo deshacer: \(error.localizedDescription)"
                AppleInteractionFeedback.play(.error)
            }
        }
    }

    private func commit(sessionId: Int64, day: Int, period: Int, vm: PlannerWorkspaceViewModel) async {
        do {
            let result = try await vm.commitCascadeMove(sessionId: sessionId, day: day, period: period)
            let suffix = result.crossesWeekBoundary ? " Se ha continuado en la semana siguiente." : ""
            transientMessage = "Sesión movida; \(result.movedCount) sesión(es) recolocadas.\(suffix)"
            AppleInteractionFeedback.play(.success)
        } catch {
            transientMessage = "No se pudo completar el movimiento: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }
}
