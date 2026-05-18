import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

let isDebugGridEnabled = false // TEMPORARY: Set to true to debug alignment

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

struct NotebookDataGrid<FixedTopAccessory: View, DividerHandle: View, TrailingFixedTopAccessory: View, ScrollTopAccessory: View, FixedHeader: View, TrailingFixedHeader: View, ScrollHeader: View, FixedRows: View, TrailingFixedRows: View, ScrollRows: View>: View {
    let fixedColumnWidth: CGFloat
    let trailingFixedColumnWidth: CGFloat
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let fixedTopAccessory: FixedTopAccessory
    let dividerHandle: DividerHandle
    let trailingFixedTopAccessory: TrailingFixedTopAccessory
    let scrollTopAccessory: ScrollTopAccessory
    let fixedHeader: FixedHeader
    let trailingFixedHeader: TrailingFixedHeader
    let scrollHeader: ScrollHeader
    let fixedRows: FixedRows
    let trailingFixedRows: TrailingFixedRows
    let scrollRows: ScrollRows
    @State private var verticalScrollOffset: CGFloat = 0

    init(
        fixedColumnWidth: CGFloat,
        trailingFixedColumnWidth: CGFloat,
        topAccessoryHeight: CGFloat,
        headerHeight: CGFloat,
        @ViewBuilder fixedTopAccessory: () -> FixedTopAccessory,
        @ViewBuilder dividerHandle: () -> DividerHandle,
        @ViewBuilder trailingFixedTopAccessory: () -> TrailingFixedTopAccessory,
        @ViewBuilder scrollTopAccessory: () -> ScrollTopAccessory,
        @ViewBuilder fixedHeader: () -> FixedHeader,
        @ViewBuilder trailingFixedHeader: () -> TrailingFixedHeader,
        @ViewBuilder scrollHeader: () -> ScrollHeader,
        @ViewBuilder fixedRows: () -> FixedRows,
        @ViewBuilder trailingFixedRows: () -> TrailingFixedRows,
        @ViewBuilder scrollRows: () -> ScrollRows
    ) {
        self.fixedColumnWidth = fixedColumnWidth
        self.trailingFixedColumnWidth = trailingFixedColumnWidth
        self.topAccessoryHeight = topAccessoryHeight
        self.headerHeight = headerHeight
        self.fixedTopAccessory = fixedTopAccessory()
        self.dividerHandle = dividerHandle()
        self.trailingFixedTopAccessory = trailingFixedTopAccessory()
        self.scrollTopAccessory = scrollTopAccessory()
        self.fixedHeader = fixedHeader()
        self.trailingFixedHeader = trailingFixedHeader()
        self.scrollHeader = scrollHeader()
        self.fixedRows = fixedRows()
        self.trailingFixedRows = trailingFixedRows()
        self.scrollRows = scrollRows()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            fixedLeftPane
                .border(isDebugGridEnabled ? Color.red : Color.clear, width: 1)
            dividerHandle
            centerScrollablePane
                .border(isDebugGridEnabled ? Color.green : Color.clear, width: 1)
            if trailingFixedColumnWidth > 0 {
                trailingRightPane
                    .border(isDebugGridEnabled ? Color.blue : Color.clear, width: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fixedLeftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            fixedTopAccessory
                .frame(height: topAccessoryHeight, alignment: .topLeading)
            fixedHeader
                .frame(height: headerHeight, alignment: .topLeading)
            NotebookSyncedVerticalScrollView(offset: $verticalScrollOffset, showsIndicators: false) {
                fixedRows
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: fixedColumnWidth, alignment: .topLeading)
        .background(fixedColumnBackground)
        .overlay(alignment: .trailing) {
            fixedColumnSeparator
        }
        .shadow(color: fixedColumnShadowColor, radius: fixedColumnShadowRadius, x: 1, y: 0)
        .zIndex(2)
    }

    private var centerScrollablePane: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                scrollTopAccessory
                    .frame(height: topAccessoryHeight, alignment: .topLeading)
                scrollHeader
                    .frame(height: headerHeight, alignment: .topLeading)
                NotebookSyncedVerticalScrollView(offset: $verticalScrollOffset, showsIndicators: true) {
                    scrollRows
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var trailingRightPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            trailingFixedTopAccessory
                .frame(height: topAccessoryHeight, alignment: .topLeading)
            trailingFixedHeader
                .frame(height: headerHeight, alignment: .topLeading)
            NotebookSyncedVerticalScrollView(offset: $verticalScrollOffset, showsIndicators: false) {
                trailingFixedRows
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: trailingFixedColumnWidth, alignment: .topLeading)
        .background(fixedColumnBackground)
        .overlay(alignment: .leading) {
            fixedColumnSeparator
        }
        .shadow(color: fixedColumnShadowColor, radius: fixedColumnShadowRadius, x: -1, y: 0)
        .zIndex(2)
    }

    @ViewBuilder
    private var fixedColumnBackground: some View {
        #if os(macOS)
        Rectangle()
            .fill(.thinMaterial)
            .overlay(appSecondarySystemBackgroundColor().opacity(0.72))
        #else
        appSecondarySystemBackgroundColor().opacity(0.94)
        #endif
    }

    @ViewBuilder
    private var fixedColumnSeparator: some View {
        #if os(macOS)
        LinearGradient(
            colors: [
                Color.clear,
                NotebookStyle.softBorder.opacity(0.70),
                NotebookStyle.softBorder.opacity(0.70),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        #else
        Color.secondary.opacity(0.12)
            .frame(width: 1)
        #endif
    }

    private var fixedColumnShadowColor: Color {
        #if os(macOS)
        return Color.black.opacity(0.035)
        #else
        return Color.black.opacity(0.08)
        #endif
    }

    private var fixedColumnShadowRadius: CGFloat {
        #if os(macOS)
        return 2
        #else
        return 4
        #endif
    }
}

private struct NotebookSyncedVerticalScrollView<Content: View>: View {
    @Binding var offset: CGFloat
    let showsIndicators: Bool
    let content: Content

    init(
        offset: Binding<CGFloat>,
        showsIndicators: Bool,
        @ViewBuilder content: () -> Content
    ) {
        _offset = offset
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        #if canImport(AppKit)
        NotebookSyncedVerticalNSScrollView(
            offset: $offset,
            showsIndicators: showsIndicators,
            content: content
        )
        #elseif canImport(UIKit)
        NotebookSyncedVerticalUIScrollView(
            offset: $offset,
            showsIndicators: showsIndicators,
            content: content
        )
        #else
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            content
        }
        #endif
    }
}

#if canImport(UIKit)
private struct NotebookSyncedVerticalUIScrollView<Content: View>: UIViewRepresentable {
    @Binding var offset: CGFloat
    let showsIndicators: Bool
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = showsIndicators
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.backgroundColor = .clear

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        scrollView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        context.coordinator.hostingController = hostingController
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.offset = $offset
        context.coordinator.scrollView = scrollView
        context.coordinator.hostingController?.rootView = content
        scrollView.showsVerticalScrollIndicator = showsIndicators
        context.coordinator.applyOffsetIfNeeded()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var offset: Binding<CGFloat>
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<Content>?
        private var isApplyingOffset = false

        init(offset: Binding<CGFloat>) {
            self.offset = offset
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isApplyingOffset else { return }
            let actualOffset = scrollView.contentOffset.y
            if abs(actualOffset - offset.wrappedValue) > 0.5 {
                offset.wrappedValue = actualOffset
            }
        }

        func applyOffsetIfNeeded() {
            guard let scrollView else { return }
            let targetOffset = offset.wrappedValue
            guard abs(scrollView.contentOffset.y - targetOffset) > 0.5 else { return }
            apply(offset: targetOffset, in: scrollView)
        }

        private func apply(offset: CGFloat, in scrollView: UIScrollView) {
            isApplyingOffset = true
            scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            isApplyingOffset = false
        }
    }
}
#endif

#if canImport(AppKit)
private struct NotebookSyncedVerticalNSScrollView<Content: View>: NSViewRepresentable {
    @Binding var offset: CGFloat
    let showsIndicators: Bool
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = showsIndicators
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.scrollViewDidScroll()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }

        context.coordinator.offset = $offset
        context.coordinator.scrollView = scrollView
        context.coordinator.applyOffsetIfNeeded()
    }

    final class Coordinator {
        var offset: Binding<CGFloat>
        weak var scrollView: NSScrollView?
        var observer: NSObjectProtocol?
        private var isApplyingOffset = false

        init(offset: Binding<CGFloat>) {
            self.offset = offset
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func scrollViewDidScroll() {
            guard !isApplyingOffset, let scrollView else { return }
            let actualOffset = scrollView.contentView.bounds.origin.y
            if abs(actualOffset - offset.wrappedValue) > 0.5 {
                offset.wrappedValue = actualOffset
            }
        }

        func applyOffsetIfNeeded() {
            guard let scrollView else { return }
            let currentOffset = scrollView.contentView.bounds.origin.y
            let targetOffset = offset.wrappedValue
            guard abs(currentOffset - targetOffset) > 0.5 else { return }
            apply(offset: targetOffset, in: scrollView)
        }

        private func apply(offset: CGFloat, in scrollView: NSScrollView) {
            isApplyingOffset = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingOffset = false
        }
    }
}
#endif
