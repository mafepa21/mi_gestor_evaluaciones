import SwiftUI
import MiGestorKit
#if os(macOS)
import AppKit
#else
import GameController
#endif

/// Lee si la tecla de copiar (⌘, o ⌥ como en el Finder) está pulsada al soltar.
/// En iPad solo funciona con teclado físico: GameController expone su estado
/// (el drop de SwiftUI no), pero no publica `GCKeyboard.coalesced` hasta que
/// alguien escucha `GCKeyboardDidConnect`. Por eso hay que llamar a
/// `startMonitoring()` antes del primer arrastre; sin eso, ⌘ nunca se ve
/// y la sesión se mueve en vez de copiarse.
@MainActor
enum PlannerDragModifiers {
    #if !os(macOS)
    private static var isMonitoring = false
    private static var pressedCopyKeys: Set<GCKeyCode> = []
    private static let copyKeyCodes: Set<GCKeyCode> = [.leftGUI, .rightGUI, .leftAlt, .rightAlt]
    #endif

    static func startMonitoring() {
        #if !os(macOS)
        guard !isMonitoring else { return }
        isMonitoring = true
        NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { notification in
            let keyboard = notification.object as? GCKeyboard
            MainActor.assumeIsolated { attach(keyboard ?? GCKeyboard.coalesced) }
        }
        attach(GCKeyboard.coalesced)
        #endif
    }

    static var isCopyModifierPressed: Bool {
        #if os(macOS)
        let flags = NSEvent.modifierFlags.union(NSApp.currentEvent?.modifierFlags ?? [])
        return flags.contains(.command) || flags.contains(.option)
        #else
        if !pressedCopyKeys.isEmpty { return true }
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return false }
        return copyKeyCodes.contains { input.button(forKeyCode: $0)?.isPressed == true }
        #endif
    }

    #if !os(macOS)
    private static func attach(_ keyboard: GCKeyboard?) {
        guard let input = keyboard?.keyboardInput else { return }
        input.keyChangedHandler = { _, _, keyCode, pressed in
            guard copyKeyCodes.contains(keyCode) else { return }
            Task { @MainActor in
                if pressed {
                    pressedCopyKeys.insert(keyCode)
                } else {
                    pressedCopyKeys.remove(keyCode)
                }
            }
        }
    }
    #endif
}

enum CascadeUndoCopy {
    static func failure(_ detail: String) -> String {
        "No se pudo deshacer el movimiento. \(detail)"
    }
}

