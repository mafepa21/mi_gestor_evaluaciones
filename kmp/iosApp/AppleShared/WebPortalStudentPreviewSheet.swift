import Foundation
import SwiftUI
import MiGestorKit

/// Modelo de solo lectura que refleja exactamente el tablón JSON que vería un alumno
/// ahora mismo, construido a partir de `WebPortalPublisher.buildBoard` sin subir nada.
struct WebPortalStudentPreviewData: Equatable {
    struct PendingTask: Identifiable, Equatable {
        let id: String
        let title: String
        let context: String
        let typeLabel: String
        let deadlineText: String?
    }

    struct DoneTask: Identifiable, Equatable {
        let id: String
        let title: String
    }

    struct GradeItem: Identifiable, Equatable {
        let id: String
        let title: String
        let typeLabel: String
        let valueText: String
        let levelText: String?
        let comment: String?
    }

    struct PhysicalTestSummary: Identifiable, Equatable {
        let id: String
        let name: String
        let capacity: String
        let currentMark: String
        let previousMark: String?
        let diffText: String?
        let improved: Bool
        let scoreText: String?
    }

    struct AttendanceSummary: Equatable {
        let absences: Int
        let lates: Int
        let excused: Int
        let noKit: Int
        let recent: [(date: String, label: String)]

        static func == (lhs: AttendanceSummary, rhs: AttendanceSummary) -> Bool {
            lhs.absences == rhs.absences && lhs.lates == rhs.lates
                && lhs.excused == rhs.excused && lhs.noKit == rhs.noKit
                && lhs.recent.count == rhs.recent.count
        }
    }

    struct HistoricalTermSummary: Identifiable, Equatable {
        let id: String
        let title: String
        let valueText: String
        let levelText: String?
    }

    struct GradeSubject: Identifiable, Equatable {
        let id: String
        let title: String
        let averageValue: String?
        let averageLevel: String?
        let items: [GradeItem]
        let historical: [HistoricalTermSummary]
    }

    struct PassportStopSummary: Identifiable, Equatable {
        let id: String
        let title: String
        let done: Bool
    }

    struct PassportSummary: Identifiable, Equatable {
        let id: String
        let title: String
        let completed: Int
        let total: Int
        let stops: [PassportStopSummary]
    }

    struct TournamentSummary: Identifiable, Equatable {
        let id: String
        let title: String
        let statusLabel: String
        let myTeamLabel: String?
        let myTeamSummary: String?
        let nextMatchSummary: String?
        let recentResults: [String]
    }

    let studentName: String
    let groupName: String
    let accountStatus: WebPortalAccountStatus
    let pendingTasks: [PendingTask]
    let doneTasks: [DoneTask]
    let gradeSubjects: [GradeSubject]
    let tournaments: [TournamentSummary]
    let physicalTests: [PhysicalTestSummary]
    let attendance: AttendanceSummary?
    let passports: [PassportSummary]
    let hiddenGradeColumnCount: Int
    let hiddenTournamentCount: Int

    var totalVisibleGrades: Int {
        gradeSubjects.reduce(0) { $0 + $1.items.count }
    }

    var hasPEData: Bool {
        !physicalTests.isEmpty || attendance != nil || !passports.isEmpty
    }

    var isCompletelyEmpty: Bool {
        pendingTasks.isEmpty && doneTasks.isEmpty && gradeSubjects.isEmpty && tournaments.isEmpty && !hasPEData
    }

    static func empty(
        studentName: String = "",
        groupName: String = "",
        accountStatus: WebPortalAccountStatus = .sinInvitar
    ) -> WebPortalStudentPreviewData {
        WebPortalStudentPreviewData(
            studentName: studentName,
            groupName: groupName,
            accountStatus: accountStatus,
            pendingTasks: [],
            doneTasks: [],
            gradeSubjects: [],
            tournaments: [],
            physicalTests: [],
            attendance: nil,
            passports: [],
            hiddenGradeColumnCount: 0,
            hiddenTournamentCount: 0
        )
    }

