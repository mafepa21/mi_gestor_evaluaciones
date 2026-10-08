import Foundation
import XCTest
@testable import MiGestorKMPMac

final class AppleCalendarReconcilerTests: XCTestCase {
    private let windowStart: Int64 = 1_788_220_800_000   // 1 sept 2026 00:00 UTC
    private let windowEnd: Int64 = 1_814_399_999_000     // 30 jun 2027 23:59:59 UTC

    private func remote(
        _ externalId: String = "ext-1",
        title: String = "Evaluación inicial",
        notes: String? = nil,
        start: Int64 = 1_792_000_000_000,
        end: Int64 = 1_792_086_399_000,
        modified: Int64 = 1_791_000_000_000
    ) -> AppleCalendarRemoteEvent {
        AppleCalendarRemoteEvent(
            externalId: externalId,
            title: title,
            notes: notes,
            startMs: start,
            endMs: end,
            lastModifiedMs: modified
        )
    }

    private func local(
        _ id: Int64 = 1,
        externalId: String? = "ext-1",
        title: String = "Evaluación inicial",
        notes: String? = nil,
        start: Int64 = 1_792_000_000_000,
        end: Int64 = 1_792_086_399_000,
        updated: Int64 = 1_791_000_000_000
    ) -> AppleCalendarLocalEvent {
        AppleCalendarLocalEvent(
            id: id,
            title: title,
            notes: notes,
            startMs: start,
            endMs: end,
            updatedMs: updated,
            externalId: externalId
        )
    }

    private func plan(remote: [AppleCalendarRemoteEvent], locals: [AppleCalendarLocalEvent]) -> [AppleCalendarReconcileAction] {
        AppleCalendarReconciler.plan(
            remote: remote,
            locals: locals,
            windowStartMs: windowStart,
            windowEndMs: windowEnd
        )
    }

    func testEventoNuevoEnColegioSeImporta() {
        let actions = plan(remote: [remote()], locals: [])
        XCTAssertEqual(actions, [.importRemote(remote())])
    }

    func testEventoYaEnlazadoNoSeDuplica() {
        let actions = plan(remote: [remote()], locals: [local()])
        XCTAssertEqual(actions, [])
    }

    func testNotasNilYVaciasSonIguales() {
        let actions = plan(remote: [remote(notes: nil)], locals: [local(notes: "")])
        XCTAssertEqual(actions, [])
    }

    func testCambioMasRecienteEnColegioActualizaLaApp() {
        let changed = remote(title: "Evaluación inicial (aplazada)", modified: 1_792_500_000_000)
        let actions = plan(remote: [changed], locals: [local(updated: 1_791_000_000_000)])
        XCTAssertEqual(actions, [.updateLocal(id: 1, classId: nil, from: changed)])
    }

    func testCambioMasRecienteEnLaAppEmpujaAColegio() {
        let actions = plan(
            remote: [remote(title: "Evaluación inicial")],
            locals: [local(title: "Evaluación inicial (aplazada)", updated: 1_792_500_000_000)]
        )
        XCTAssertEqual(actions, [.pushLocal(local(title: "Evaluación inicial (aplazada)", updated: 1_792_500_000_000))])
    }

    func testBorradoEnColegioDentroDelCursoBorraLaApp() {
        let actions = plan(remote: [], locals: [local(start: windowStart + 86_400_000)])
        XCTAssertEqual(actions, [.deleteLocal(id: 1)])
    }

    func testBorradoEnColegioFueraDelCursoNoBorraLaApp() {
        let actions = plan(remote: [], locals: [local(start: windowStart - 86_400_000)])
        XCTAssertEqual(actions, [])
    }

    func testEventoSinEnlaceNuncaSeBorra() {
        let actions = plan(remote: [], locals: [local(externalId: nil, start: windowStart + 86_400_000)])
        XCTAssertEqual(actions, [])
    }

    func testDosEventosApuntandoAlMismoRemotoDejanUno() {
        let actions = plan(
            remote: [remote()],
            locals: [local(2, externalId: "ext-1"), local(1, externalId: "ext-1")]
        )
        XCTAssertEqual(actions, [.removeDuplicate(id: 2)])
    }

    func testEventoAjenoALaAppNoSeToca() {
        let actions = plan(remote: [], locals: [local(externalId: nil)])
        XCTAssertEqual(actions, [])
    }

    func testEventoDeColegioSeEnlazaConLaFilaSinEnlaceDelMismoDia() {
        let remoteEvent = remote()
        let unlinked = AppleCalendarLocalEvent(
            id: 7, title: "Evaluación inicial", notes: nil,
            startMs: 1_792_000_000_000, endMs: 1_792_086_399_000,
            updatedMs: 1_791_000_000_000, externalId: nil, classId: 42
        )
        let actions = plan(remote: [remoteEvent], locals: [unlinked])
        XCTAssertEqual(actions, [.adoptLocal(id: 7, classId: 42, from: remoteEvent)])
    }

    func testEventoDeOtroDiaNoSeEnlazaSeImporta() {
        let remoteEvent = remote(start: 1_792_200_000_000, end: 1_792_286_399_000)
        let unlinked = local(7, externalId: nil)
        let actions = plan(remote: [remoteEvent], locals: [unlinked])
        XCTAssertEqual(actions, [.importRemote(remoteEvent)])
    }

    func testCambioEnColegioConservaElGrupo() {
        let changed = remote(title: "Evaluación inicial (aplazada)", modified: 1_792_500_000_000)
        let linked = AppleCalendarLocalEvent(
            id: 1, title: "Evaluación inicial", notes: nil,
            startMs: 1_792_000_000_000, endMs: 1_792_086_399_000,
            updatedMs: 1_791_000_000_000, externalId: "ext-1", classId: 42
        )
        let actions = plan(remote: [changed], locals: [linked])
        XCTAssertEqual(actions, [.updateLocal(id: 1, classId: 42, from: changed)])
    }
}