struct PlannerInlineBanner: View {
    let message: String
    var isError = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.orange : EvaluationDesign.success)
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

    /// Destino de una copia: una celda de la semana visible (⌘/⌥ + arrastrar)
    /// o el grupo, la fecha y la franja elegidos en «Copiar a…».
    enum CopyDestination: Equatable {
        case cell(day: Int, period: Int)
        case chosen(groupId: Int64, date: Date, period: Int)
    }

    /// Copia a una franja ocupada, a la espera de confirmar.
    struct PendingCopy: Identifiable {
        let sessionId: Int64
        let destination: CopyDestination

        var id: Int64 { sessionId }
    }

    @Published var pendingConfirmation: PendingDrop?
    @Published var pendingCopy: PendingCopy?
    @Published var transientMessage: String?
    /// El aviso actual es un error (icono y color de aviso, no el visto verde).
    @Published var transientIsError = false

    init() {
        PlannerDragModifiers.startMonitoring()
    }

    func handleDrop(sessionId: Int64, day: Int, period: Int, vm: PlannerWorkspaceViewModel) {
        if PlannerDragModifiers.isCopyModifierPressed {
            handleCopy(sessionId: sessionId, day: day, period: period, vm: vm)
            return
        }
        Task {
            do {
                let preview = try await vm.previewCascadeMove(sessionId: sessionId, day: day, period: period)
                guard !preview.isNoOp else { return }
                if !preview.completedSessionIds.isEmpty || !preview.cancelledSessionIds.isEmpty {
                    pendingConfirmation = PendingDrop(
                        sessionId: sessionId,
                        day: day,
                        period: period,
                        completedCount: preview.completedSessionIds.count + preview.cancelledSessionIds.count
                    )
                } else {
                    await commit(sessionId: sessionId, day: day, period: period, forceTerminalSessions: false, vm: vm)
                }
            } catch {
                showMessage("No se puede mover la sesión: \(error.localizedDescription)", isError: true)
                AppleInteractionFeedback.play(.error)
            }
        }
    }

    func confirmPendingMove(vm: PlannerWorkspaceViewModel) {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        Task {
            await commit(sessionId: pending.sessionId, day: pending.day, period: pending.period, forceTerminalSessions: true, vm: vm)
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
                showMessage("Movimiento deshecho.")
                AppleInteractionFeedback.play(.success)
            } catch {
                showMessage(CascadeUndoCopy.failure(error.localizedDescription), isError: true)
                AppleInteractionFeedback.play(.error)
            }
        }
    }

    func confirmPendingCopy(vm: PlannerWorkspaceViewModel) {
        guard let pending = pendingCopy else { return }
        pendingCopy = nil
        Task {
            await copy(sessionId: pending.sessionId, to: pending.destination, overwrite: true, vm: vm)
        }
    }

    func cancelPendingCopy() {
        pendingCopy = nil
        AppleInteractionFeedback.play(.warning)
    }

    /// Copia desde la hoja «Copiar a…»; si el destino está ocupado, pide confirmar.
    func copyChosen(sessionId: Int64, groupId: Int64, date: Date, period: Int, vm: PlannerWorkspaceViewModel) {
        Task {
            await copy(sessionId: sessionId, to: .chosen(groupId: groupId, date: date, period: period), overwrite: false, vm: vm)
        }
    }

    private func handleCopy(sessionId: Int64, day: Int, period: Int, vm: PlannerWorkspaceViewModel) {
        Task {
            await copy(sessionId: sessionId, to: .cell(day: day, period: period), overwrite: false, vm: vm)
        }
    }

    private func copy(sessionId: Int64, to destination: CopyDestination, overwrite: Bool, vm: PlannerWorkspaceViewModel) async {
        do {
            let outcome: PlannerSessionCopyOutcome
            switch destination {
            case .cell(let day, let period):
                outcome = try await vm.copySession(sessionId: sessionId, day: day, period: period, overwrite: overwrite)
            case .chosen(let groupId, let date, let period):
                outcome = try await vm.copySession(sessionId: sessionId, toGroupId: groupId, date: date, period: period, overwrite: overwrite)
            }
            switch outcome {
            case .copied(let summary):
                showMessage(summary)
                AppleInteractionFeedback.play(.success)
            case .occupied:
                pendingCopy = PendingCopy(sessionId: sessionId, destination: destination)
            case .sameSlot:
                // Soltar sobre sí misma no es un error; elegirlo en la hoja, sí.
                if case .chosen = destination {
                    showMessage("La sesión ya está en ese grupo, día y franja.", isError: true)
                }
            case .failed:
                showMessage("No se pudo copiar la sesión.", isError: true)
                AppleInteractionFeedback.play(.error)
            }
        } catch {
            showMessage("No se pudo copiar la sesión: \(error.localizedDescription)", isError: true)
            AppleInteractionFeedback.play(.error)
        }
    }

    private func showMessage(_ message: String, isError: Bool = false) {
        transientIsError = isError
        transientMessage = message
    }

    private func commit(sessionId: Int64, day: Int, period: Int, forceTerminalSessions: Bool, vm: PlannerWorkspaceViewModel) async {
        do {
            let result = try await vm.commitCascadeMove(
                sessionId: sessionId,
                day: day,
                period: period,
                forceTerminalSessions: forceTerminalSessions
            )
            let suffix = result.crossesWeekBoundary ? " Se ha continuado en la semana siguiente." : ""
            showMessage("Sesión movida; \(result.movedCount) sesión(es) recolocadas.\(suffix)")
            AppleInteractionFeedback.play(.success)
        } catch {
            showMessage("No se pudo completar el movimiento: \(error.localizedDescription)", isError: true)
            AppleInteractionFeedback.play(.error)
        }
    }
}
