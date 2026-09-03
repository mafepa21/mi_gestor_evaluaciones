import SwiftUI
import PhotosUI
import QuickLook
import MiGestorKit
#if os(macOS)
import AppKit
#endif

// MARK: - Presentation Models & Parser Helper

struct PlannerParsedZone: Identifiable, Equatable {
    let id = UUID()
    let zoneNumber: Int
    let title: String
    let subtitle: String?
    let isTeacherLed: Bool
    let instructions: [String]
}

struct PlannerParsedRotationRound: Identifiable, Equatable {
    let id = UUID()
    let roundNumber: Int
    let durationMinutes: Int?
    let assignments: [String]
    let rawText: String
}

struct PlannerParsedStationActivity: Equatable {
    let title: String?
    let zones: [PlannerParsedZone]
    let rotationRounds: [PlannerParsedRotationRound]
    let transitionNote: String?
    let clilCallout: String?
    let generalNotes: [String]
}

enum PlannerSessionPresentationHelper {
    /// Determina el título específico del juego o tarea motriz para evitar mostrar etiquetas genéricas
    /// repetitivas como "Actividad principal" o "Activación".
    static func displayTitle(for activity: LearningSituationSessionActivityDraft) -> String {
        let raw = activity.activity.trimmingCharacters(in: .whitespacesAndNewlines)
        let phase = activity.phase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let genericTerms: Set<String> = [
            "actividad principal", "explicacion inicial", "explicación inicial",
            "activacion", "activación", "calentamiento", "reflexion", "reflexión",
            "registro", "desarrollo operativo", "narrative", "main", "activation",
            "entry", "reflection", "closure"
        ]
        
        let isGeneric = raw.isEmpty
            || raw.caseInsensitiveCompare(phase) == .orderedSame
            || genericTerms.contains(normalize(raw))
        
        if isGeneric {
            if let extracted = extractGameOrTaskTitle(from: activity.teacherActions) {
                return extracted
            }
            if let extracted = extractGameOrTaskTitle(from: activity.purpose) {
                return extracted
            }
        }
        
        return raw.isEmpty ? (phase.isEmpty ? "Actividad" : phase) : raw
    }
    
