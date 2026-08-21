import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import ZIPFoundation

struct PlannerDocxRenderResult {
    let html: String
    let tableCount: Int
    let imageCount: Int

    var featureSummary: String {
        var items: [String] = []
        if tableCount > 0 { items.append("\(tableCount) tabla\(tableCount == 1 ? "" : "s")") }
        if imageCount > 0 { items.append("\(imageCount) imagen\(imageCount == 1 ? "" : "es")") }
        return items.joined(separator: " · ")
    }
}

enum PlannerDocxRenderError: LocalizedError {
    case missingDocumentXML
    case invalidDocument
    case missingSession

    var errorDescription: String? {
        switch self {
        case .missingDocumentXML:
            return "El documento DOCX no contiene un cuerpo Word reconocible."
        case .invalidDocument:
            return "No se ha podido interpretar el documento DOCX."
        case .missingSession:
            return "No se ha podido localizar esta sesión dentro del DOCX."
        }
    }
}

struct PlannerSessionDocxRenderer {
    func render(from url: URL, sourceLabel: String, sessionNumber: Int) throws -> PlannerDocxRenderResult {
        let data = try Data(contentsOf: url)
        let archive = try Archive(data: data, accessMode: .read, pathEncoding: nil)
        guard let documentData = try archiveData(archive, path: "word/document.xml") else {
            throw PlannerDocxRenderError.missingDocumentXML
        }

        let documentRoot = try PlannerDocxXMLParser.parse(documentData)
        guard let body = documentRoot.descendant(named: "body") else {
            throw PlannerDocxRenderError.invalidDocument
        }

        let blocks = body.children.filter { node in
            node.localName == "p" || node.localName == "tbl"
        }
        let selectedBlocks = selectSessionBlocks(
            from: blocks,
            sourceLabel: sourceLabel,
            sessionNumber: sessionNumber
        )
        guard !selectedBlocks.isEmpty else {
            throw PlannerDocxRenderError.missingSession
        }

        let relationships = try documentRelationships(from: archive)
        let context = PlannerDocxRenderContext(archive: archive, relationships: relationships)
        let bodyHTML = selectedBlocks.map { context.renderBlock($0) }.joined(separator: "\n")
        let html = Self.htmlDocument(bodyHTML)
        return PlannerDocxRenderResult(
            html: html,
            tableCount: context.tableCount,
            imageCount: context.imageCount
        )
    }

    private func selectSessionBlocks(
        from blocks: [PlannerDocxXMLNode],
        sourceLabel: String,
        sessionNumber: Int
    ) -> [PlannerDocxXMLNode] {
        let wanted = normalize(sourceLabel)
        let startIndex = blocks.firstIndex { block in
            guard block.localName == "p" else { return false }
            let text = normalize(block.textContent)
            if !wanted.isEmpty, text == wanted || text.hasPrefix(wanted) || wanted.hasPrefix(text) {
                return true
            }
            return sessionNumber > 0 && isSessionHeader(text, number: sessionNumber)
        }

        guard let startIndex else {
            // A hand-authored session can omit the canonical header. Rendering the
            // complete document keeps the original material available through the
            // in-app viewer; QuickLook remains available for the exact source file.
            return blocks
        }

        let endIndex = blocks[(startIndex + 1)...].firstIndex { block in
            guard block.localName == "p" else { return false }
            return isAnySessionHeader(normalize(block.textContent))
        } ?? blocks.count
        return Array(blocks[startIndex..<endIndex])
    }

