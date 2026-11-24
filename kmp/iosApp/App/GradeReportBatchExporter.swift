import Foundation
import MiGestorKit

/// Guarda de golpe los informes de notas del grupo: un PDF por alumno dentro de
/// una carpeta nueva. Nunca sobrescribe ni borra nada: si el nombre existe, numera.
enum GradeReportBatchExporter {
    struct Item {
        let report: StudentGradeReport
        let narrative: GradeReportNarrative
    }

    struct Result: Equatable {
        let folder: URL
        let savedFiles: [URL]
        /// Alumnos cuyo PDF no se pudo crear o escribir.
        let failedNames: [String]
    }

    /// «Notas 1ª Evaluación · 2º ESO B». Sin barras ni dos puntos, que el sistema no admite.
    static func folderName(periodName: String, className: String) -> String {
        let parts = [periodName, className]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let base = parts.isEmpty ? "Notas" : "Notas " + parts.joined(separator: " · ")
        return base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// Primera ruta libre: «Nombre», «Nombre 2», «Nombre 3»…
    static func uniqueURL(in parent: URL, name: String, pathExtension: String? = nil, fileManager: FileManager = .default) -> URL {
        func candidate(_ index: Int) -> URL {
            let stem = index == 1 ? name : "\(name) \(index)"
            let url = parent.appendingPathComponent(stem, isDirectory: pathExtension == nil)
            return pathExtension.map { url.appendingPathExtension($0) } ?? url
        }
        var index = 1
        while fileManager.fileExists(atPath: candidate(index).path) {
            index += 1
        }
        return candidate(index)
    }

    /// Crea la carpeta dentro de `parent` y escribe un PDF por alumno.
    /// Si un alumno falla, sigue con los demás y lo anota en `failedNames`.
    static func export(
        items: [Item],
        context: StudentGradeReportPDFRenderer.Context,
        into parent: URL,
        fileManager: FileManager = .default
    ) throws -> Result {
        let folder = uniqueURL(
            in: parent,
            name: folderName(periodName: context.periodName, className: context.className),
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)

        var saved: [URL] = []
        var failed: [String] = []
        for item in items {
            let fileName = StudentGradeReportPDFRenderer.fileName(for: item.report, periodName: context.periodName)
            let stem = (fileName as NSString).deletingPathExtension
            let url = uniqueURL(in: folder, name: stem, pathExtension: "pdf", fileManager: fileManager)
            guard let data = StudentGradeReportPDFRenderer.pdfData(report: item.report, narrative: item.narrative, context: context) else {
                failed.append(item.report.studentName)
                continue
            }
            do {
                try data.write(to: url, options: .withoutOverwriting)
                saved.append(url)
            } catch {
                failed.append(item.report.studentName)
            }
        }
        return Result(folder: folder, savedFiles: saved, failedNames: failed)
    }
}
