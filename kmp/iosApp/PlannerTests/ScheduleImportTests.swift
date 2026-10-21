import XCTest
@testable import MiGestorKMPMac

final class ScheduleImportTests: XCTestCase {
    func testCombinesComplementaryFilesBeforeSaving() throws {
        let service = ScheduleExcelImportService()
        let eso = try service.preview(
            rows: [
                ["Horas", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"],
                ["De 08:05 a 09:00", "EFI3 : 3ESOB", "", "", "", ""],
                ["Materias:", "EFI3: Educación Física", "", "", "", ""]
            ],
            sourceName: "ESO.xlsx"
        )
        let bachillerato = try service.preview(
            rows: [
                ["Horas", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"],
                ["De 08:05 a 09:00", "", "", "", "", "EFI1 : 1BAHA"],
                ["Materias:", "EFI1: Educación Física", "", "", "", ""]
            ],
            sourceName: "Bachillerato.xlsx"
        )

        let combined = service.combine([eso, bachillerato])

        XCTAssertEqual(combined.sourceName, "2 archivos combinados")
        XCTAssertEqual(combined.persistableSlots.count, 2)
        XCTAssertEqual(combined.groupCodes, ["1BAHA", "3ESOB"])
        XCTAssertTrue(combined.conflicts.isEmpty)
    }

    func testUnifiesExactDuplicatesAcrossFiles() throws {
        let service = ScheduleExcelImportService()
        let preview = try service.preview(
            rows: [
                ["Horas", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"],
                ["De 12:20 a 13:15", "", "", "", "", "EFI4 : 4ESOA"],
                ["Materias:", "EFI4: Educación Física", "", "", "", ""]
            ],
            sourceName: "Horario.xlsx"
        )

        let combined = service.combine([preview, preview])

        XCTAssertEqual(combined.persistableSlots.count, 1)
        XCTAssertTrue(combined.warnings.contains { $0.contains("idénticos") })
    }

    func testRejectsMoreThanThreeFiles() {
        let urls = (1...4).map { URL(fileURLWithPath: "/tmp/horario-\($0).xlsx") }

        XCTAssertThrowsError(try ScheduleExcelImportService().preview(from: urls)) { error in
            XCTAssertEqual(error.localizedDescription, "Puedes combinar un máximo de 3 archivos de horario.")
        }
    }

    // MARK: - Grupos con el mismo nombre (dos "4º ESO A" de centros distintos)

    private let resolver = ScheduleImportCatalogResolver()

    func testSingleExactGroupStillMatchesAutomatically() {
        let resolution = resolver.resolveGroups(
            groupCodes: ["4ESOA"],
            existingGroups: [(id: 7, name: "4º ESO A"), (id: 8, name: "4º ESO B")]
        )
        XCTAssertEqual(resolution.matchedIdByCode["4ESOA"], 7)
        XCTAssertTrue(resolution.ambiguousCandidatesByCode.isEmpty)
        XCTAssertTrue(resolution.toCreate.isEmpty)
    }

    func testTwoGroupsWithSameNameAreNotPickedSilently() {
        let resolution = resolver.resolveGroups(
            groupCodes: ["4ESOA"],
            existingGroups: [(id: 12, name: "4º ESO A"), (id: 3, name: "4º  eso a")]
        )
        XCTAssertNil(resolution.matchedIdByCode["4ESOA"])
        XCTAssertEqual(resolution.ambiguousCandidatesByCode["4ESOA"], [3, 12])
        XCTAssertTrue(resolution.toCreate.isEmpty)
    }

    func testGroupWithCenterSuffixCountsAsCandidate() {
        let resolution = resolver.resolveGroups(
            groupCodes: ["4ESOA"],
            existingGroups: [(id: 1, name: "4º ESO A"), (id: 2, name: "4º ESO A - Tavernes"), (id: 3, name: "4º ESO AB")]
        )
        XCTAssertNil(resolution.matchedIdByCode["4ESOA"])
        XCTAssertEqual(resolution.ambiguousCandidatesByCode["4ESOA"], [1, 2])
    }

    func testChoiceAssignsSlotsToChosenGroupOrCreatesNewOne() {
        let groups: [(id: Int64, name: String)] = [(id: 1, name: "4º ESO A"), (id: 2, name: "4º ESO A")]
        let chosen = resolver.resolveGroups(groupCodes: ["4ESOA"], existingGroups: groups, choices: ["4ESOA": .existing(2)])
        XCTAssertEqual(chosen.matchedIdByCode["4ESOA"], 2)
        XCTAssertTrue(chosen.ambiguousCandidatesByCode.isEmpty)

        let created = resolver.resolveGroups(groupCodes: ["4ESOA"], existingGroups: groups, choices: ["4ESOA": .createNew])
        XCTAssertNil(created.matchedIdByCode["4ESOA"])
        XCTAssertEqual(created.toCreate.map(\.name), ["4º ESO A"])

        let stale = resolver.resolveGroups(groupCodes: ["4ESOA"], existingGroups: groups, choices: ["4ESOA": .existing(99)])
        XCTAssertEqual(stale.ambiguousCandidatesByCode["4ESOA"], [1, 2])
    }

    func testPlanKeepsPromptsAfterChoosing() {
        let groups: [(id: Int64, name: String)] = [(id: 1, name: "4º ESO A"), (id: 2, name: "4º ESO A")]
        let plan = ScheduleImportCatalogPlan.build(
            groupResolution: resolver.resolveGroups(groupCodes: ["4ESOA"], existingGroups: groups, choices: ["4ESOA": .existing(1)]),
            subjectResolution: .init(),
            promptResolution: resolver.resolveGroups(groupCodes: ["4ESOA"], existingGroups: groups),
            candidateTitle: { $0 == 1 ? "4º ESO A · Mislata" : "4º ESO A · Tavernes" }
        )
        XCTAssertEqual(plan.groupChoicePrompts.map(\.id), ["4ESOA"])
        XCTAssertEqual(plan.groupChoicePrompts.first?.candidates.map(\.title), ["4º ESO A · Mislata", "4º ESO A · Tavernes"])
        XCTAssertEqual(plan.groupsReusedCount, 1)
    }

    func testDisplayNamesDistinguishRepeatedGroups() {
        let labels = SchoolClassDisplayNames.labels(for: [
            .init(id: 1, name: "4º ESO A", description: "Mislata"),
            .init(id: 2, name: "4º ESO A", description: "Tavernes"),
            .init(id: 3, name: "1º BAC B"),
            .init(id: 4, name: "3º ESO A", academicYearName: "2025-2026"),
            .init(id: 5, name: "3º ESO A", academicYearName: "2026-2027"),
            .init(id: 6, name: "2º ESO C"),
            .init(id: 7, name: "2º ESO C")
        ])
        XCTAssertEqual(labels[1], "4º ESO A · Mislata")
        XCTAssertEqual(labels[2], "4º ESO A · Tavernes")
        XCTAssertEqual(labels[3], "1º BAC B")
        XCTAssertEqual(labels[4], "3º ESO A · 2025-2026")
        XCTAssertEqual(labels[5], "3º ESO A · 2026-2027")
        XCTAssertEqual(labels[6], "2º ESO C · 1")
        XCTAssertEqual(labels[7], "2º ESO C · 2")
    }

    func testSameNameGroupsShowWhichGroupOwnsEachDay() throws {
        let groups: [SchoolClassDisplayNames.Group] = [
            .init(id: 1, name: "4º ESO A", description: "Mislata"),
            .init(id: 2, name: "4º ESO A ", description: "Tavernes"),
            .init(id: 3, name: "1º BAC B")
        ]
        // Martes mal asignado a Mislata; jueves mezclado.
        let slots: [SameNameGroupScheduleDays.Slot] = [
            .init(id: 10, groupId: 1, day: 1),
            .init(id: 11, groupId: 1, day: 2),
            .init(id: 12, groupId: 1, day: 4),
            .init(id: 13, groupId: 2, day: 4),
            .init(id: 14, groupId: 3, day: 2)
        ]
        let families = SameNameGroupScheduleDays.families(groups: groups, slots: slots)
        XCTAssertEqual(families.count, 1)
        let family = try XCTUnwrap(families.first)
        XCTAssertEqual(family.groupIds, [1, 2])
        XCTAssertEqual(family.days, [1, 2, 4])
        XCTAssertEqual(family.groupIdsByDay[2], [1])
        XCTAssertEqual(family.groupIdsByDay[4], [1, 2])

        let tuesday = SameNameGroupScheduleDays.slotsToReassign(in: family, day: 2, to: 2, slots: slots)
        XCTAssertEqual(tuesday.map(\.id), [11])
        let thursday = SameNameGroupScheduleDays.slotsToReassign(in: family, day: 4, to: 2, slots: slots)
        XCTAssertEqual(thursday.map(\.id), [12])
        XCTAssertTrue(SameNameGroupScheduleDays.slotsToReassign(in: family, day: 2, to: 3, slots: slots).isEmpty)
    }

    func testNoFamilyWhenNamesAreUnique() {
        let families = SameNameGroupScheduleDays.families(
            groups: [.init(id: 1, name: "4º ESO A"), .init(id: 2, name: "4º ESO B")],
            slots: [.init(id: 10, groupId: 1, day: 1), .init(id: 11, groupId: 2, day: 2)]
        )
        XCTAssertTrue(families.isEmpty)
    }

    func testOrphanGroupIdsListsSlotsOfDeletedGroups() {
        let orphans = SameNameGroupScheduleDays.orphanGroupIds(
            knownGroupIds: [1, 2],
            slots: [
                .init(id: 10, groupId: 1, day: 1),
                .init(id: 11, groupId: 21, day: 4),
                .init(id: 12, groupId: 19, day: 2),
                .init(id: 13, groupId: 21, day: 4)
            ]
        )
        XCTAssertEqual(orphans, [19, 21])
    }
}
