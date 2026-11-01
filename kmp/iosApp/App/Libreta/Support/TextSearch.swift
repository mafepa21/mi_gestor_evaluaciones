import SwiftUI
import Vision

/// Reconocimiento de texto manuscrito con Vision.
enum TextRecognizer {
    static func recognize(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["es-ES", "en-US"]
            do {
                try VNImageRequestHandler(cgImage: cg).perform([request])
            } catch { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: " ")
        }.value
    }
}

/// Indexa las hojas en segundo plano: tras editar, espera un momento y reconoce el texto.
@MainActor
final class PageIndexer {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func schedule(_ page: Page, after delay: Duration = .seconds(2)) {
        tasks[page.id]?.cancel()
        tasks[page.id] = Task { [weak page] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let page else { return }
            await index(page)
        }
    }

    /// Indexa las hojas cuyo dibujo cambió desde la última vez (p. ej. al abrir el cuaderno).
    func indexPending(in notebook: Notebook) {
        for page in notebook.pageList where page.indexedDrawingSize != page.drawingData.count {
            schedule(page, after: .milliseconds(300))
        }
    }

    private func index(_ page: Page) async {
        var recognized = ""
        if let image = PageRenderer.inkOnWhite(of: page) {
            recognized = await TextRecognizer.recognize(image)
        }
        let typed = page.elementList.filter { $0.kind == .text }.map(\.text).joined(separator: " ")
        page.searchText = [recognized, typed].filter { !$0.isEmpty }.joined(separator: " ")
        page.indexedDrawingSize = page.drawingData.count
    }
}

enum SearchMatch {
    static func matches(_ page: Page, query: String) -> Bool {
        page.searchText.localizedStandardContains(query)
    }

    static func snippet(_ page: Page, query: String) -> String {
        let text = page.searchText
        guard let r = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(80))
        }
        let start = text.index(r.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + String(text[start..<end]) + "…"
    }
}
