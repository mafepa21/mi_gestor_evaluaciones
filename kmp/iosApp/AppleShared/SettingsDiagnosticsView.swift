import SwiftUI
import SQLite3
import MiGestorKit

#if os(macOS)
import AppKit
#endif

struct SettingsDiagnosticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var dbLogs: String = ""
    @State private var diskUsage: String = ""
    @State private var loading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Herramientas de Diagnóstico")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 4)

                // Banco de pruebas de las entregas web. Solo DEBUG, y solo hasta
                // que exista la publicación de formularios: entonces se borra.
                #if DEBUG
                WebSubmissionTestBenchView()
                    .padding(.horizontal, 4)
                Divider()
                #endif

                #if os(macOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Acciones de Soporte")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Button("Copiar diagnóstico") {
                            copyDiagnostic(anonymized: false)
                        }
                        Button("Copiar anonimizado") {
                            copyDiagnostic(anonymized: true)
                        }
                        Button("Abrir logs") {
                            openLogsFolder()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(12)
                #endif
                
                if loading {
                    HStack {
                        Spacer()
                        ProgressView("Cargando diagnóstico...")
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    diagnosticsCard(title: "Uso de Disco", detail: diskUsage)
                    diagnosticsCard(title: "Logs de Base de Datos", detail: dbLogs)
                }
            }
            .padding(16)
        }
        .navigationTitle("Diagnóstico avanzado")
        .task {
            await runDiagnostics()
        }
    }
    
    private func diagnosticsCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            
            Text(detail)
                .font(.system(.footnote, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
        .padding()
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }
    
    private func runDiagnostics() async {
        loading = true
        defer { loading = false }
        
        let fileManager = FileManager.default
        let dbPath = AppleBridgeBootstrap.current().databasePath
        let dbURL = URL(fileURLWithPath: dbPath)
        let appDataURL = dbURL.deletingLastPathComponent()
        
        // Compute Disk Usage
        var usageStr = ""
        if let dbSize = try? fileManager.attributesOfItem(atPath: dbPath)[.size] as? Int64 {
            usageStr += "Base de Datos: \(ByteCountFormatter.string(fromByteCount: dbSize, countStyle: .file))\n"
        }
        
        let backupsDir = appDataURL.appendingPathComponent("backups", isDirectory: true)
        if let urls = try? fileManager.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil, options: []) {
            let backupsCount = urls.filter { $0.pathExtension == "migestorbackup" }.count
            usageStr += "Copias de seguridad guardadas: \(backupsCount)\n"
            
            var totalBackupsSize: Int64 = 0
            for url in urls {
                if let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                    totalBackupsSize += size
                }
            }
            usageStr += "Espacio total backups: \(ByteCountFormatter.string(fromByteCount: totalBackupsSize, countStyle: .file))\n"
        }
        
        let attachmentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("NotebookEvidence", isDirectory: true) ?? appDataURL.appendingPathComponent("NotebookEvidence")
        if let atts = try? fileManager.contentsOfDirectory(at: attachmentsDir, includingPropertiesForKeys: nil, options: []) {
            usageStr += "Evidencias/Adjuntos: \(atts.count) archivos\n"
        }
        
        diskUsage = usageStr.isEmpty ? "No se pudo calcular el uso de disco." : usageStr
        
        // Extract DB Logs / Details
        var logs = ""
        logs += "Ruta DB: \(dbPath)\n"
        
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            defer { sqlite3_close(db) }
            
            // Schema user_version
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    let version = sqlite3_column_int(statement, 0)
                    logs += "Esquema DB Versión: \(version)\n"
                }
                sqlite3_finalize(statement)
            }
            
            // Integrity check
            var integrityStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA integrity_check(1);", -1, &integrityStmt, nil) == SQLITE_OK {
                if sqlite3_step(integrityStmt) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(integrityStmt, 0) {
                        let status = String(cString: cString)
                        logs += "Estado de integridad: \(status)\n"
                    }
                }
                sqlite3_finalize(integrityStmt)
            }
            
            // Table List and row counts
            let tables = ["classes", "students", "notebook_columns", "rubrics", "attendance", "calendar_events", "incidents", "key_value_store"]
            logs += "\nRecuento de Filas por Tabla:\n"
            for table in tables {
                var countStmt: OpaquePointer?
                let q = "SELECT COUNT(*) FROM \(table);"
                if sqlite3_prepare_v2(db, q, -1, &countStmt, nil) == SQLITE_OK {
                    if sqlite3_step(countStmt) == SQLITE_ROW {
                        let count = sqlite3_column_int(countStmt, 0)
                        logs += " - \(table): \(count)\n"
                    }
                    sqlite3_finalize(countStmt)
                }
            }
        } else {
            logs += "No se pudo abrir la conexión SQLite para obtener diagnóstico adicional."
        }
        
        dbLogs = logs
    }
    
    #if os(macOS)
    private func copyDiagnostic(anonymized: Bool) {
        let dbPath = AppleBridgeBootstrap.current().databasePath
        let platform = AppleBridgeBootstrap.current().platformName
        
        let lines = [
            "MiGestor macOS Diagnostic Log",
            "Plataforma: \(platform)",
            "SQLDelight Path: \(anonymized ? "anonymized" : dbPath)",
            "Disk Space: \(diskUsage)"
        ]
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }
    
    private func openLogsFolder() {
        let dbPath = AppleBridgeBootstrap.current().databasePath
        let dbURL = URL(fileURLWithPath: dbPath)
        let logsURL = dbURL.deletingLastPathComponent().appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logsURL])
    }
    #endif
}
