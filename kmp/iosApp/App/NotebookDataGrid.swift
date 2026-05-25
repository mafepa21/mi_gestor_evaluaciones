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
    let onResetWidth: () -> Void
    
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .contentShape(Rectangle())
            
            Rectangle()
                .fill(isDragging ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.20)))
                .frame(width: (isDragging || isHovering) ? 2 : 1)
                
            if isDragging || isHovering {
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 36)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: 12)
        .modifier(NotebookResizeCursorModifier())
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        #endif
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    onDragChanged(value.translation.width)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
        .onTapGesture(count: 2) {
            onResetWidth()
        }
        .contextMenu {
            Button("Restaurar ancho recomendado") {
                onResetWidth()
            }
        }
        .help("Arrastrar para redimensionar. Doble clic para restaurar el ancho.")
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
}

final class NotebookScrollSyncCoordinator: ObservableObject {
    #if canImport(UIKit)
    private var uiScrollViews = NSMapTable<NSString, UIScrollView>(keyOptions: .strongMemory, valueOptions: .weakMemory)
    #endif
    #if canImport(AppKit)
    private var nsScrollViews = NSMapTable<NSString, NSScrollView>(keyOptions: .strongMemory, valueOptions: .weakMemory)
    #endif
    
    private var isSyncing = false
    
    #if canImport(UIKit)
    func register(id: String, scrollView: UIScrollView) {
        uiScrollViews.setObject(scrollView, forKey: id as NSString)
    }
    
    func unregister(id: String) {
        uiScrollViews.removeObject(forKey: id as NSString)
    }
    
    func synchronizeScroll(from sourceId: String, offset: CGPoint) {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let enumerator = uiScrollViews.keyEnumerator()
        while let key = enumerator.nextObject() as? NSString {
            let keyStr = key as String
            if keyStr != sourceId, let scrollView = uiScrollViews.object(forKey: key) {
                if abs(scrollView.contentOffset.y - offset.y) > 0.5 {
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset.y), animated: false)
                }
            }
        }
    }
    #endif
    
    #if canImport(AppKit)
    func register(id: String, scrollView: NSScrollView) {
        nsScrollViews.setObject(scrollView, forKey: id as NSString)
    }
    
    func unregister(id: String) {
        nsScrollViews.removeObject(forKey: id as NSString)
    }
    
    func synchronizeScroll(from sourceId: String, offset: NSPoint) {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        let enumerator = nsScrollViews.keyEnumerator()
        while let key = enumerator.nextObject() as? NSString {
            let keyStr = key as String
            if keyStr != sourceId, let scrollView = nsScrollViews.object(forKey: key) {
                let currentOffset = scrollView.contentView.bounds.origin
                if abs(currentOffset.y - offset.y) > 0.5 {
                    scrollView.contentView.scroll(to: NSPoint(x: currentOffset.x, y: offset.y))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }
    }
    #endif
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
    let isFixedColumnResizing: Bool
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
    
    @StateObject private var scrollSyncCoordinator = NotebookScrollSyncCoordinator()

    init(
        fixedColumnWidth: CGFloat,
        trailingFixedColumnWidth: CGFloat,
        isFixedColumnResizing: Bool = false,
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
        self.isFixedColumnResizing = isFixedColumnResizing
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
            NotebookSyncedVerticalScrollView(id: "left", coordinator: scrollSyncCoordinator, showsIndicators: false) {
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
        .shadow(
            color: isFixedColumnResizing ? .clear : fixedColumnShadowColor,
            radius: isFixedColumnResizing ? 0 : fixedColumnShadowRadius,
            x: 1,
            y: 0
        )
        .transaction { transaction in
            if isFixedColumnResizing {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
        .zIndex(2)
    }

    private var centerScrollablePane: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                scrollTopAccessory
                    .frame(height: topAccessoryHeight, alignment: .topLeading)
                scrollHeader
                    .frame(height: headerHeight, alignment: .topLeading)
                NotebookSyncedVerticalScrollView(id: "center", coordinator: scrollSyncCoordinator, showsIndicators: true) {
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
            NotebookSyncedVerticalScrollView(id: "right", coordinator: scrollSyncCoordinator, showsIndicators: false) {
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
        if isFixedColumnResizing {
            appSecondarySystemBackgroundColor().opacity(0.94)
        } else {
            Rectangle()
                .fill(.thinMaterial)
                .overlay(appSecondarySystemBackgroundColor().opacity(0.72))
        }
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
    let id: String
    let coordinator: NotebookScrollSyncCoordinator
    let showsIndicators: Bool
    let content: Content

    init(
        id: String,
        coordinator: NotebookScrollSyncCoordinator,
        showsIndicators: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.coordinator = coordinator
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        #if canImport(AppKit)
        NotebookSyncedVerticalNSScrollView(
            id: id,
            coordinator: coordinator,
            showsIndicators: showsIndicators,
            content: content
        )
        #elseif canImport(UIKit)
        NotebookSyncedVerticalUIScrollView(
            id: id,
            coordinator: coordinator,
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
    let id: String
    let coordinator: NotebookScrollSyncCoordinator
    let showsIndicators: Bool
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(id: id, coordinator: coordinator)
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
        coordinator.register(id: id, scrollView: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        scrollView.showsVerticalScrollIndicator = showsIndicators
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        coordinator.coordinator.unregister(id: coordinator.id)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let id: String
        let coordinator: NotebookScrollSyncCoordinator
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<Content>?

        init(id: String, coordinator: NotebookScrollSyncCoordinator) {
            self.id = id
            self.coordinator = coordinator
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            coordinator.synchronizeScroll(from: id, offset: scrollView.contentOffset)
        }
    }
}
#endif

#if canImport(AppKit)
private struct NotebookSyncedVerticalNSScrollView<Content: View>: NSViewRepresentable {
    let id: String
    let coordinator: NotebookScrollSyncCoordinator
    let showsIndicators: Bool
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(id: id, coordinator: coordinator)
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

        coordinator.register(id: id, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.coordinator.unregister(id: coordinator.id)
    }

    final class Coordinator {
        let id: String
        let coordinator: NotebookScrollSyncCoordinator
        weak var scrollView: NSScrollView?
        var observer: NSObjectProtocol?

        init(id: String, coordinator: NotebookScrollSyncCoordinator) {
            self.id = id
            self.coordinator = coordinator
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func scrollViewDidScroll() {
            guard let scrollView else { return }
            coordinator.synchronizeScroll(from: id, offset: scrollView.contentView.bounds.origin)
        }
    }
}
#endif