    /// Parsea el JSON exacto producido por `WebPortalPublisher.buildBoard`.
    static func parse(
        boardData: Data,
        studentName: String,
        groupName: String,
        accountStatus: WebPortalAccountStatus,
        hiddenGradeColumnCount: Int = 0,
        hiddenTournamentCount: Int = 0
    ) -> WebPortalStudentPreviewData {
        guard let root = (try? JSONSerialization.jsonObject(with: boardData)) as? [String: Any] else {
            return .empty(studentName: studentName, groupName: groupName, accountStatus: accountStatus)
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "es_ES")
        dayFmt.dateFormat = "d MMM"

        let pendingRaw = root["pendientes"] as? [[String: Any]] ?? []
        let pendingTasks: [PendingTask] = pendingRaw.enumerated().map { idx, item in
            let title = item["titulo"] as? String ?? "Actividad"
            let context = item["contexto"] as? String ?? groupName
            let typeKey = item["tipo"] as? String ?? "autoevaluacion"
            let typeLabel: String = switch typeKey {
            case "coevaluacion": "Coevaluación"
            case "pasaporte": "Pasaporte"
            default: "Autoevaluación"
            }
            let deadlineText: String? = (item["plazo"] as? String).flatMap { iso.date(from: $0) }.map {
                "Hasta el \(dayFmt.string(from: $0))"
            }
            return PendingTask(
                id: "p-\(idx)-\(title)",
                title: title,
                context: context,
                typeLabel: typeLabel,
                deadlineText: deadlineText
            )
        }

        let doneRaw = root["hechos"] as? [[String: Any]] ?? []
        let doneTasks: [DoneTask] = doneRaw.enumerated().map { idx, item in
            DoneTask(id: "d-\(idx)", title: item["titulo"] as? String ?? "Actividad")
        }

        var gradeSubjects: [GradeSubject] = []
        if let notas = root["notas"] as? [String: Any],
           let materias = notas["materias"] as? [[String: Any]] {
            let numFmt = NumberFormatter()
            numFmt.locale = Locale(identifier: "es_ES")
            numFmt.minimumFractionDigits = 0
            numFmt.maximumFractionDigits = 1

            for (mIdx, subject) in materias.enumerated() {
                let subjectTitle = (subject["materia"] as? String)
                    ?? (subject["grupo"] as? String)
                    ?? groupName
                let mediaDict = subject["media"] as? [String: Any]
                let avgValue = (mediaDict?["valor"] as? Double).flatMap { numFmt.string(from: NSNumber(value: $0)) }
                let avgLevel = mediaDict?["nivel"] as? String

                let activities = subject["actividades"] as? [[String: Any]] ?? []
                let items: [GradeItem] = activities.enumerated().map { aIdx, act in
                    let title = act["titulo"] as? String ?? "Nota"
                    let tipo = act["tipo"] as? String ?? "nota"
                    let typeLabel: String = switch tipo {
                    case "rubrica": "Rúbrica"
                    case "prueba_fisica": "Prueba física"
                    default: "Nota"
                    }
                    let valText: String
                    if let d = act["valor"] as? Double, let formatted = numFmt.string(from: NSNumber(value: d)) {
                        valText = formatted
                    } else if let s = act["valor"] as? String {
                        valText = s
                    } else {
                        valText = "—"
                    }
                    return GradeItem(
                        id: "g-\(mIdx)-\(aIdx)-\(title)",
                        title: title,
                        typeLabel: typeLabel,
                        valueText: valText,
                        levelText: act["nivel"] as? String,
                        comment: act["comentario"] as? String
                    )
                }
                let histRaw = subject["historico"] as? [[String: Any]] ?? []
                let historical: [HistoricalTermSummary] = histRaw.enumerated().compactMap { hIdx, h in
                    guard let title = h["titulo"] as? String,
                          let m = h["media"] as? [String: Any],
                          let val = m["valor"] as? Double,
                          let formatted = numFmt.string(from: NSNumber(value: val)) else { return nil }
                    return HistoricalTermSummary(
                        id: "h-\(mIdx)-\(hIdx)",
                        title: title,
                        valueText: formatted,
                        levelText: m["nivel"] as? String
                    )
                }
                if !items.isEmpty || !historical.isEmpty {
                    gradeSubjects.append(GradeSubject(
                        id: "m-\(mIdx)-\(subjectTitle)",
                        title: subjectTitle,
                        averageValue: avgValue,
                        averageLevel: avgLevel,
                        items: items,
                        historical: historical
                    ))
                }
            }
        }

        var tournaments: [TournamentSummary] = []
        if let torneos = root["torneos"] as? [String: Any],
           let lista = torneos["lista"] as? [[String: Any]] {
            for (tIdx, item) in lista.enumerated() {
                let id = item["id"] as? String ?? "t-\(tIdx)"
                let title = item["titulo"] as? String ?? "Torneo"
                let estadoKey = item["estado"] as? String ?? "en_curso"
                let statusLabel: String = switch estadoKey {
                case "finalizado": "Finalizado"
                case "sin_empezar": "Sin empezar"
                default: "En curso"
                }
                let miEquipo = item["miEquipo"] as? [String: Any]
                let myLabel = miEquipo?["etiqueta"] as? String
                let mySummary = miEquipo?["resumen"] as? String

                var nextMatchSummary: String?
                if let next = item["proximoPartido"] as? [String: Any] {
                    let local = next["local"] as? String ?? ""
                    let visitante = next["visitante"] as? String ?? ""
                    let fase = next["fase"] as? String
                    if !local.isEmpty && !visitante.isEmpty {
                        nextMatchSummary = fase.map { "\($0) · \(local) vs \(visitante)" } ?? "\(local) vs \(visitante)"
                    }
                }

                var recentResults: [String] = []
                if let rondas = item["rondas"] as? [[String: Any]] {
                    for ronda in rondas {
                        let partidos = ronda["partidos"] as? [[String: Any]] ?? []
                        for p in partidos {
                            guard let ml = p["marcadorLocal"] as? Int,
                                  let mv = p["marcadorVisitante"] as? Int,
                                  let local = p["local"] as? String,
                                  let visitante = p["visitante"] as? String else { continue }
                            let isMine = (p["esMio"] as? Bool) == true
                            if isMine || myLabel == nil {
                                recentResults.append("\(local) \(ml) – \(mv) \(visitante)")
                            }
                        }
                    }
                }
                tournaments.append(TournamentSummary(
                    id: id,
                    title: title,
                    statusLabel: statusLabel,
                    myTeamLabel: myLabel,
                    myTeamSummary: mySummary,
                    nextMatchSummary: nextMatchSummary,
                    recentResults: Array(recentResults.suffix(3).reversed())
                ))
            }
        }

        var physicalTests: [PhysicalTestSummary] = []
        if let fisica = root["fisica"] as? [String: Any],
           let pruebas = fisica["pruebas"] as? [[String: Any]] {
            let numFmt = NumberFormatter()
            numFmt.locale = Locale(identifier: "es_ES")
            numFmt.minimumFractionDigits = 0
            numFmt.maximumFractionDigits = 1
            for (idx, p) in pruebas.enumerated() {
                let actual = p["actual"] as? [String: Any]
                let anterior = p["anterior"] as? [String: Any]
                let scoreText = (actual?["nota"] as? Double).flatMap { numFmt.string(from: NSNumber(value: $0)) }
                physicalTests.append(PhysicalTestSummary(
                    id: p["id"] as? String ?? "pe-\(idx)",
                    name: p["nombre"] as? String ?? "Prueba",
                    capacity: p["capacidad"] as? String ?? "",
                    currentMark: actual?["marca"] as? String ?? "—",
                    previousMark: anterior?["marca"] as? String,
                    diffText: p["diferencia"] as? String,
                    improved: (p["mejora"] as? Bool) == true,
                    scoreText: scoreText
                ))
            }
        }

        var attendance: AttendanceSummary?
        if let att = root["asistencia"] as? [String: Any],
           let resumen = att["resumen"] as? [String: Any] {
            let recRaw = att["recientes"] as? [[String: Any]] ?? []
            let recent: [(String, String)] = recRaw.prefix(5).map { r in
                let date = r["fecha"] as? String ?? ""
                let label: String = switch (r["tipo"] as? String ?? "") {
                case "retraso": "Retraso"
                case "justificada": "Justificada"
                case "sin_equipacion": "Sin equipación"
                default: "Falta"
                }
                return (date, label)
            }
            attendance = AttendanceSummary(
                absences: resumen["faltas"] as? Int ?? 0,
                lates: resumen["retrasos"] as? Int ?? 0,
                excused: resumen["justificadas"] as? Int ?? 0,
                noKit: resumen["sinEquipacion"] as? Int ?? 0,
                recent: recent
            )
        }

        var passports: [PassportSummary] = []
        if let pas = root["pasaporte"] as? [String: Any],
           let lista = pas["lista"] as? [[String: Any]] {
            for (pIdx, p) in lista.enumerated() {
                let stopsRaw = p["paradas"] as? [[String: Any]] ?? []
                let stops = stopsRaw.enumerated().map { sIdx, s in
                    PassportStopSummary(
                        id: "ps-\(pIdx)-\(sIdx)",
                        title: s["titulo"] as? String ?? "Parada",
                        done: (s["hecha"] as? Bool) == true
                    )
                }
                if !stops.isEmpty {
                    passports.append(PassportSummary(
                        id: "p-\(pIdx)",
                        title: p["titulo"] as? String ?? "Pasaporte",
                        completed: p["completadas"] as? Int ?? stops.filter(\.done).count,
                        total: p["total"] as? Int ?? stops.count,
                        stops: stops
                    ))
                }
            }
        }

        return WebPortalStudentPreviewData(
            studentName: studentName,
            groupName: groupName,
            accountStatus: accountStatus,
            pendingTasks: pendingTasks,
            doneTasks: doneTasks,
            gradeSubjects: gradeSubjects,
            tournaments: tournaments,
            physicalTests: physicalTests,
            attendance: attendance,
            passports: passports,
            hiddenGradeColumnCount: hiddenGradeColumnCount,
            hiddenTournamentCount: hiddenTournamentCount
        )
    }
}

