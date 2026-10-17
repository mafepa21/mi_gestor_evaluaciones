import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Agrupación por día

/// Copias de un mismo día, en el orden en que llegan (más recientes primero).
struct BackupDayGroup: Identifiable {
    let day: Date
    let backups: [AppleBackupDescriptor]

    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
        return formatter.string(from: day).capitalizedFirstLetter
    }

    static func groups(from backups: [AppleBackupDescriptor]) -> [BackupDayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [AppleBackupDescriptor]] = [:]
        for backup in backups {
            let day = calendar.startOfDay(for: backup.manifest.createdAt)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(backup)
        }
        return order.map { BackupDayGroup(day: $0, backups: byDay[$0] ?? []) }
    }
}

extension AppleBackupDescriptor {
    /// Copia que la app crea sola justo antes de restaurar otra
    /// (ver `AppleBackupService.restoreBackup`).
    var isPreRestoreBackup: Bool {
        manifest.note?.hasPrefix("Copia de seguridad de emergencia") == true
    }

    /// Coincide con la búsqueda por nota, dispositivo, plataforma o fecha.
    func matches(search text: String) -> Bool {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return (manifest.note?.localizedCaseInsensitiveContains(query) ?? false)
            || manifest.deviceName.localizedCaseInsensitiveContains(query)
            || manifest.platform.localizedCaseInsensitiveContains(query)
            || manifest.createdAt.formattedDateText.localizedCaseInsensitiveContains(query)
    }

    /// Hora más, si la hay, la nota escrita por el docente. Las copias de emergencia
    /// llevan una nota generada que se sustituye por la etiqueta "Antes de restaurar".
    var rowTitle: String {
        let time = manifest.createdAt.formatted(date: .omitted, time: .shortened)
        guard !isPreRestoreBackup,
              let note = manifest.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return time }
        return "\(time) · \(note)"
    }

    var contentSummaryText: String {
        let summary = manifest.summary
        var parts = [
            "\(summary.classCount) clases",
            "\(summary.studentCount) alumnos",
            "\(summary.notebookColumnCount) columnas",
            "\(summary.rubricCount) rúbricas"
        ]
        if let libretas = summary.libretaCount, libretas > 0 {
            parts.append("\(libretas) libretas")
        }
        return parts.joined(separator: " · ")
    }

    /// Problema que impide restaurar, si lo hay.
    var problemText: String? {
        if hasEmptyDatabase {
            // El checksum de un fichero vacío es válido, así que estas copias
            // se mostraban como "Válida". Restaurarlas borra los datos actuales
            // y no repone nada.
            return "Vacía: restaurarla borraría tus datos sin reponer nada."
        }
        if isVerified, verificationError != nil {
            return "Dañada: no se puede restaurar."
        }
        return nil
    }

    var isValidated: Bool { isVerified && verificationError == nil && !hasEmptyDatabase }

    var accessibilityStatusText: String {
        if let problemText { return problemText }
        return isValidated ? "Validada" : "Sin validar"
    }

    var longDateText: String { manifest.createdAt.formattedDateText }
}

// MARK: - BackupRowView

struct BackupRowView: View {
    let backup: AppleBackupDescriptor
    var onOpen: () -> Void
    var onVerify: () -> Void
    var onExport: () -> Void
    var onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var statusWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    statusSymbol
                        .frame(width: statusWidth)

                    VStack(alignment: .leading, spacing: 2) {
                        titleLine
                        if let problem = backup.problemText {
                            Text(problem)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        } else {
                            Text(backup.contentSummaryText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if dynamicTypeSize.isAccessibilitySize {
                            Text(backup.sizeText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(backup.sizeText)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        if backup.isEmergencyBackup {
                            Label("Copia de emergencia · antes de restaurar", systemImage: "lifepreserver")
                                .font(IOSAppStyle.captionText.weight(.semibold))
                                .foregroundStyle(IOSAppStyle.warning)
                                .padding(.top, 2)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(backup.hasEmptyDatabase)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(backup.hasEmptyDatabase ? "" : "Muestra el contenido de la copia y permite restaurarla")

            actionsMenu
        }
        .padding(.vertical, 4)
        .contextMenu { menuItems }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Eliminar", systemImage: "trash")
            }
            Button(action: onExport) {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading) {
            Button(action: onVerify) {
                Label("Validar", systemImage: "checkmark.shield")
            }
            .tint(.green)
        }
        #endif
        .accessibilityAction(named: "Validar", onVerify)
        .accessibilityAction(named: "Exportar", onExport)
        .accessibilityAction(named: "Eliminar", onDelete)
    }

    private var titleLine: some View {
        HStack(spacing: 8) {
            Text(backup.rowTitle)
                .font(.body)
                .lineLimit(2)
            if backup.isPreRestoreBackup {
                Text("Antes de restaurar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    /// Solo hay símbolo cuando aporta algo: validada o con un problema. "Sin validar" es
    /// el estado normal de una copia recién hecha y no debe parecer un aviso.
    @ViewBuilder
    private var statusSymbol: some View {
        if backup.hasEmptyDatabase {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if backup.isVerified, backup.verificationError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if backup.isVerified {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Color.clear
        }
    }

    private var actionsMenu: some View {
        Menu {
            menuItems
        } label: {
            Label("Acciones", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                #else
                .frame(minWidth: 28, minHeight: 28)
                #endif
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Acciones de la copia")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onOpen) {
            Label("Ver contenido y restaurar…", systemImage: "clock.arrow.circlepath")
        }
        .disabled(backup.hasEmptyDatabase)
        Button(action: onVerify) {
            Label("Validar", systemImage: "checkmark.shield")
        }
        Button(action: onExport) {
            Label("Exportar…", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Eliminar…", systemImage: "trash")
        }
    }

    private var accessibilityLabel: String {
        var parts = [backup.longDateText]
        if let note = backup.manifest.note, !note.isEmpty, !backup.isPreRestoreBackup { parts.append(note) }
        if backup.isPreRestoreBackup { parts.append("copia antes de restaurar") }
        parts.append(backup.accessibilityStatusText)
        parts.append(backup.contentSummaryText)
        parts.append(backup.sizeText)
        return parts.joined(separator: ", ")
    }
}

/// Fila de relleno mientras se escanea la carpeta de copias.
struct BackupPlaceholderRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("00:00 · Copia de seguridad")
            Text("0 clases · 0 alumnos · 0 columnas · 0 rúbricas")
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - iOS ShareSheet Representable
#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Local Date Formatter Helper
extension Date {
    fileprivate var formattedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: self)
    }
}

extension String {
    fileprivate var capitalizedFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
