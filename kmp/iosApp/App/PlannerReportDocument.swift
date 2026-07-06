import SwiftUI
import MiGestorKit

#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// Construye el contenido del informe de planificación (texto maquetado, listo
/// para paginar con `PlannerReportPDFRenderer`). Plantilla sobria pensada para
/// entregar a jefatura/inspección: sesiones planificadas vs. impartidas,
/// objetivos, estado de diarios, incidencias y una línea de firma/fecha.
///
/// Aislado a `@MainActor` porque `groupSection` llama a `vm.dayLabel(for:)`/
/// `vm.timeLabel(for:)`, que están aislados al actor principal (el ViewModel
/// lo está por completo); solo se invoca desde `PlannerSummaryDashboard`, ya
/// en el hilo principal.
@MainActor
enum PlannerReportDocument {
    static func build(
        rangeData: PlannerRangeData,
        groupFilterName: String?,
        vm: PlannerWorkspaceViewModel
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(paragraph("Informe de planificación docente", style: .title))
        result.append(paragraph(rangeData.rangeLabel, style: .subtitle))
        result.append(paragraph("Grupo: \(groupFilterName ?? "Todos los grupos")", style: .meta))
        result.append(paragraph("Generado el \(Self.generationDateText)", style: .meta))
        result.append(spacer())

        result.append(summarySection(rangeData: rangeData))
        result.append(spacer())

        let sessionsByGroup = Dictionary(grouping: rangeData.sessions, by: \.groupName)
        for groupName in sessionsByGroup.keys.sorted() {
            let sessions = (sessionsByGroup[groupName] ?? []).sorted {
                if $0.weekNumber == $1.weekNumber {
                    if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                    return $0.dayOfWeek < $1.dayOfWeek
                }
                return $0.weekNumber < $1.weekNumber
            }
            result.append(groupSection(groupName: groupName, sessions: sessions, rangeData: rangeData, vm: vm))
        }

        result.append(spacer())
        result.append(signatureLine())

        return result
    }

    private static var generationDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private static func summarySection(rangeData: PlannerRangeData) -> NSAttributedString {
        let sessions = rangeData.sessions
        let completed = sessions.count { $0.status == .completed }
        let cancelled = sessions.count { $0.status == .cancelled }
        let notDelivered = sessions.count { isPastAndNotDelivered($0, rangeData: rangeData) }
        let pendingJournal = sessions.count { session in
            session.status == .completed && rangeData.journalSummaryBySessionId[session.id]?.status != .completed
        }

        let result = NSMutableAttributedString()
        result.append(paragraph("Resumen", style: .sectionHeader))
        result.append(paragraph("\(sessions.count) sesiones planificadas · \(completed) impartidas · \(cancelled) canceladas", style: .body))
        if notDelivered > 0 {
            result.append(paragraph("\(notDelivered) sesiones de semanas ya pasadas sin marcar como impartidas.", style: .bodyWarning))
        }
        if pendingJournal > 0 {
            result.append(paragraph("\(pendingJournal) diarios de sesión pendientes de cerrar.", style: .bodyWarning))
        }
        return result
    }

    private static func groupSection(
        groupName: String,
        sessions: [PlanningSession],
        rangeData: PlannerRangeData,
        vm: PlannerWorkspaceViewModel
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(paragraph(groupName, style: .sectionHeader))

        for session in sessions {
            let dayLabel = vm.dayLabel(for: Int(session.dayOfWeek))
            let time = session.startTime.flatMap { start in
                session.endTime.map { end in "\(start)-\(end)" }
            } ?? vm.timeLabel(for: Int(session.period))
            let unit = session.teachingUnitName.nilIfBlank ?? "Sesión sin título"
            let statusText = sessionStatusText(session, rangeData: rangeData)

            result.append(paragraph("\(dayLabel) \(time) — \(unit) — \(statusText)", style: .body))

            let objective = session.objectives.nilIfBlank ?? session.activities.nilIfBlank
            if let objective {
                result.append(paragraph("Objetivo: \(objective)", style: .bodyIndented))
            }

            if let summary = rangeData.journalSummaryBySessionId[session.id], !summary.incidentTags.isEmpty {
                result.append(paragraph("Incidencias: \(summary.incidentTags.joined(separator: ", "))", style: .bodyIndentedWarning))
            }
        }
        return result
    }

    private static func sessionStatusText(_ session: PlanningSession, rangeData: PlannerRangeData) -> String {
        if session.status == .cancelled { return "Cancelada" }
        if session.status == .completed {
            let journalStatus = rangeData.journalSummaryBySessionId[session.id]?.status
            return journalStatus == .completed ? "Impartida (diario cerrado)" : "Impartida (diario pendiente)"
        }
        if isPastAndNotDelivered(session, rangeData: rangeData) {
            return "No impartida"
        }
        return "Planificada"
    }

    private static func isPastAndNotDelivered(_ session: PlanningSession, rangeData: PlannerRangeData) -> Bool {
        guard session.status != .completed, session.status != .cancelled else { return false }
        let sessionWeek = PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber))
        let currentWeek = PlannerGanttWeek(date: Date())
        return sessionWeek.weeks(until: currentWeek) > 0
    }

    private static func signatureLine() -> NSAttributedString {
        paragraph("Firma: _________________________________          Fecha: _____ / _____ / _________", style: .meta)
    }

    private static func spacer() -> NSAttributedString {
        NSAttributedString(string: "\n")
    }

    private enum TextStyle {
        case title, subtitle, meta, sectionHeader, body, bodyWarning, bodyIndented, bodyIndentedWarning
    }

    private static func paragraph(_ text: String, style: TextStyle) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = spacingBefore(style)
        paragraphStyle.paragraphSpacing = spacingAfter(style)
        if style == .bodyIndented || style == .bodyIndentedWarning {
            paragraphStyle.firstLineHeadIndent = 16
            paragraphStyle.headIndent = 16
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style),
            .foregroundColor: color(for: style),
            .paragraphStyle: paragraphStyle
        ]
        return NSAttributedString(string: text + "\n", attributes: attributes)
    }

    private static func spacingBefore(_ style: TextStyle) -> CGFloat {
        style == .sectionHeader ? 10 : 0
    }

    private static func spacingAfter(_ style: TextStyle) -> CGFloat {
        switch style {
        case .title: return 4
        case .sectionHeader: return 4
        default: return 2
        }
    }

    private static func font(for style: TextStyle) -> PlatformFont {
        switch style {
        case .title: return .boldSystemFont(ofSize: 20)
        case .subtitle: return .systemFont(ofSize: 13, weight: .medium)
        case .meta: return .systemFont(ofSize: 10)
        case .sectionHeader: return .boldSystemFont(ofSize: 14)
        case .body, .bodyWarning, .bodyIndented, .bodyIndentedWarning: return .systemFont(ofSize: 11)
        }
    }

    private static func color(for style: TextStyle) -> PlatformColor {
        switch style {
        case .title, .sectionHeader: return .black
        case .subtitle, .body, .bodyIndented: return PlatformColor(white: 0.15, alpha: 1)
        case .meta: return PlatformColor(white: 0.4, alpha: 1)
        case .bodyWarning, .bodyIndentedWarning: return PlatformColor(red: 0.62, green: 0.31, blue: 0.0, alpha: 1)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
