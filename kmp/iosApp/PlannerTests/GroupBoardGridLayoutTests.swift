import XCTest
@testable import MiGestorKMPMac

/// Rejilla del tablero de grupos: todos los grupos a la vista sin desplazar la pantalla.
final class GroupBoardGridLayoutTests: XCTestCase {
    /// Hueco útil del tablero en un iPad horizontal (tras barra, «Sin grupo» y márgenes).
    private let iPadArea = CGSize(width: 1148, height: 640)
    private let iPadChips: ClosedRange<CGFloat> = 32...44

    func testOchoGruposDeCuatroCabenEnIPadSinDesplazar() {
        let layout = GroupBoardGridLayout.make(cardCount: 9, size: iPadArea, largestGroup: 4, chipRange: iPadChips)
        XCTAssertEqual(layout.columns * layout.rows >= 9, true)
        XCTAssertTrue(layout.fitsWithoutScroll)
        XCTAssertGreaterThanOrEqual(layout.chipHeight, 32, "En iPad la ficha no baja del mínimo táctil")
    }

    func testTodasLasTarjetasEntranEnElAlto() {
        for count in 1...12 {
            let layout = GroupBoardGridLayout.make(cardCount: count, size: iPadArea, largestGroup: 4, chipRange: iPadChips)
            let usedHeight = CGFloat(layout.rows) * layout.cardHeight + CGFloat(layout.rows - 1) * GroupBoardGridLayout.spacing
            XCTAssertLessThanOrEqual(usedHeight, iPadArea.height + 0.5, "\(count) tarjetas")
            XCTAssertGreaterThanOrEqual(layout.columns * layout.rows, count)
        }
    }

    func testTarjetaAnchaUsaDosColumnasDeFichas() {
        let layout = GroupBoardGridLayout.make(cardCount: 5, size: iPadArea, largestGroup: 6, chipRange: iPadChips)
        XCTAssertGreaterThan(layout.cardWidth, 300)
        XCTAssertEqual(layout.innerColumns, 2)
    }

    func testGrupoMuyGrandeNoEncogeLaFichaPorDebajoDelMinimo() {
        let layout = GroupBoardGridLayout.make(cardCount: 11, size: iPadArea, largestGroup: 12, chipRange: iPadChips)
        XCTAssertEqual(layout.chipHeight, 32)
        XCTAssertFalse(layout.fitsWithoutScroll, "Ese grupo se desplaza por dentro en lugar de encoger más")
    }

    func testSinDosColumnasInternasSiSeDesactivan() {
        let layout = GroupBoardGridLayout.make(cardCount: 3, size: iPadArea, largestGroup: 4, chipRange: iPadChips, allowTwoInnerColumns: false)
        XCTAssertEqual(layout.innerColumns, 1)
    }
}
