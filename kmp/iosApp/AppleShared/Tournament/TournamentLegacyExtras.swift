import Foundation

/// Datos del módulo antiguo de torneos de Educación Física que el motor no usa pero que se
/// conservan al migrar (`config_json`, clave opcional `legacyExtras`).
/// Los torneos creados desde una Situación de Aprendizaje no la tienen (`nil`).
struct TournamentLegacyExtras: Equatable, Codable, Sendable {
    /// Alumno con su nivel y sus incompatibilidades (autoequilibrado del módulo antiguo).
    struct StudentProfile: Equatable, Codable, Sendable {
        var studentID: String
        var level: String
        var incompatibleStudentIDs: [String]
    }

    var sport: String
    var pointsWin: Int
    var pointsDraw: Int
    var pointsLoss: Int
    var tieBreaker: String
    /// Plantilla original ("Round-robin", "Eliminatoria", "Fase de grupos + eliminatoria").
    var legacyTemplate: String
    /// Estado original ("Borrador", "Activo", "Cerrado", "Archivado").
    var legacyStatus: String
    /// Fecha de creación original (el registro nuevo estrena la suya al guardarse).
    var originalCreatedAt: Date
    /// Color (hex) de cada equipo, por id de equipo.
    var teamColorHexByTeamID: [String: String]
    /// Sesión de EF enlazada a cada partido, por id de partido.
    var linkedSessionIDByMatchID: [String: Int64]
    var studentProfiles: [StudentProfile]
}
