import SwiftUI

enum AppleAppCommandDestination: String {
    case notebook
    case attendance
    case planner
}

enum AppleAppCommand {
    static func post(_ name: Notification.Name, object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }
}

struct AppleAppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Añadir columna") {
                AppleAppCommand.post(.appleAppAddNotebookColumnRequested)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Guardar / sincronizar") {
                AppleAppCommand.post(.appleAppSaveOrSyncRequested)
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandMenu("Cuaderno") {
            Button("Buscar") {
                AppleAppCommand.post(.appleAppSearchRequested)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Añadir columna") {
                AppleAppCommand.post(.appleAppAddNotebookColumnRequested)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Mostrar columnas ocultas") {
                AppleAppCommand.post(.appleAppShowHiddenNotebookColumnsRequested)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Reordenar columnas") {
                AppleAppCommand.post(.appleAppReorderNotebookColumnsRequested)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Exportar informe") {
                AppleAppCommand.post(.appleAppExportReportRequested)
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandMenu("Navegación") {
            Button("Ir al Cuaderno") {
                AppleAppCommand.post(.appleAppNavigateRequested, object: AppleAppCommandDestination.notebook.rawValue)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Ir a Asistencia") {
                AppleAppCommand.post(.appleAppNavigateRequested, object: AppleAppCommandDestination.attendance.rawValue)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Ir a Planner") {
                AppleAppCommand.post(.appleAppNavigateRequested, object: AppleAppCommandDestination.planner.rawValue)
            }
            .keyboardShortcut("3", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let appleAppAddNotebookColumnRequested = Notification.Name("appleAppAddNotebookColumnRequested")
    static let appleAppSearchRequested = Notification.Name("appleAppSearchRequested")
    static let appleAppSaveOrSyncRequested = Notification.Name("appleAppSaveOrSyncRequested")
    static let appleAppShowHiddenNotebookColumnsRequested = Notification.Name("appleAppShowHiddenNotebookColumnsRequested")
    static let appleAppReorderNotebookColumnsRequested = Notification.Name("appleAppReorderNotebookColumnsRequested")
    static let appleAppExportReportRequested = Notification.Name("appleAppExportReportRequested")
    static let appleAppNavigateRequested = Notification.Name("appleAppNavigateRequested")
    static let appleAppRefreshRequested = Notification.Name("appleAppRefreshRequested")
    static let appleAppBackupRequested = Notification.Name("appleAppBackupRequested")
    static let appleAppToggleInspectorRequested = Notification.Name("appleAppToggleInspectorRequested")
    static let appleAppToggleSidebarRequested = Notification.Name("appleAppToggleSidebarRequested")
}
