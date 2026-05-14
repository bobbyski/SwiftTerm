#if os(macOS)
import AppKit
import Testing

@testable import SwiftTerm

@MainActor
final class VTGTerminalOverlayContainerViewTests {
    @Test func typedContainerExposesTerminalAndReportsResize() {
        let terminalView = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let container = VTGTypedTerminalOverlayContainerView(
            frame: NSRect(x: 0, y: 0, width: 120, height: 80),
            terminalView: terminalView
        )

        var resizeEvents: [Bool] = []
        container.resizeNotification = { force in
            resizeEvents.append(force)
        }

        #expect(container.terminalView === terminalView)
        #expect(container.terminalContentView === terminalView)
        #expect(container.overlayView.superview === container)

        container.layout()
        container.setFrameSize(NSSize(width: 160, height: 100))
        container.viewDidEndLiveResize()

        #expect(resizeEvents == [false, false, true])
    }
}
#endif
