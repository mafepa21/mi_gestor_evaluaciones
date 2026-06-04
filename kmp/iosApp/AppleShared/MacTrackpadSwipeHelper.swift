import SwiftUI

#if canImport(AppKit)
import AppKit

struct MacTrackpadSwipeOverlay: NSViewRepresentable {
    let onSwipeChanged: (CGFloat) -> Void
    let onSwipeEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeChanged: onSwipeChanged, onSwipeEnded: onSwipeEnded)
    }

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        context.coordinator.removeMonitor()
        
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak nsView] event in
            guard let nsView = nsView, nsView.window != nil, !nsView.visibleRect.isEmpty else {
                return event
            }
            
            let locationInWindow = event.locationInWindow
            let locationInView = nsView.convert(locationInWindow, from: nil)
            
            guard nsView.bounds.contains(locationInView) else {
                return event
            }
            
            let phase = event.phase
            let isTrackpad = phase != [] || event.momentumPhase != []
            
            guard isTrackpad else {
                return event
            }
            
            let coordinator = context.coordinator
            
            if phase == .began {
                if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                    coordinator.isSwipeActive = true
                    coordinator.accumulatedDeltaX = 0
                    coordinator.accumulatedDeltaX += event.scrollingDeltaX
                    coordinator.onSwipeChanged(coordinator.accumulatedDeltaX)
                    return nil // Consume el evento
                } else {
                    coordinator.isSwipeActive = false
                    return event
                }
            } else if phase == .changed && coordinator.isSwipeActive {
                coordinator.accumulatedDeltaX += event.scrollingDeltaX
                coordinator.onSwipeChanged(coordinator.accumulatedDeltaX)
                return nil // Consume el evento
            } else if (phase == .ended || phase == .cancelled) && coordinator.isSwipeActive {
                coordinator.accumulatedDeltaX += event.scrollingDeltaX
                coordinator.onSwipeEnded(coordinator.accumulatedDeltaX)
                coordinator.isSwipeActive = false
                return nil // Consume el evento
            } else if coordinator.isSwipeActive {
                return nil
            }
            
            return event
        }
        
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipeChanged = onSwipeChanged
        context.coordinator.onSwipeEnded = onSwipeEnded
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    class Coordinator {
        var onSwipeChanged: (CGFloat) -> Void
        var onSwipeEnded: (CGFloat) -> Void
        var accumulatedDeltaX: CGFloat = 0
        var isSwipeActive = false
        var monitor: Any?

        init(onSwipeChanged: @escaping (CGFloat) -> Void, onSwipeEnded: @escaping (CGFloat) -> Void) {
            self.onSwipeChanged = onSwipeChanged
            self.onSwipeEnded = onSwipeEnded
        }

        deinit {
            removeMonitor()
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif

extension View {
    func macTrackpadSwipe(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat) -> Void
    ) -> some View {
        #if canImport(AppKit)
        self.background(
            MacTrackpadSwipeOverlay(onSwipeChanged: onChanged, onSwipeEnded: onEnded)
        )
        #else
        self
        #endif
    }
}