// MARK: - Carga local desde KmpBridge (sin red ni publicación)

extension KmpBridge {
    /// Construye la vista previa exacta del tablón de un alumno en local.
    /// Todas las llamadas `suspend` de Kotlin corren en `@MainActor`; no toca el servidor.
    @MainActor
    func portalStudentPreview(
        classId: Int64,
        student: WebPortalStudent,
        status: WebPortalAccountStatus
    ) async -> WebPortalStudentPreviewData {
        let groupName = classes.first(where: { $0.id == classId })?.name ?? ""
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        // 1. Formularios abiertos del alumno (mismo filtro que republishPortalBoards)
        var forms: [WebPortalFormEntry] = []
        if let instancias = try? await container.webSubmissionsRepository.listAllFormInstances() {
            for instancia in instancias where !instancia.revoked && !instancia.archived && instancia.expiresAtEpochMs > nowMs {
                let alumnado = (try? await container.classesRepository.listStudentsInClass(classId: instancia.classId)) ?? []
                guard alumnado.contains(where: { $0.id == student.id }),
                      let snapshot = await loadWebSubmissionSnapshot(formInstanceId: instancia.formInstanceId) else { continue }
                let links = WebSubmissionPrivateLinksStore.readLinks(
                    formInstanceId: instancia.formInstanceId,
                    snapshot: snapshot,
                    students: alumnado
                )
                guard let link = links.first(where: { $0.studentId == student.id }) else { continue }
                let ledger = (try? await container.webSubmissionsRepository.listLedgerForForm(formInstanceId: instancia.formInstanceId)) ?? []
                let doneStudents = Set(ledger.filter { $0.status == "IMPORTED" }.compactMap { entry in
                    entry.alias.flatMap { snapshot.studentIdByAlias[$0] }
                })
                let formGroupName = classes.first(where: { $0.id == instancia.classId })?.name ?? groupName
                forms.append(WebPortalFormEntry(
                    title: instancia.title,
                    context: formGroupName,
                    mode: instancia.mode,
                    expiresAt: Date(timeIntervalSince1970: Double(instancia.expiresAtEpochMs) / 1000),
                    url: link.url.absoluteString,
                    done: doneStudents.contains(student.id)
                ))
            }
        }

        // 2. Notas visibles del grupo (mismo bloque que el publicador)
        let gradeBlocks = await portalGradeBlocks(extraClassIds: [classId])
        let notas = gradeBlocks.notas(for: student.id)
        let gradeOverview = await portalGradeOverview(classId: classId, tabId: nil)
        let gradeSettings = WebPortalGradeSettings.standardURL().map { WebPortalGradeSettings.load(fileURL: $0) } ?? WebPortalGradeSettings()
        let groupGradeSettings = gradeSettings[classId]
        let totalGradeCols = gradeOverview?.columns.count ?? 0
        let visibleGradeCols = gradeOverview?.columns.filter { groupGradeSettings.isVisible(columnId: $0.id) }.count ?? 0
        let hiddenGradeCols = max(0, totalGradeCols - visibleGradeCols)

        // 3. Torneos visibles del grupo (mismo bloque que el publicador)
        let tournamentBlocks = await portalTournamentBlocks(extraClassIds: [classId])
        let torneos = tournamentBlocks.torneos(for: student.id)
        let tournamentOverview = await portalTournamentOverview(classId: classId)
        let tournamentSettings = WebPortalTournamentSettings.standardURL().map { WebPortalTournamentSettings.load(fileURL: $0) } ?? WebPortalTournamentSettings()
        let groupTournamentSettings = tournamentSettings[classId]
        let totalTournaments = tournamentOverview?.tournaments.count ?? 0
        let visibleTournaments = tournamentOverview?.tournaments.filter { groupTournamentSettings.isVisible(tournamentId: $0.id) }.count ?? 0
        let hiddenTournaments = max(0, totalTournaments - visibleTournaments)

        // 4. EF, asistencia y pasaporte visibles del grupo
        let peBlocks = await portalPEBlocks(extraClassIds: [classId])
        let fisica = peBlocks.fisica(for: student.id)
        let asistencia = peBlocks.asistencia(for: student.id)
        let pasaporte = peBlocks.pasaporte(for: student.id)

        let portalId = WebPortalStore.standard()?[student.id]?.portalId ?? "preview-\(student.id)"
        guard let boardData = try? WebPortalPublisher.buildBoard(
            portalId: portalId,
            forms: forms,
            notas: notas,
            torneos: torneos,
            fisica: fisica,
            asistencia: asistencia,
            pasaporte: pasaporte,
            now: now
        ) else {
            return .empty(studentName: student.fullName, groupName: groupName, accountStatus: status)
        }

        return WebPortalStudentPreviewData.parse(
            boardData: boardData,
            studentName: student.fullName,
            groupName: groupName,
            accountStatus: status,
            hiddenGradeColumnCount: hiddenGradeCols,
            hiddenTournamentCount: hiddenTournaments
        )
    }
}

