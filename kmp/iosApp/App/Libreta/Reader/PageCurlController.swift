import SwiftUI
import UIKit

/// Paso de hoja con curvatura de papel real (`UIPageViewController`, `.pageCurl`).
///
/// - Apaisado: lomo en el centro (`.mid`) y `isDoubleSided`: se ven dos hojas
///   (par a la izquierda, impar a la derecha) y el reverso de la hoja que se pasa
///   es la hoja siguiente de verdad.
/// - Vertical: lomo a la izquierda (`.min`), una hoja; el reverso es el estándar
///   translúcido. El lomo no se puede cambiar en caliente: quien lo usa debe
///   recrear la vista al girar (`.id(isLandscape)`).
///
/// La hoja que se ve la manda `currentPage` (primera hoja visible). Los pasos de hoja
/// hechos con el dedo se comunican con `onPageChange`; si se pasa más allá de la
/// última hoja se muestran hojas en blanco provisionales y, al completar el giro,
/// se pide crearlas con `onAppendPages`.
///
/// Los gestos de curvatura solo aceptan el dedo (nunca el Apple Pencil, que dibuja)
/// y se desactivan con `gesturesEnabled == false` (dibujar con el dedo, modo Objetos).
struct PageCurlView: UIViewControllerRepresentable {
    /// Ids de las hojas en orden: detecta altas, bajas y cambios de orden.
    let pageIDs: [UUID]
    /// Primera hoja visible pedida (en apaisado se redondea a la par).
    let currentPage: Int
    let isLandscape: Bool
    let gesturesEnabled: Bool
    /// Contenido de la hoja `index` (si `index` no existe todavía: hoja en blanco).
    let content: (Int, PageSide) -> AnyView
    /// La primera hoja visible tras un paso de hoja con el dedo.
    let onPageChange: (Int) -> Void
    /// Se ha pasado a hojas que aún no existen: hay que crearlas.
    let onAppendPages: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let spine: UIPageViewController.SpineLocation = isLandscape ? .mid : .min
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: spine.rawValue)]
        )
        pvc.isDoubleSided = isLandscape
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        context.coordinator.pvc = pvc
        context.coordinator.show(context.coordinator.normalized(currentPage), animated: false)
        context.coordinator.configureGestures()
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
    }

    static func dismantleUIViewController(_ pvc: UIPageViewController, coordinator: Coordinator) {
        pvc.dataSource = nil
        pvc.delegate = nil
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView
        weak var pvc: UIPageViewController?

        /// Primera hoja que muestra ahora el controlador.
        private var displayedFirst = 0
        /// Giro en curso (con el dedo o programado): no se tocan los controladores.
        private var isTransitioning = false
        /// Llegó una actualización durante el giro; se aplica al terminar.
        private var pendingSync = false

        init(parent: PageCurlView) { self.parent = parent }

        private var perSpread: Int { parent.isLandscape ? 2 : 1 }
        private var pageCount: Int { parent.pageIDs.count }

        func normalized(_ index: Int) -> Int {
            let clamped = min(max(index, 0), max(pageCount - 1, 0))
            return parent.isLandscape ? clamped - clamped % 2 : clamped
        }

        private func side(for index: Int) -> PageSide {
            guard parent.isLandscape else { return .single }
            return index % 2 == 0 ? .left : .right
        }

        private func pageID(at index: Int) -> UUID? {
            (0..<pageCount).contains(index) ? parent.pageIDs[index] : nil
        }

        private func makeController(_ index: Int) -> CurlPageController {
            CurlPageController(index: index, pageID: pageID(at: index),
                               rootView: parent.content(index, side(for: index)))
        }

        // MARK: Sincronización con el estado de SwiftUI

        func configureGestures() {
            guard let pvc else { return }
            // Solo el dedo (y el trackpad) pasan hoja; el Apple Pencil siempre dibuja.
            let touchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                              NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            for g in pvc.gestureRecognizers {
                g.allowedTouchTypes = touchTypes
                // El toque en el margen también pasaría hoja: se apaga para que los toques
                // (enfocar hoja, quitar el marcapáginas) nunca pasen hoja por accidente.
                g.isEnabled = parent.gesturesEnabled && !(g is UITapGestureRecognizer)
            }
        }

        func sync() {
            guard let pvc else { return }
            configureGestures()
            guard !isTransitioning else { pendingSync = true; return }

            let target = normalized(parent.currentPage)
            let visible = (pvc.viewControllers ?? []).compactMap { $0 as? CurlPageController }
            if target != displayedFirst {
                show(target, animated: true)
            } else if visible.count != perSpread
                        || visible.contains(where: { $0.pageID != pageID(at: $0.index) }) {
                // Se insertaron, borraron o reordenaron hojas: mismas posiciones, otras hojas.
                show(target, animated: false)
            } else {
                // Mismo contenido: solo se refresca (hoja activa, modo Objetos, selección…).
                for vc in visible { vc.rootView = parent.content(vc.index, side(for: vc.index)) }
            }
        }

        func show(_ first: Int, animated: Bool) {
            guard let pvc else { return }
            let direction: UIPageViewController.NavigationDirection = first >= displayedFirst ? .forward : .reverse
            let controllers = (first..<first + perSpread).map { makeController($0) }
            displayedFirst = first
            guard animated else {
                pvc.setViewControllers(controllers, direction: direction, animated: false)
                return
            }
            isTransitioning = true
            // Durante un giro programado no se admiten gestos (evita estados incoherentes).
            pvc.view.isUserInteractionEnabled = false
            pvc.setViewControllers(controllers, direction: direction, animated: true) { [weak self] _ in
                self?.programmaticTransitionEnded()
            }
        }

        private func programmaticTransitionEnded() {
            isTransitioning = false
            pvc?.view.isUserInteractionEnabled = true
            if pendingSync {
                pendingSync = false
                sync()
            }
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? CurlPageController, vc.index > 0 else { return nil }
            return makeController(vc.index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? CurlPageController else { return nil }
            let next = vc.index + 1
            // Una hoja (vertical) o una doble página (apaisado) en blanco más allá del final:
            // al pasar a ella se crea de verdad.
            guard next < pageCount + perSpread else { return nil }
            return makeController(next)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            isTransitioning = false
            guard completed,
                  let first = (pageViewController.viewControllers?.first as? CurlPageController)?.index
            else {
                if pendingSync { pendingSync = false; sync() }
                return
            }
            displayedFirst = first
            // No se sincroniza aquí: `parent` aún tiene la hoja anterior. El cambio de estado
            // provoca un `updateUIViewController` con los datos nuevos (y, si se crearon
            // hojas, cambia las provisionales por las reales sin animación).
            pendingSync = false
            if first + perSpread > pageCount { parent.onAppendPages() }
            parent.onPageChange(first)
        }
    }
}

/// Una hoja dentro del `UIPageViewController`: aloja la vista SwiftUI de la hoja.
final class CurlPageController: UIHostingController<AnyView> {
    let index: Int
    /// `nil` = hoja provisional (aún no existe en el cuaderno).
    let pageID: UUID?

    init(index: Int, pageID: UUID?, rootView: AnyView) {
        self.index = index
        self.pageID = pageID
        super.init(rootView: rootView)
        // La hoja ocupa exactamente su rectángulo: sin márgenes de seguridad ni teclado.
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Transparente: las esquinas redondeadas del papel dejan ver la pila de hojas fija
        // que hay debajo. El papel en sí es opaco, así que el reverso nunca se ve vacío.
        view.backgroundColor = .clear
    }
}
