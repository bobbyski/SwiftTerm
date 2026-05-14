#if os(macOS)
import AppKit
import Testing

@testable import SwiftTerm

@MainActor
final class VTGCanvasSizeAppKitTests {
    @Test func bestAvailableCanvasPrefersOverlayBounds() {
        let terminal = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 70))

        let canvas = VTGCanvasSize.bestAvailable(
            preferredView: overlay,
            fallbackView: terminal
        )

        #expect(canvas == VTGCanvasSize(width: 120, height: 70))
    }

    @Test func bestAvailableCanvasFallsBackToSuperviewBeforeTerminalBounds() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        let terminal = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        container.addSubview(terminal)

        let canvas = VTGCanvasSize.bestAvailable(
            preferredView: NSView(frame: .zero),
            fallbackView: terminal
        )

        #expect(canvas == VTGCanvasSize(width: 300, height: 180))
    }

    @Test func bestAvailableCanvasFallsBackToTerminalBounds() {
        let terminal = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 50))

        let canvas = VTGCanvasSize.bestAvailable(
            preferredView: nil,
            fallbackView: terminal
        )

        #expect(canvas == VTGCanvasSize(width: 90, height: 50))
    }
}
#endif