    private func isSessionHeader(_ text: String, number: Int) -> Bool {
        let pattern = #"^(?:sesion|sesiones|session|sessions)\s+#?"# + String(number) + #"\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func isAnySessionHeader(_ text: String) -> Bool {
        text.range(of: #"^(?:sesion|sesiones|session|sessions)\s+[0-9]+"#, options: .regularExpression) != nil
            || text.range(of: #"^(?:semana|setmana|week)\s+[0-9]+"#, options: .regularExpression) != nil
    }

    private func documentRelationships(from archive: Archive) throws -> [String: String] {
        guard let data = try archiveData(archive, path: "word/_rels/document.xml.rels") else { return [:] }
        let root = try PlannerDocxXMLParser.parse(data)
        var result: [String: String] = [:]
        for relationship in root.descendants(named: "Relationship") {
            guard let id = relationship.attribute(localName: "Id"),
                  let target = relationship.attribute(localName: "Target") else { continue }
            result[id] = target
        }
        return result
    }

    private func archiveData(_ archive: Archive, path: String) throws -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlDocument(_ body: String) -> String {
        """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 8px 4px 24px; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: 15px; line-height: 1.48; color: #202124; background: transparent; }
        h1, h2, h3, h4 { margin: 20px 0 8px; line-height: 1.18; color: #111; }
        h1 { font-size: 25px; } h2 { font-size: 21px; } h3 { font-size: 18px; } h4 { font-size: 16px; }
        p { margin: 8px 0; }
        .list-item { margin: 5px 0 5px 18px; padding-left: 4px; }
        .list-item::before { content: "•"; margin-left: -16px; margin-right: 8px; color: #16877d; }
        .docx-table-wrap { width: 100%; overflow-x: auto; margin: 16px 0; }
        table { border-collapse: collapse; min-width: 100%; font-size: 14px; }
        th, td { border: 1px solid rgba(128,128,128,.35); padding: 8px 10px; vertical-align: top; text-align: left; }
        th { font-weight: 700; background: rgba(22,135,125,.12); }
        td p { margin: 0 0 5px; } td p:last-child { margin-bottom: 0; }
        img { display: block; max-width: 100%; height: auto; margin: 14px auto; border-radius: 6px; }
        .docx-image-caption { text-align: center; color: #6b6b6b; font-size: 12px; margin-top: -8px; }
        @media (prefers-color-scheme: dark) {
          body { color: #f2f2f7; } h1, h2, h3, h4 { color: #fff; }
          th { background: rgba(88,205,190,.18); } th, td { border-color: rgba(255,255,255,.28); }
        }
        </style></head><body>\(body)</body></html>
        """
    }
}

private final class PlannerDocxRenderContext {
    let archive: Archive
    let relationships: [String: String]
    var tableCount = 0
    var imageCount = 0

    init(archive: Archive, relationships: [String: String]) {
        self.archive = archive
        self.relationships = relationships
    }

    func renderBlock(_ node: PlannerDocxXMLNode) -> String {
        switch node.localName {
        case "p": return renderParagraph(node)
        case "tbl": return renderTable(node)
        default: return ""
        }
    }

    private func renderParagraph(_ node: PlannerDocxXMLNode) -> String {
        let style = node.child(named: "pPr")?.child(named: "pStyle")?.attribute(localName: "val") ?? ""
        let normalizedStyle = style.lowercased()
        let isList = node.child(named: "pPr")?.child(named: "numPr") != nil
            || normalizedStyle.contains("list")
        let tag: String
        if normalizedStyle.contains("heading1") || normalizedStyle == "title" {
            tag = "h1"
        } else if normalizedStyle.contains("heading2") {
            tag = "h2"
        } else if normalizedStyle.contains("heading3") || normalizedStyle.contains("subtitle") {
            tag = "h3"
        } else {
            tag = isList ? "div" : "p"
        }

        let content = node.descendants(named: "r").map(renderRun).joined()
        guard !content.isEmpty else { return "" }
        return isList ? "<div class=\"list-item\">\(content)</div>" : "<\(tag)>\(content)</\(tag)>"
    }

    private func renderRun(_ node: PlannerDocxXMLNode) -> String {
        var content = ""
        for child in node.children {
            switch child.localName {
            case "t": content += escapeHTML(child.textContent)
            case "tab": content += "&emsp;"
            case "br", "cr": content += "<br>"
            case "drawing", "pict": content += renderImage(in: child)
            default: break
            }
        }
        guard !content.isEmpty else { return "" }

        let properties = node.child(named: "rPr")
        if properties?.child(named: "b") != nil { content = "<strong>\(content)</strong>" }
        if properties?.child(named: "i") != nil { content = "<em>\(content)</em>" }
        if properties?.child(named: "u") != nil { content = "<u>\(content)</u>" }
        return content
    }

    private func renderTable(_ node: PlannerDocxXMLNode) -> String {
        let rows = node.children.filter { $0.localName == "tr" }
        guard !rows.isEmpty else { return "" }
        tableCount += 1
        let rowsHTML = rows.enumerated().map { index, row in
            let cells = row.children.filter { $0.localName == "tc" }.map { cell -> String in
                let content = cell.children.compactMap { child -> String? in
                    guard child.localName == "p" || child.localName == "tbl" else { return nil }
                    return renderBlock(child)
                }.joined()
                let colSpan = cell.child(named: "tcPr")?.child(named: "gridSpan")?.attribute(localName: "val")
                let span = Int(colSpan ?? "1") ?? 1
                let attribute = span > 1 ? " colspan=\"\(span)\"" : ""
                return "<\(index == 0 ? "th" : "td")\(attribute)>\(content)</\(index == 0 ? "th" : "td")>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()
        return "<div class=\"docx-table-wrap\"><table>\(rowsHTML)</table></div>"
    }

    private func renderImage(in node: PlannerDocxXMLNode) -> String {
        guard let blip = node.descendant(named: "blip"),
              let relationshipId = blip.attribute(localName: "embed") ?? blip.attribute(localName: "link"),
              let target = relationships[relationshipId],
              let data = imageData(for: target) else { return "" }
        imageCount += 1
        let mimeType = mimeType(for: target)
        return "<img src=\"data:\(mimeType);base64,\(data.base64EncodedString())\" alt=\"Imagen del documento\">"
    }

    private func imageData(for target: String) -> Data? {
        let normalizedTarget = target.replacingOccurrences(of: "\\", with: "/")
        let path: String
        if normalizedTarget.hasPrefix("/") {
            path = String(normalizedTarget.dropFirst())
        } else {
            path = "word/\(normalizedTarget)"
        }
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }
        return data.isEmpty ? nil : data
    }

    private func mimeType(for target: String) -> String {
        let ext = URL(fileURLWithPath: target).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        default: return "image/png"
        }
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class PlannerDocxXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [PlannerDocxXMLNode] = []
    var ownText = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var localName: String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    var textContent: String {
        var result = ownText
        for child in children {
            if child.localName == "tab" { result += "\t" }
            else if child.localName == "br" || child.localName == "cr" { result += "\n" }
            else { result += child.textContent }
        }
        return result
    }

    func attribute(localName: String) -> String? {
        attributes.first { key, _ in
            key == localName || key.split(separator: ":").last.map(String.init) == localName
        }?.value
    }

    func child(named localName: String) -> PlannerDocxXMLNode? {
        children.first { $0.localName == localName }
    }

    func descendant(named localName: String) -> PlannerDocxXMLNode? {
        if let child = children.first(where: { $0.localName == localName }) { return child }
        for child in children {
            if let descendant = child.descendant(named: localName) { return descendant }
        }
        return nil
    }

    func descendants(named localName: String) -> [PlannerDocxXMLNode] {
        var result: [PlannerDocxXMLNode] = []
        for child in children {
            if child.localName == localName { result.append(child) }
            result.append(contentsOf: child.descendants(named: localName))
        }
        return result
    }
}

private final class PlannerDocxXMLParser: NSObject, XMLParserDelegate {
    private var stack: [PlannerDocxXMLNode] = []
    private(set) var root: PlannerDocxXMLNode?

    static func parse(_ data: Data) throws -> PlannerDocxXMLNode {
        let parser = PlannerDocxXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse(), let root = parser.root else {
            throw PlannerDocxRenderError.invalidDocument
        }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = PlannerDocxXMLNode(name: elementName, attributes: attributeDict)
        stack.last?.children.append(node)
        stack.append(node)
        if root == nil { root = node }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.ownText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        _ = stack.popLast()
    }
}

struct PlannerDocxWebView: View {
    let html: String

    var body: some View {
        PlannerDocxWebViewRepresentable(html: html)
            .frame(minHeight: 420, idealHeight: 560, maxHeight: 720)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("Contenido enriquecido del documento de sesión")
    }
}

#if os(iOS)
private struct PlannerDocxWebViewRepresentable: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct PlannerDocxWebViewRepresentable: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#endif
