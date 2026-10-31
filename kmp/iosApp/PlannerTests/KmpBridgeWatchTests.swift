import AppKit
import Combine
import SwiftUI
import XCTest
@testable import MiGestorKMPMac

/// Las vistas migradas de `@EnvironmentObject` a `kmpBridgeReference` deben seguir
/// refrescándose con lo que leen y dejar de hacerlo con lo demás.
@MainActor
final class KmpBridgeWatchTests: XCTestCase {
    private var bridge: KmpBridge!

    override func setUp() async throws {
        bridge = KmpBridge()
    }

    override func tearDown() async throws {
        bridge = nil
    }

    func testAvisaSoloCuandoCambiaLoQueVigila() async {
        let watch = KmpBridgeWatch()
        _ = watch.bridge(bridge) { [.init($0.syncPendingChanges)] }
        var avisos = 0
        let suscripcion = watch.objectWillChange.sink { avisos += 1 }
        defer { suscripcion.cancel() }

        bridge.syncStatusMessage = "Otro estado de SyncLAN"
        await vueltaDelBucle()
        XCTAssertEqual(avisos, 0, "Un cambio que la vista no lee no debe redibujarla")

        bridge.syncPendingChanges += 1
        await vueltaDelBucle()
        XCTAssertEqual(avisos, 1, "Un cambio de lo que lee debe redibujarla")

        bridge.syncPendingChanges = bridge.syncPendingChanges
        await vueltaDelBucle()
        XCTAssertEqual(avisos, 1, "Volver a poner el mismo valor no cuenta como cambio")
    }

    func testVariosCambiosSeguidosCuentanComoUno() async {
        let watch = KmpBridgeWatch()
        _ = watch.bridge(bridge) { [.init($0.syncPendingChanges)] }
        var avisos = 0
        let suscripcion = watch.objectWillChange.sink { avisos += 1 }
        defer { suscripcion.cancel() }

        bridge.syncPendingChanges += 1
        bridge.syncPendingChanges += 1
        bridge.syncPendingChanges += 1
        await vueltaDelBucle()
        XCTAssertEqual(avisos, 1)
    }

    /// Con SwiftUI de verdad: cuenta cuántas veces se calcula `body` de cada vista.
    func testVistaMigradaSeRedibujaConLoQueLeeYNoConLoDemas() async {
        let contador = ContadorDeBody()
        let raiz = VStack {
            SondaObservaTodo(contador: contador)
            SondaVigilada(contador: contador)
            SondaSoloAcciones(contador: contador)
        }
        .kmpBridgeEnvironment(bridge)
        let host = NSHostingView(rootView: raiz)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        await pintar(host)
        contador.reiniciar()

        bridge.syncStatusMessage = "Aviso de SyncLAN \(UUID())"
        await pintar(host)
        XCTAssertGreaterThan(contador.veces["observaTodo", default: 0], 0, "Control: con @EnvironmentObject sí se redibuja")
        XCTAssertEqual(contador.veces["vigilada", default: 0], 0, "La vista migrada no debe redibujarse por SyncLAN")
        XCTAssertEqual(contador.veces["soloAcciones", default: 0], 0)
        contador.reiniciar()

        bridge.syncPendingChanges += 1
        await pintar(host)
        XCTAssertGreaterThan(contador.veces["vigilada", default: 0], 0, "La vista migrada debe redibujarse con lo que pinta")
        XCTAssertEqual(contador.veces["soloAcciones", default: 0], 0)
    }

    private func vueltaDelBucle() async {
        // El vigilante compara en la vuelta siguiente de la cola principal.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func pintar(_ host: NSView) async {
        await vueltaDelBucle()
        host.layoutSubtreeIfNeeded()
        host.display()
        await vueltaDelBucle()
        host.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class ContadorDeBody {
    var veces: [String: Int] = [:]
    func sumar(_ nombre: String) { veces[nombre, default: 0] += 1 }
    func reiniciar() { veces = [:] }
}

private struct SondaObservaTodo: View {
    @EnvironmentObject var bridge: KmpBridge
    let contador: ContadorDeBody

    var body: some View {
        let _ = contador.sumar("observaTodo")
        Text("\(bridge.syncPendingChanges)")
    }
}

private struct SondaVigilada: View {
    @Environment(\.kmpBridgeReference) private var bridgeReference
    @StateObject private var bridgeWatch = KmpBridgeWatch()
    var bridge: KmpBridge {
        bridgeWatch.bridge(bridgeReference) { [.init($0.syncPendingChanges)] }
    }
    let contador: ContadorDeBody

    var body: some View {
        let _ = contador.sumar("vigilada")
        Text("\(bridge.syncPendingChanges)")
    }
}

private struct SondaSoloAcciones: View {
    @Environment(\.kmpBridgeReference) private var bridgeReference
    var bridge: KmpBridge { bridgeReference! }
    let contador: ContadorDeBody

    var body: some View {
        let _ = contador.sumar("soloAcciones")
        Button("Sincronizar") { _ = bridge }
    }
}
