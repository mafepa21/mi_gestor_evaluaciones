import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct NotebookDividerHandle: View {
    let isDragging: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25))
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -6))
            .modifier(NotebookResizeCursorModifier())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onDragChanged(value.translation.width)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

struct NotebookResizableHeader<Content: View>: View {
    let width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let onWidthChange: (CGFloat) -> Void
    let content: Content

    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 0

    init(
        width: CGFloat,
        minWidth: CGFloat = 80,
        maxWidth: CGFloat = 400,
        onWidthChange: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.onWidthChange = onWidthChange
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            content

            Rectangle()
                .fill(isDragging ? Color.accentColor : Color.clear)
                .frame(width: isDragging ? 2 : 4)
                .contentShape(Rectangle())
                .modifier(NotebookResizeCursorModifier())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartWidth = width
                            }
                            onWidthChange(min(maxWidth, max(minWidth, dragStartWidth + value.translation.width)))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
        .frame(width: width)
    }
}

private struct NotebookResizeCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(AppKit)
        content.onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        #else
        content
        #endif
    }
}

struct NotebookDataGrid<FixedTopAccessory: View, DividerHandle: View, ScrollTopAccessory: View, FixedHeader: View, ScrollHeader: View, FixedRows: View, ScrollRows: View>: View {
    let fixedColumnWidth: CGFloat
    let fixedTopAccessory: FixedTopAccessory
    let dividerHandle: DividerHandle
    let scrollTopAccessory: ScrollTopAccessory
    let fixedHeader: FixedHeader
    let scrollHeader: ScrollHeader
    let fixedRows: FixedRows
    let scrollRows: ScrollRows

    init(
        fixedColumnWidth: CGFloat,
        @ViewBuilder fixedTopAccessory: () -> FixedTopAccessory,
        @ViewBuilder dividerHandle: () -> DividerHandle,
        @ViewBuilder scrollTopAccessory: () -> ScrollTopAccessory,
        @ViewBuilder fixedHeader: () -> FixedHeader,
        @ViewBuilder scrollHeader: () -> ScrollHeader,
        @ViewBuilder fixedRows: () -> FixedRows,
        @ViewBuilder scrollRows: () -> ScrollRows
    ) {
        self.fixedColumnWidth = fixedColumnWidth
        self.fixedTopAccessory = fixedTopAccessory()
        self.dividerHandle = dividerHandle()
        self.scrollTopAccessory = scrollTopAccessory()
        self.fixedHeader = fixedHeader()
        self.scrollHeader = scrollHeader()
        self.fixedRows = fixedRows()
        self.scrollRows = scrollRows()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    fixedTopAccessory
                    fixedHeader
                    fixedRows
                }
                .frame(width: fixedColumnWidth, alignment: .topLeading)
                .background(appSecondarySystemBackgroundColor().opacity(0.94))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 2, y: 0)
                .zIndex(1)

                dividerHandle

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        scrollTopAccessory
                        scrollHeader
                        scrollRows
                    }
                }
            }
        }
    }
}