    /// Extrae nombres entrecomillados o destacados tipo «Juego...» o *«Juego...»* de las primeras líneas.
    static func extractGameOrTaskTitle(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // 1. Buscar comillas latinas «...» en las primeras 5 líneas
        for line in lines.prefix(5) {
            if let range = line.range(of: #"«([^»]+)»"#, options: .regularExpression) {
                var candidate = String(line[range])
                candidate = candidate.replacingOccurrences(of: "«", with: "")
                    .replacingOccurrences(of: "»", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count >= 3 && candidate.count <= 120 {
                    return candidate
                }
            }
            // 2. Buscar asteriscos *«...»* o *...*
            if let range = line.range(of: #"\*+«?([^»*]+)»?\*+"#, options: .regularExpression) {
                let candidate = line[range]
                    .replacingOccurrences(of: "*", with: "")
                    .replacingOccurrences(of: "«", with: "")
                    .replacingOccurrences(of: "»", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count >= 3 && candidate.count <= 120 && !candidate.lowercased().contains("minuto") {
                    return candidate
                }
            }
        }
        return nil
    }
    
    /// Extrae una consigna CLIL destacada de la actividad si existe.
    static func clilCallout(for activity: LearningSituationSessionActivityDraft) -> String? {
        var raw = activity.clilFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            let text = activity.teacherActions
            if let range = text.range(of: #"(?:Consigna\s+CLIL|CLIL\s+consigna|Consigna)\s*:\s*([^\n\r]+)"#, options: [.regularExpression, .caseInsensitive]) {
                let line = String(text[range])
                raw = line.replacingOccurrences(of: #"^(?:Consigna\s+CLIL|CLIL\s+consigna|Consigna)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard !raw.isEmpty else { return nil }
        let cleaned = raw.replacingOccurrences(of: #"^\s*U[0-9]{2,3}\s*[-·:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
    
    /// Divide el texto de materiales en cápsulas individuales limpias.
    static func materialChips(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let separators = CharacterSet(charactersIn: ",;\n•-")
        let rawParts = trimmed.components(separatedBy: separators)
        
        var results: [String] = []
        var seen = Set<String>()
        
        for part in rawParts {
            var item = part.trimmingCharacters(in: .whitespacesAndNewlines)
            item = item.replacingOccurrences(of: #"^Zona\s+[0-9]+\s*(?:con|:)?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            item = item.replacingOccurrences(of: #"^[0-9]+\.\s*"#, with: "", options: .regularExpression)
            item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard item.count >= 3 && item.count <= 40 else { continue }
            let norm = normalize(item)
            if seen.insert(norm).inserted {
                results.append(item)
            }
        }
        return results
    }
    
    /// Parsea la estructura de zonas y rotaciones de actividades organizadas en circuito.
    static func parseStationActivity(from activity: LearningSituationSessionActivityDraft) -> PlannerParsedStationActivity? {
        let text = activity.teacherActions
        guard text.range(of: #"Zona\s+[1-9]"#, options: .caseInsensitive) != nil else {
            return nil
        }
        
        var zones: [PlannerParsedZone] = []
        var rotationRounds: [PlannerParsedRotationRound] = []
        var transitionNote: String?
        var clilCallout: String? = clilCallout(for: activity)
        var generalNotes: [String] = []
        
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var currentZoneNumber: Int?
        var currentZoneTitle = ""
        var currentZoneSubtitle: String?
        var currentZoneIsTeacher = false
        var currentZoneLines: [String] = []
        
        func flushZone() {
            guard let zNum = currentZoneNumber, !currentZoneTitle.isEmpty else { return }
            zones.append(PlannerParsedZone(
                zoneNumber: zNum,
                title: currentZoneTitle,
                subtitle: currentZoneSubtitle,
                isTeacherLed: currentZoneIsTeacher,
                instructions: currentZoneLines
            ))
            currentZoneNumber = nil
            currentZoneTitle = ""
            currentZoneSubtitle = nil
            currentZoneIsTeacher = false
            currentZoneLines = []
        }
        
        for line in lines {
            // Detectar cabecera de Zona: "Zona 1 (Zona Docente · Test Stork Balance): ..."
            let zonePattern = #"^(?:-\s*)?Zona\s+([1-9])\s*(?:\(([^)]+)\))?\s*:\s*(.*)$"#
            if let match = line.range(of: zonePattern, options: .regularExpression) {
                flushZone()
                let full = String(line[match])
                let regex = try? NSRegularExpression(pattern: zonePattern, options: [])
                if let rMatch = regex?.firstMatch(in: full, options: [], range: NSRange(full.startIndex..., in: full)) {
                    if let nRange = Range(rMatch.range(at: 1), in: full), let num = Int(full[nRange]) {
                        currentZoneNumber = num
                    }
                    var subtitle: String?
                    var parsedTitle = ""
                    if rMatch.range(at: 2).location != NSNotFound, let subRange = Range(rMatch.range(at: 2), in: full) {
                        let rawSub = String(full[subRange])
                        let parts = rawSub.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if parts.count >= 2 {
                            subtitle = parts[0]
                            parsedTitle = parts.dropFirst().joined(separator: " · ")
                        } else {
                            subtitle = rawSub
                        }
                    }
                    if rMatch.range(at: 3).location != NSNotFound, let restRange = Range(rMatch.range(at: 3), in: full) {
                        let rest = String(full[restRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if parsedTitle.isEmpty {
                            parsedTitle = rest.components(separatedBy: ".").first ?? rest
                        }
                        if !rest.isEmpty {
                            currentZoneLines.append(rest)
                        }
                    }
                    currentZoneTitle = parsedTitle.isEmpty ? "Zona \(currentZoneNumber ?? 1)" : parsedTitle
                    currentZoneSubtitle = subtitle
                    currentZoneIsTeacher = (subtitle?.lowercased().contains("docente") == true) || (subtitle?.lowercased().contains("profesor") == true)
                    continue
                }
            }
            
            // Detectar rondas de rotación: "Ronda 2 (8 min): Rotación (20s): G2 a Zona 1..."
            let roundPattern = #"^Ronda\s+([1-9])(?:\s*\(([0-9]+)\s*min\))?\s*:\s*(.*)$"#
            if let match = line.range(of: roundPattern, options: [.regularExpression, .caseInsensitive]) {
                let roundText = String(line[match])
                let regex = try? NSRegularExpression(pattern: roundPattern, options: [.caseInsensitive])
                if let rMatch = regex?.firstMatch(in: roundText, options: [], range: NSRange(roundText.startIndex..., in: roundText)) {
                    let numStr = (rMatch.range(at: 1).location != NSNotFound && Range(rMatch.range(at: 1), in: roundText) != nil)
                        ? String(roundText[Range(rMatch.range(at: 1), in: roundText)!]) : "1"
                    let rNum = Int(numStr) ?? 1
                    var minutes: Int?
                    if rMatch.range(at: 2).location != NSNotFound, let mRange = Range(rMatch.range(at: 2), in: roundText) {
                        minutes = Int(roundText[mRange])
                    }
                    let rest = (rMatch.range(at: 3).location != NSNotFound && Range(rMatch.range(at: 3), in: roundText) != nil)
                        ? String(roundText[Range(rMatch.range(at: 3), in: roundText)!]) : ""
                    
                    if line.contains("20s") || line.contains("transición") || line.contains("Rotación") {
                        transitionNote = "Rotación ágil: 20s entre rondas"
                    }
                    
                    let assignments = rest.components(separatedBy: " y ").flatMap { $0.components(separatedBy: ",") }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    rotationRounds.append(PlannerParsedRotationRound(
                        roundNumber: rNum,
                        durationMinutes: minutes,
                        assignments: assignments,
                        rawText: rest
                    ))
                    continue
                }
            }
            
            // Detectar Consigna CLIL
            if line.lowercased().contains("consigna clil") {
                clilCallout = line.replacingOccurrences(of: #"^Consigna\s+CLIL\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            
            // Línea dentro de una zona abierta
            if currentZoneNumber != nil {
                currentZoneLines.append(line)
            } else {
                generalNotes.append(line)
            }
        }
        flushZone()
        
        guard zones.count >= 2 else { return nil }
        
        let title = extractGameOrTaskTitle(from: text)
        return PlannerParsedStationActivity(
            title: title,
            zones: zones,
            rotationRounds: rotationRounds,
            transitionNote: transitionNote,
            clilCallout: clilCallout,
            generalNotes: generalNotes
        )
    }
    
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Timeline Bar

struct PlannerSessionTimelineBar: View {
    let activities: [LearningSituationSessionActivityDraft]
    let selectedKey: String?
    let tint: Color
    let effectiveMinutes: Int
    let onSelectActivity: (String) -> Void
    
    private var totalMinutes: Int {
        let sum = activities.compactMap(\.plannedMinutes).reduce(0, +)
        return sum > 0 ? sum : max(effectiveMinutes, 1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(activities.enumerated()), id: \.element.activityKey) { index, activity in
                    let isSelected = activity.activityKey == selectedKey
                    let minutes = activity.plannedMinutes ?? (totalMinutes / max(activities.count, 1))
                    let weight = CGFloat(minutes) / CGFloat(totalMinutes)
                    
                    Button {
                        onSelectActivity(activity.activityKey)
                    } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(barColor(for: activity, isSelected: isSelected))
                                .frame(height: isSelected ? 12 : 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
                                )
                            
                            Text("\(minutes)'")
                                .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .monospaced))
                                .foregroundStyle(isSelected ? tint : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(Double(weight * 100))
                    
                    // Insertar marcador de descanso legal tras el Bloque 1 si hay 8 actividades en sesión LONG
                    if activities.count >= 8 && index == 3 {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: 8)
                            Text("15'☕")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 32)
                        .accessibilityLabel("Descanso legal 15 minutos")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(EvaluationDesign.surfaceSoft.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private func barColor(for activity: LearningSituationSessionActivityDraft, isSelected: Bool) -> Color {
        let phase = activity.phase.lowercased()
        if isSelected {
            return tint
        }
        if phase.contains("activacion") || phase.contains("calentamiento") {
            return tint.opacity(0.60)
        }
        if phase.contains("principal") {
            return tint.opacity(0.85)
        }
        if phase.contains("reflexion") || phase.contains("registro") {
            return tint.opacity(0.40)
        }
        return tint.opacity(0.30)
    }
}

// MARK: - Zone Cards View

struct PlannerSessionZoneCardsView: View {
    let station: PlannerParsedStationActivity
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Título de la organización
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x1.below.line.grid.1x2.fill")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text("Organización por Zonas Simultáneas")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(station.zones.count) puestos")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(tint)
            }
            
            // Grid de tarjetas de zona
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(station.zones) { zone in
                        zoneCard(zone)
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(station.zones) { zone in
                        zoneCard(zone)
                    }
                }
            }
            
            // Widget de Rotaciones
            if !station.rotationRounds.isEmpty {
                rotationRoundsPanel
            }
        }
        .padding(14)
        .background(EvaluationDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func zoneCard(_ zone: PlannerParsedZone) -> some View {
        let zoneTint = zoneColor(for: zone)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("ZONA \(zone.zoneNumber)", systemImage: zone.isTeacherLed ? "person.crop.circle.badge.checkmark" : "figure.run")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(zoneTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .foregroundStyle(zoneTint)
                
                Spacer(minLength: 4)
                
                if let subtitle = zone.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Text(zone.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
                .background(EvaluationDesign.border)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(zone.instructions, id: \.self) { line in
                    HStack(alignment: .top, spacing: 5) {
                        Text("•")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(zoneTint)
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(EvaluationDesign.surfaceSoft.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(zoneTint.opacity(0.35), lineWidth: 1)
        )
    }
    
    private var rotationRoundsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text("Esquema de Rotación Rápida")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                if let trans = station.transitionNote {
                    Text(trans)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 8) {
                ForEach(station.rotationRounds) { round in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Ronda \(round.roundNumber)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tint)
                            if let min = round.durationMinutes {
                                Text("\(min) min")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(round.rawText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EvaluationDesign.surfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(EvaluationDesign.border, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.top, 4)
    }
    
    private func zoneColor(for zone: PlannerParsedZone) -> Color {
        if zone.isTeacherLed {
            return Color.teal
        }
        switch zone.zoneNumber {
        case 2: return Color.indigo
        case 3: return Color.orange
        default: return tint
        }
    }
}

// MARK: - CLIL Callout Banner

struct PlannerSessionCLILBanner: View {
    let text: String
    let tint: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("CONSIGNA OPERATIVA / CLIL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                
                Text(cleanText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(0.30), lineWidth: 1)
        )
    }
    
    private var cleanText: String {
        text.replacingOccurrences(of: #"^[🗣️\s*«"]+"#, with: "«", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Material Chips Grid

struct PlannerSessionMaterialChipsView: View {
    let materialsText: String
    let tint: Color
    
    private var chips: [String] {
        PlannerSessionPresentationHelper.materialChips(from: materialsText)
    }
    
    var body: some View {
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Material necesario para pista", systemImage: "shippingbox.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                WorkspaceFlowLayout(spacing: 6) {
                    ForEach(chips, id: \.self) { item in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(tint)
                            Text(item)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(EvaluationDesign.surfaceSoft, in: Capsule())
                        .overlay(Capsule().stroke(EvaluationDesign.border, lineWidth: 1))
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Session Attachments Store & Gallery

struct PlannerSessionAttachment: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let createdAt: Date
    let isImage: Bool
}

@MainActor
final class PlannerSessionAttachmentStore: ObservableObject {
    @Published var attachments: [PlannerSessionAttachment] = []
    
    let sessionId: Int64
    private let directoryURL: URL
    
    init(sessionId: Int64) {
        self.sessionId = sessionId
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.directoryURL = base.appendingPathComponent("SessionAttachments/\(sessionId)", isDirectory: true)
        loadAttachments()
    }
    
    func loadAttachments() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directoryURL.path) else {
            attachments = []
            return
        }
        guard let urls = try? manager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.creationDateKey]) else {
            attachments = []
            return
        }
        
        attachments = urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            let isImg = ["png", "jpg", "jpeg", "heic", "webp"].contains(ext)
            let isDoc = ["pdf", "docx"].contains(ext)
            guard isImg || isDoc else { return nil }
            let attrs = try? manager.attributesOfItem(atPath: url.path)
            let date = attrs?[.creationDate] as? Date ?? Date()
            return PlannerSessionAttachment(
                id: UUID(),
                url: url,
                name: url.lastPathComponent,
                createdAt: date,
                isImage: isImg
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }
    
    func saveImage(data: Data, originalName: String = "croquis.png") {
        let manager = FileManager.default
        try? manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let filename = "\(Date().timeIntervalSince1970)_\(originalName)"
        let destination = directoryURL.appendingPathComponent(filename)
        try? data.write(to: destination)
        loadAttachments()
    }
    
    func deleteAttachment(_ attachment: PlannerSessionAttachment) {
        try? FileManager.default.removeItem(at: attachment.url)
        loadAttachments()
    }
}

struct PlannerSessionAttachmentGalleryView: View {
    @ObservedObject var store: PlannerSessionAttachmentStore
    let tint: Color
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var previewURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Croquis y fotografías de la sesión", systemImage: "photo.stack.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                
                Spacer()
                
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Añadir foto", systemImage: "photo.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Archivo", systemImage: "folder.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if store.attachments.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No hay esquemas ni fotografías adjuntas")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Puedes añadir fotos de la pizarra táctica, croquis del patio o tarjetas de las estaciones.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.attachments) { item in
                            Button {
                                previewURL = item.url
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    if item.isImage, let image = imageFromURL(item.url) {
                                        Image(platformImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 100)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    } else {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(EvaluationDesign.surfaceSoft)
                                                .frame(width: 140, height: 100)
                                            Image(systemName: "doc.richtext.fill")
                                                .font(.title)
                                                .foregroundStyle(tint)
                                        }
                                    }
                                    
                                    Text(item.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 140, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteAttachment(item)
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .quickLookPreview($previewURL)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        store.saveImage(data: data, originalName: "foto_pizarra.jpg")
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            if let urls = try? result.get(), let url = urls.first {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    store.saveImage(data: data, originalName: url.lastPathComponent)
                }
            }
        }
    }
    
    #if os(macOS)
    private func imageFromURL(_ url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }
    #else
    private func imageFromURL(_ url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }
    #endif
}

#if os(macOS)
extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif

// MARK: - Activity Detail Section Cards & Formatted Content

enum PlannerSectionKind: Equatable {
    case purpose
    case teacher
    case students
    case organization
    case timing
    case evidence
    case adaptations
    case slowGroup
    case fastGroup
    case continuity
    case custom(title: String, icon: String)
    
    var icon: String {
        switch self {
        case .purpose: return "target"
        case .teacher: return "person.badge.shield.checkmark.fill"
        case .students: return "person.2.fill"
        case .organization: return "square.split.2x2.fill"
        case .timing: return "clock.arrow.2.circlepath"
        case .evidence: return "checklist"
        case .adaptations: return "accessibility"
        case .slowGroup: return "tortoise.fill"
        case .fastGroup: return "hare.fill"
        case .continuity: return "arrow.right.circle.fill"
        case .custom(_, let icon): return icon
        }
    }
    
    var title: String {
        switch self {
        case .purpose: return "Propósito"
        case .teacher: return "Profesorado"
        case .students: return "Alumnado"
        case .organization: return "Organización y preparación"
        case .timing: return "Temporización y transiciones"
        case .evidence: return "Evidencia y registro"
        case .adaptations: return "Adaptaciones y DUA"
        case .slowGroup: return "Si el grupo va lento"
        case .fastGroup: return "Extensión si termina antes"
        case .continuity: return "Continuidad LONG"
        case .custom(let title, _): return title
        }
    }
    
    var accentColor: Color? {
        switch self {
        case .slowGroup: return Color.orange
        case .fastGroup: return Color.blue
        default: return nil
        }
    }
}

struct PlannerActivityDetailSectionCard: View {
    let kind: PlannerSectionKind
    let text: String
    let tint: Color
    
    private var cleanText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        if !cleanText.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(kind.accentColor ?? tint)
                        .frame(width: 26, height: 26)
                        .background((kind.accentColor ?? tint).opacity(0.12), in: Circle())
                    
                    Text(kind.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                
                PlannerFormattedTextView(text: cleanText, kind: kind, tint: tint)
            }
            .padding(14)
            .background(EvaluationDesign.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(EvaluationDesign.border, lineWidth: 1)
            )
            .padding(.bottom, 10)
        }
    }
}

struct PlannerFormattedTextView: View {
    let text: String
    let kind: PlannerSectionKind
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if kind == .purpose {
                let cleaned = text.replacingOccurrences(of: #"^\s*U[0-9]{2,3}\s*[-·:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Text(cleaned)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let blocks = parseBlocks(from: text)
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
        }
    }
    
    @ViewBuilder
    private func renderBlock(_ block: FormattedTextBlock) -> some View {
        switch block {
        case .zone(let number, let subtitle, let title, let description):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Zona \(number)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(zoneColor(number: number).opacity(0.15), in: Capsule())
                        .foregroundStyle(zoneColor(number: number))
                    
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    
                    if !title.isEmpty {
                        Text("· \(title)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(EvaluationDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(zoneColor(number: number).opacity(0.35), lineWidth: 1)
            )
            
        case .phaseHeader(let title):
            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .padding(.top, 4)
            .padding(.bottom, 2)
            
        case .rotationRound(let number, let duration, let rawText):
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                    Text("Ronda \(number)")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(tint.opacity(0.12), in: Capsule())
                .foregroundStyle(tint)
                
                if let duration {
                    Text("\(duration) min")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                
                Text(rawText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EvaluationDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(EvaluationDesign.border, lineWidth: 1)
            )
            
        case .clilConsigna(let consigna):
            PlannerSessionCLILBanner(text: consigna, tint: tint)
                .padding(.vertical, 2)
            
        case .bulletItem(let item):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                renderStyledText(item)
            }
            
        case .keyValue(let key, let value):
            HStack(alignment: .top, spacing: 4) {
                Text("\(key):")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
        case .paragraph(let text):
            renderStyledText(text)
        }
    }
    
    @ViewBuilder
    private func renderStyledText(_ content: String) -> some View {
        let cleaned = content.replacingOccurrences(of: #"^\s*U[0-9]{2,3}\s*[-·:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Text(cleaned)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private func zoneColor(number: Int) -> Color {
        switch number {
        case 1: return Color.teal
        case 2: return Color.indigo
        case 3: return Color.orange
        default: return tint
        }
    }
    
    private func parseBlocks(from fullText: String) -> [FormattedTextBlock] {
        var blocks: [FormattedTextBlock] = []
        let rawLines = fullText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        for line in rawLines {
            let zoneRegex = try? NSRegularExpression(pattern: #"^(?:-\s*)?Zona\s+([1-9])(?:\s*\(([^)]+)\))?\s*:\s*(.*)$"#, options: [.caseInsensitive])
            if let match = zoneRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {
                let numStr = (Range(match.range(at: 1), in: line) != nil) ? String(line[Range(match.range(at: 1), in: line)!]) : "1"
                let num = Int(numStr) ?? 1
                var subtitle: String?
                var parsedTitle = ""
                if match.range(at: 2).location != NSNotFound, let subRange = Range(match.range(at: 2), in: line) {
                    let rawSub = String(line[subRange])
                    let parts = rawSub.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count >= 2 {
                        subtitle = parts[0]
                        parsedTitle = parts.dropFirst().joined(separator: " · ")
                    } else {
                        subtitle = rawSub
                    }
                }
                let desc = (match.range(at: 3).location != NSNotFound && Range(match.range(at: 3), in: line) != nil)
                    ? String(line[Range(match.range(at: 3), in: line)!]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                
                blocks.append(.zone(number: num, subtitle: subtitle, title: parsedTitle, description: desc))
                continue
            }
            
            let roundRegex = try? NSRegularExpression(pattern: #"^Ronda\s+([1-9])(?:\s*\(([0-9]+)\s*min\))?\s*:\s*(.*)$"#, options: [.caseInsensitive])
            if let match = roundRegex?.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {
                let numStr = (Range(match.range(at: 1), in: line) != nil) ? String(line[Range(match.range(at: 1), in: line)!]) : "1"
                let rNum = Int(numStr) ?? 1
                var minutes: Int?
                if match.range(at: 2).location != NSNotFound, let mRange = Range(match.range(at: 2), in: line) {
                    minutes = Int(line[mRange])
                }
                let rest = (match.range(at: 3).location != NSNotFound && Range(match.range(at: 3), in: line) != nil)
                    ? String(line[Range(match.range(at: 3), in: line)!]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                blocks.append(.rotationRound(number: rNum, duration: minutes, rawText: rest))
                continue
            }
            
            if line.lowercased().hasPrefix("fase ") || line.lowercased().hasPrefix("fases ") {
                blocks.append(.phaseHeader(title: line))
                continue
            }
            
            if line.lowercased().contains("consigna clil") || line.lowercased().contains("clil:") {
                let consigna = line.replacingOccurrences(of: #"^.*?(?:Consigna\s+CLIL|CLIL)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(.clilConsigna(consigna: consigna))
                continue
            }
            
            if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("· ") {
                let item = line.replacingOccurrences(of: #"^[-•·]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(.bulletItem(item: item))
                continue
            }
            
            if let colonIdx = line.firstIndex(of: ":") {
                let keyCandidate = String(line[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valCandidate = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if keyCandidate.count >= 3 && keyCandidate.count <= 35 && !valCandidate.isEmpty && !keyCandidate.contains("http") {
                    blocks.append(.keyValue(key: keyCandidate, value: valCandidate))
                    continue
                }
            }
            
            blocks.append(.paragraph(text: line))
        }
        
        return blocks
    }
}

enum FormattedTextBlock {
    case zone(number: Int, subtitle: String?, title: String, description: String)
    case phaseHeader(title: String)
    case rotationRound(number: Int, duration: Int?, rawText: String)
    case clilConsigna(consigna: String)
    case bulletItem(item: String)
    case keyValue(key: String, value: String)
    case paragraph(text: String)
}

