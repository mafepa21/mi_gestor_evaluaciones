import SwiftUI

/// Engancha todo el onboarding a un shell (iOS/iPadOS o macOS) con una línea.
///
/// Los pasos no reimplementan nada: abren las pantallas que ya existen
/// (`TeacherScheduleWizard`, `StudentImportSheet`, el módulo de Situaciones).
/// Así el camino guiado y el camino normal no pueden divergir.
///
/// Este modificador sólo presenta. Quién decide si hay que enseñar la
/// bienvenida es `OnboardingStore.bootstrap(bridge:)`, y cada shell la llama
/// cuando su propia carga inicial ha terminado: si se preguntara antes, la base
/// aún estaría vacía y un docente con el curso empezado vería el tutorial.
struct OnboardingHostModifier: ViewModifier {
    /// Explícito y no por `@EnvironmentObject`: la shell de macOS trabaja con
    /// el `KmpBridge` de su `MacAppSessionController`, que no es la instancia
    /// que hay en el entorno. Cada shell pasa el suyo.
    @ObservedObject var bridge: KmpBridge
    @ObservedObject private var store = OnboardingStore.shared

    /// Cómo lleva este shell al usuario a un módulo concreto. `.courses` debe
    /// resolverse a Ajustes → Cursos y grupos, que es donde vive ahora.
    let onOpenModule: (AppWorkspaceModule) -> Void

    @State private var wizardClassId: Int64?

    func body(content: Content) -> some View {
        content
            .sheet(item: $store.route) { route in
                routeContent(route)
            }
    }

    @ViewBuilder
    private func routeContent(_ route: OnboardingRoute) -> some View {
        switch route {
        case .welcome:
            OnboardingWelcomeSheet(
                onStart: {
                    store.markWelcomeSeen()
                    replaceRoute(with: .checklist)
                },
                onSkip: { store.dismiss() }
            )
#if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif

        case .checklist:
            OnboardingChecklistView(
                store: store,
                onAction: handleAction(_:_:),
                onClose: { store.dismiss() },
                onFinish: finishOnboarding
            )
            // La lista también se abre desde Ajustes mucho después del primer
            // arranque: se recalcula el progreso al aparecer.
            .task { await store.refresh(bridge: bridge) }
#if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif

        case .scheduleWizard(let startOnSlots, let autoPresentImporter):
            TeacherScheduleWizard(
                bridge: bridge,
                selectedClassId: $wizardClassId,
                onClose: { returnToChecklist() },
                initialStep: startOnSlots ? .slots : .course,
                autoPresentImporter: autoPresentImporter
            )
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 620)
            #endif

        case .students(let startWithImport):
            OnboardingStudentsSheet(
                startWithImport: startWithImport,
                onFinished: { returnToChecklist() }
            )
            .environmentObject(bridge)
        }
    }

    /// Cambiar el `item` de un `.sheet` mientras hay una hoja presentada es
    /// poco fiable: hay que cerrar, dejar terminar la animación y volver a
    /// presentar. Todos los saltos entre pantallas del onboarding pasan por aquí.
    private func replaceRoute(with route: OnboardingRoute) {
        store.route = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            store.route = route
        }
    }

    /// Al volver de un paso se recalcula el progreso antes de reabrir la lista:
    /// el docente ve marcado lo que acaba de hacer, no un estado viejo.
    private func returnToChecklist() {
        store.route = nil
        Task {
            await store.refresh(bridge: bridge)
            replaceRoute(with: .checklist)
        }
    }

    /// Cerrar el recorrido no debe dejar al docente en el mismo estado de
    /// configuración: Hoy es la primera superficie operativa y el destino
    /// común de iPad, iPhone y macOS.
    private func finishOnboarding() {
        store.dismiss()
        onOpenModule(.dashboard)
    }

    private func handleAction(_ step: OnboardingStep, _ kind: OnboardingActionKind) {
        switch step {
        case .course:
            replaceRoute(with: .scheduleWizard(startOnSlots: false, autoPresentImporter: false))

        case .schedule:
            replaceRoute(with: .scheduleWizard(
                startOnSlots: true,
                autoPresentImporter: kind == .importDocument
            ))

        case .groups:
            // Los grupos no se crean aquí: salen del horario. "Ver mis grupos"
            // lleva a la pantalla que los administra, ahora dentro de Ajustes.
            store.route = nil
            onOpenModule(.courses)

        case .students:
            replaceRoute(with: .students(startWithImport: kind == .importDocument))

        case .learningSituations:
            store.route = nil
            onOpenModule(.situations)
        }
    }
}

extension View {
    func onboardingHost(
        bridge: KmpBridge,
        onOpenModule: @escaping (AppWorkspaceModule) -> Void
    ) -> some View {
        modifier(OnboardingHostModifier(bridge: bridge, onOpenModule: onOpenModule))
    }
}
