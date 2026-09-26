import XCTest
@testable import MiGestorKMPMac

final class CooperativeGroupAndCalibrationTests: XCTestCase {

    // MARK: - Tests de Generación de Grupos Cooperativos

    func testHeterogeneousGroupingBalancesAverages() {
        let service = CooperativeGroupGeneratorService()
        // 12 alumnos con notas del 1 al 10
        let students: [CooperativeCandidateStudent] = (1...12).map { id in
            CooperativeCandidateStudent(
                id: Int64(id),
                name: "Alumno \(id)",
                average: Double(id), // 1.0, 2.0, ..., 12.0
                gender: id % 2 == 0 ? "F" : "M"
            )
        }

        let config = CooperativeGroupingConfiguration(
            strategy: .heterogeneous,
            targetGroupCount: 3,
            balanceGender: false,
            groupNamePrefix: "Equipo"
        )

        let result = service.generateGroups(students: students, configuration: config)

        XCTAssertEqual(result.groups.count, 3)
        for group in result.groups {
            XCTAssertEqual(group.members.count, 4)
            XCTAssertNotNil(group.averageScore)
        }

        // Con distribución serpenteante (12, 11, 10 / 7, 8, 9 / 6, 5, 4 / 1, 2, 3), las medias son muy cercanas
        let avgs = result.groups.compactMap(\.averageScore)
        let minAvg = avgs.min() ?? 0
        let maxAvg = avgs.max() ?? 0
        XCTAssertLessThanOrEqual(maxAvg - minAvg, 1.0, "La diferencia entre medias en agrupamiento heterogéneo debe ser mínima")
    }

    func testHomogeneousGroupingPartitionsTiers() {
        let service = CooperativeGroupGeneratorService()
        let students: [CooperativeCandidateStudent] = (1...9).map { id in
            CooperativeCandidateStudent(
                id: Int64(id),
                name: "Alumno \(id)",
                average: Double(id)
            )
        }

        let config = CooperativeGroupingConfiguration(
            strategy: .homogeneous,
            targetGroupCount: 3,
            groupNamePrefix: "Nivel"
        )

        let result = service.generateGroups(students: students, configuration: config)

        XCTAssertEqual(result.groups.count, 3)
        // Grupo 1 debe tener las notas más altas (9, 8, 7)
        let g1Avg = result.groups[0].averageScore ?? 0
        // Grupo 3 debe tener las notas más bajas (3, 2, 1)
        let g3Avg = result.groups[2].averageScore ?? 0

        XCTAssertGreaterThan(g1Avg, g3Avg)
        XCTAssertEqual(g1Avg, 8.0)
        XCTAssertEqual(g3Avg, 2.0)
    }

    func testToImportedNotebookGroupsAdapter() {
        let service = CooperativeGroupGeneratorService()
        let students = [
            CooperativeCandidateStudent(id: 101, name: "Lucas"),
            CooperativeCandidateStudent(id: 102, name: "Sara")
        ]
        let result = service.generateGroups(
            students: students,
            configuration: CooperativeGroupingConfiguration(targetGroupCount: 1)
        )

        let imported = service.toImportedNotebookGroups(result: result)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].members.count, 2)
        XCTAssertEqual(imported[0].members[0].matchedStudentId, 101)
        XCTAssertEqual(imported[0].members[1].matchedStudentId, 102)
    }

    // MARK: - Tests de Calibración Docente (ML Feedback Loop)

    @MainActor
    func testCalibrationSuppressionAndThresholds() {
        // Usamos una suite de UserDefaults aislada para no afectar la app
        let testDefaults = UserDefaults(suiteName: "test_ml_calibration_\(UUID().uuidString)")!
        let service = PedagogicalMLCalibrationService(userDefaults: testDefaults)

        let studentId: Int64 = 42
        let classId: Int64 = 10
        let pattern = EducationalPatternType.silentDisengagement

        // 1. Por defecto (.balanced, umbral 0.70):
        // Con confianza 0.65 -> debe suprimirse
        XCTAssertTrue(service.isSignalSuppressed(studentId: studentId, classId: classId, patternType: pattern, confidence: 0.65))
        // Con confianza 0.85 -> NO debe suprimirse
        XCTAssertFalse(service.isSignalSuppressed(studentId: studentId, classId: classId, patternType: pattern, confidence: 0.85))

        // 2. Si cambiamos umbral a .sensitive (0.50):
        service.setConfidenceThreshold(.sensitive)
        XCTAssertFalse(service.isSignalSuppressed(studentId: studentId, classId: classId, patternType: pattern, confidence: 0.65))

        // 3. Marcar como atendida / justificada con motivo:
        service.setStatus(
            studentId: studentId,
            classId: classId,
            patternType: pattern,
            status: .addressed,
            reason: .personalCircumstance,
            note: "Alumno con lesión justificada"
        )

        // Ahora, aunque la confianza sea 0.99, debe suprimirse de las alertas activas
        XCTAssertTrue(service.isSignalSuppressed(studentId: studentId, classId: classId, patternType: pattern, confidence: 0.99))

        // El registro existe
        let record = service.record(for: studentId, classId: classId, patternType: pattern)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.status, .addressed)
        XCTAssertEqual(record?.reason, .personalCircumstance)

        // 4. Reactivar la señal:
        service.reactivateSignal(studentId: studentId, classId: classId, patternType: pattern)
        XCTAssertFalse(service.isSignalSuppressed(studentId: studentId, classId: classId, patternType: pattern, confidence: 0.99))
    }
}