// MARK: - Hoja de vista previa (V1 / V2)

struct WebPortalStudentPreviewSheet: View {
    let student: WebPortalStudent
    let groupName: String
    let accountStatus: WebPortalAccountStatus
    let loadPreview: () async -> WebPortalStudentPreviewData

    @Environment(\.dismiss) private var dismiss
    @State private var data: WebPortalStudentPreviewData?
    @State private var section: PreviewSection = .hacer

    enum PreviewSection: String, CaseIterable, Identifiable {
        case hacer = "Para hacer"
        case notas = "Mis notas"
        case ef = "Mi EF"
        case torneo = "Torneo"
        var id: String { rawValue }
    }

    private let paperBg = Color(red: 0.949, green: 0.933, blue: 0.882)       // #f2eee1
    private let paperCard = Color(red: 0.984, green: 0.973, blue: 0.933)     // #fbf8ee
    private let pistaGreen = Color(red: 0.059, green: 0.239, blue: 0.180)    // #0f3d2e
    private let inkSecondary = Color(red: 0.310, green: 0.361, blue: 0.329)  // #4f5c54

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            banner
            if let data {
                if data.isCompletelyEmpty {
                    emptyNotebook
                } else {
                    notebookBody(data)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando vista previa local…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 700, maxWidth: 820, minHeight: 420, idealHeight: 520, maxHeight: 620)
        #else
        .frame(minWidth: 500, minHeight: 460)
        #endif
        .task {
            let loaded = await loadPreview()
            data = loaded
            if loaded.pendingTasks.isEmpty && loaded.doneTasks.isEmpty {
                if !loaded.gradeSubjects.isEmpty {
                    section = .notas
                } else if !loaded.tournaments.isEmpty {
                    section = .torneo
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName).font(.title3.weight(.bold))
                Text(subtitleText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cerrar") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var subtitleText: String {
        var parts = [groupName, accountStatus == .activada ? "Cuenta activada" : "Aún sin cuenta activada"]
        if let data {
            parts.append("\(data.pendingTasks.count) pendientes")
            parts.append("\(data.totalVisibleGrades) notas")
            if !data.tournaments.isEmpty {
                parts.append("\(data.tournaments.count) \(data.tournaments.count == 1 ? "torneo" : "torneos")")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vista previa local · Así lo vería \(student.firstName) ahora mismo (no se ha publicado nada).")
                    .font(.footnote.weight(.semibold))
                if let hiddenSummary = hiddenSummaryText {
                    Text(hiddenSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var hiddenSummaryText: String? {
        guard let data else { return nil }
        var pieces: [String] = []
        if data.hiddenGradeColumnCount > 0 {
            pieces.append("\(data.hiddenGradeColumnCount) \(data.hiddenGradeColumnCount == 1 ? "columna oculta" : "columnas ocultas")")
        }
        if data.hiddenTournamentCount > 0 {
            pieces.append("\(data.hiddenTournamentCount) \(data.hiddenTournamentCount == 1 ? "torneo oculto" : "torneos ocultos")")
        }
        return pieces.isEmpty ? nil : "\(pieces.joined(separator: " y ")) no aparecen en su móvil."
    }

    private var emptyNotebook: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(pistaGreen, lineWidth: 3)
                    .frame(width: 88, height: 88)
                Text("AL DÍA")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(pistaGreen)
                    .rotationEffect(.degrees(-8))
            }
            Text("No tienes nada pendiente")
                .font(.title3.weight(.bold))
                .foregroundStyle(pistaGreen)
            Text("Cuando tu docente publique algo, aparecerá aquí.")
                .font(.callout)
                .foregroundStyle(inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        .padding(24)
        .background(paperBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(pistaGreen.opacity(0.22), lineWidth: 1)
        )
    }

    private func notebookBody(_ data: WebPortalStudentPreviewData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Sección del alumno", selection: $section) {
                Text("Para hacer (\(data.pendingTasks.count))").tag(PreviewSection.hacer)
                Text("Mis notas (\(data.totalVisibleGrades))").tag(PreviewSection.notas)
                if data.hasPEData {
                    Text("Mi EF (\(data.physicalTests.count))").tag(PreviewSection.ef)
                }
                Text("Torneo (\(data.tournaments.count))").tag(PreviewSection.torneo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    switch section {
                    case .hacer: tasksSection(data)
                    case .notas: gradesSection(data)
                    case .ef: peSection(data)
                    case .torneo: tournamentsSection(data)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(pistaGreen.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tasksSection(_ data: WebPortalStudentPreviewData) -> some View {
        if data.pendingTasks.isEmpty && data.doneTasks.isEmpty {
            sectionEmpty("Sin tareas abiertas ahora mismo.")
        } else {
            ForEach(data.pendingTasks) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.callout.weight(.semibold)).foregroundStyle(pistaGreen)
                        Text([task.typeLabel, task.deadlineText].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(inkSecondary)
                    }
                    Spacer()
                    Text("Pendiente")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pistaGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(pistaGreen.opacity(0.10), in: Capsule())
                }
                .padding(12)
                .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
            }
            if !data.doneTasks.isEmpty {
                Text("Completadas (\(data.doneTasks.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(inkSecondary)
                    .padding(.top, 6)
                ForEach(data.doneTasks) { done in
                    Label(done.title, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(pistaGreen)
                }
            }
        }
    }

    @ViewBuilder
    private func gradesSection(_ data: WebPortalStudentPreviewData) -> some View {
        if data.gradeSubjects.isEmpty {
            sectionEmpty("No hay ninguna nota marcada como visible para este grupo.")
        } else {
            ForEach(data.gradeSubjects) { subject in
                if let avg = subject.averageValue {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tu media actual").font(.callout.weight(.semibold)).foregroundStyle(.white)
                            Text(subject.averageLevel ?? subject.title)
                                .font(.caption).foregroundStyle(.white.opacity(0.82))
                        }
                        Spacer()
                        Text(avg)
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(14)
                    .background(pistaGreen, in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(subject.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.callout.weight(.semibold)).foregroundStyle(pistaGreen)
                                Text([item.typeLabel, item.levelText].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(inkSecondary)
                            }
                            Spacer()
                            Text(item.valueText)
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(pistaGreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(pistaGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if let comment = item.comment, !comment.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("COMENTARIO DEL DOCENTE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color(red: 0.55, green: 0.28, blue: 0.06))
                                Text(comment)
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 0.40, green: 0.22, blue: 0.06))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 1.0, green: 0.96, blue: 0.90), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                    .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
                }
                if !subject.historical.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Evolución del curso")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(pistaGreen)
                        ForEach(subject.historical) { h in
                            HStack {
                                Text(h.title).font(.caption.weight(.semibold)).foregroundStyle(pistaGreen)
                                Spacer()
                                Text([h.valueText, h.levelText].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(inkSecondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func peSection(_ data: WebPortalStudentPreviewData) -> some View {
        ForEach(data.physicalTests) { test in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(test.name).font(.callout.weight(.semibold)).foregroundStyle(pistaGreen)
                    Text(test.capacity).font(.caption).foregroundStyle(inkSecondary)
                    if let prev = test.previousMark {
                        Text("Antes: \(prev) → \(test.currentMark)")
                            .font(.caption2).foregroundStyle(inkSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(test.currentMark)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(pistaGreen)
                    if let diff = test.diffText {
                        Text(diff)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(test.improved ? Color(red: 0.05, green: 0.36, blue: 0.20) : inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background((test.improved ? Color.green : Color.gray).opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(12)
            .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
        }
        if let att = data.attendance {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mi asistencia").font(.callout.weight(.semibold)).foregroundStyle(pistaGreen)
                Text("Faltas: \(att.absences) · Retrasos: \(att.lates) · Justificadas: \(att.excused) · Sin equipación: \(att.noKit)")
                    .font(.caption)
                    .foregroundStyle(inkSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
        }
        ForEach(data.passports) { passport in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(passport.title).font(.callout.weight(.semibold)).foregroundStyle(pistaGreen)
                    Spacer()
                    Text("\(passport.completed) de \(passport.total) paradas")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(pistaGreen)
                }
                ForEach(passport.stops) { stop in
                    Label(stop.title, systemImage: stop.done ? "checkmark.seal.fill" : "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(stop.done ? pistaGreen : inkSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func tournamentsSection(_ data: WebPortalStudentPreviewData) -> some View {
        if data.tournaments.isEmpty {
            sectionEmpty("No hay ningún torneo marcado como visible para este grupo.")
        } else {
            ForEach(data.tournaments) { tournament in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tournament.title).font(.callout.weight(.bold)).foregroundStyle(.white)
                            if let team = tournament.myTeamLabel {
                                let detail = tournament.myTeamSummary.map { "\(team) · \($0)" } ?? team
                                Text("Tu equipo: \(detail)")
                                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        Spacer()
                        Text(tournament.statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    .padding(14)
                    .background(pistaGreen, in: RoundedRectangle(cornerRadius: 12))

                    if let next = tournament.nextMatchSummary {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Próximo partido").font(.caption.weight(.semibold)).foregroundStyle(inkSecondary)
                                Text(next).font(.callout.weight(.semibold)).foregroundStyle(pistaGreen)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(paperCard, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(pistaGreen.opacity(0.14), lineWidth: 1))
                    }

                    ForEach(tournament.recentResults, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(pistaGreen)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(paperCard, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(pistaGreen.opacity(0.12), lineWidth: 1))
                    }
                }
            }
        }
    }

    private func sectionEmpty(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(inkSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
}
