import SwiftUI

enum PageGeometry {
    /// Tamaño lógico de una hoja: trazos y objetos se guardan en estas coordenadas
    /// y se escalan al tamaño real en pantalla.
    static let logicalSize = CGSize(width: 820, height: 820 / Theme.pageAspect)
}
