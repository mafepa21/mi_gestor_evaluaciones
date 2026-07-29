import SwiftUI

/// Rejilla semanal del horario: franjas horarias en vertical, días lectivos en
/// horizontal. Sustituye la lectura de una lista lineal ordenada por (día,
/// hora), que obliga a reconstruir la semana mentalmente.
///
/// No depende de los modelos KMP: cada pantalla mapea sus datos a `Entry`. Así
/// la misma vista sirve para el panel de macOS, para la lectura de iPad y para
/// el PDF, sin arrastrar el puente a la capa de dibujo.
struct ScheduleWeekGridView: View {
    struct Entry: Identifiable, Hashable {
        let id: Int64
        /// 1 = lunes … 7 = domingo (convención de `TeacherScheduleSlot.dayOfWeek`).
        let dayOfWeek: Int
        let startTime: String
        let endTime: String
        let subject: String
        let groupName: String
        let unit: String?
    }

    let entries: [Entry]
    /// Días que se pintan como columnas. Respeta los días lectivos configurados:
    /// un centro con jornada de lunes a jueves no debe ver una columna de viernes.
    let activeWeekdays: [Int]
    let dayLabel: (Int) -> String
    var compact: Bool = false
    /// Sólo el asistente de horario lo pasa: hace que los huecos libres sean
    /// pulsables para precargar día y hora en el editor de franjas. En lectura
    /// (iPad, PDF) se deja a `nil` y la rejilla sigue siendo sólo para mirar.
    var onSelectEmptySlot: ((_ day: Int, _ startTime: String, _ endTime: String) -> Void)? = nil

    private var timeSlots: [String] {
        var seen = Set<String>()
        return entries
            .sorted { ($0.startTime, $0.endTime) < ($1.startTime, $1.endTime) }
            .map { "\($0.startTime)-\($0.endTime)" }
            .filter { seen.insert($0).inserted }
    }

    private var days: [Int] {
        activeWeekdays.sorted()
    }

    private func entries(day: Int, timeSlot: String) -> [Entry] {
        entries.filter { "\($0.startTime)-\($0.endTime)" == timeSlot && $0.dayOfWeek == day }
    }

    private var timeColumnWidth: CGFloat { compact ? 64 : 78 }
    private var rowHeight: CGFloat { compact ? 52 : 64 }

    var body: some View {
        if entries.isEmpty || days.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Hora")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: timeColumnWidth, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        Text(dayLabel(day))
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(timeSlots, id: \.self) { timeSlot in
                    // Alineación superior: una celda con solapes es más alta que
                    // sus vecinas, y con el centrado por defecto arrastraba a
                    // toda la fila hacia arriba, desalineando la franja.
                    HStack(alignment: .top, spacing: 6) {
                        Text(timeSlot.replacingOccurrences(of: "-", with: "\n"))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: timeColumnWidth, alignment: .leading)

                        ForEach(days, id: \.self) { day in
                            cell(entries(day: day, timeSlot: timeSlot), day: day, timeSlot: timeSlot)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ cellEntries: [Entry], day: Int, timeSlot: String) -> some View {
        // Hueco libre: espacio sobrio y sin llamada a la acción. El alta de
        // franjas vive en el editor, y un "+" por celda vacía sería ruido en la
        // vista que existe para leer la semana de un vistazo. La excepción es
        // el asistente, que sí pasa `onSelectEmptySlot`: ahí la rejilla es la
        // herramienta de edición y repetir una hora en otro día debe costar un
        // toque, no teclear cuatro campos.
        if cellEntries.isEmpty {
            if let onSelectEmptySlot {
                Button {
                    let parts = timeSlot.split(separator: "-", maxSplits: 1).map(String.init)
                    onSelectEmptySlot(day, parts.first ?? "", parts.count > 1 ? parts[1] : "")
                } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir franja el \(dayLabel(day)) a las \(timeSlot)")
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
                    .frame(maxWidth: .infinity, minHeight: rowHeight)
            }
        } else {
            VStack(spacing: 4) {
                // Los solapes se apilan: si dos grupos comparten franja, el
                // docente tiene que verlo, no que se le oculte uno.
                ForEach(cellEntries) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        // La materia es el dato dominante de la celda: se le dan
                        // dos líneas y algo de reducción antes de recortar.
                        // "Lengua Castellana y Literatura" no cabe en una.
                        Text(entry.subject.isEmpty ? "Sin materia" : entry.subject)
                            .font(.caption.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                        Text(entry.groupName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let unit = entry.unit, !unit.isEmpty {
                            Text(unit)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight)
        }
    }
}

/// Página completa del horario, tal y como se exporta a PDF: cabecera con el
/// contexto (agenda, grupo y fecha de generación) más la rejilla. Es la misma
/// vista que se ve en pantalla, así que no hay dos maquetaciones que mantener
/// sincronizadas.
struct ScheduleWeekGridPage: View {
    let title: String
    let subtitle: String
    let entries: [ScheduleWeekGridView.Entry]
    let activeWeekdays: [Int]
    let dayLabel: (Int) -> String

    private var generationDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Generado el \(generationDateText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScheduleWeekGridView(
                entries: entries,
                activeWeekdays: activeWeekdays,
                dayLabel: dayLabel
            )
        }
        .padding(24)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
