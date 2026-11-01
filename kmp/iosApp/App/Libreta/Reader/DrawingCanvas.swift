import SwiftUI
import PencilKit

/// Una única paleta de herramientas compartida por todos los lienzos visibles.
@MainActor
final class ToolPickerHolder {
    let picker = PKToolPicker()

    func attach(_ canvas: PKCanvasView) {
        picker.addObserver(canvas)
    }

    func activate(_ canvas: PKCanvasView) {
        picker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    func hide(_ canvas: PKCanvasView) {
        picker.setVisible(false, forFirstResponder: canvas)
    }
}

/// Lienzo PencilKit transparente que se pinta sobre el papel y guarda en `Page`.
struct DrawingCanvas: UIViewRepresentable {
    let page: Page
    let fingerDrawing: Bool
    let isPrimary: Bool
    let objectMode: Bool
    let tools: ToolPickerHolder
    let onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(page: page, tools: tools, onEdit: onEdit) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light   // la tinta se ve siempre sobre papel claro
        canvas.isScrollEnabled = false               // los gestos de dedo pasan al paginado
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        canvas.delegate = context.coordinator
        if !page.drawingData.isEmpty, let d = try? PKDrawing(data: page.drawingData) {
            canvas.drawing = d
        }
        tools.attach(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        context.coordinator.onEdit = onEdit
        if objectMode {
            DispatchQueue.main.async { tools.hide(canvas) }
        } else if isPrimary {
            DispatchQueue.main.async { tools.activate(canvas) }
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let page: Page
        let tools: ToolPickerHolder
        var onEdit: () -> Void

        init(page: Page, tools: ToolPickerHolder, onEdit: @escaping () -> Void) {
            self.page = page; self.tools = tools; self.onEdit = onEdit
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            page.drawingData = canvasView.drawing.dataRepresentation()
            onEdit()
        }

        // Al empezar a dibujar en una hoja, pasa a ser la que recibe deshacer/rehacer.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if !canvasView.isFirstResponder {
                Task { @MainActor in tools.activate(canvasView) }
            }
        }
    }
}
