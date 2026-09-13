#if os(macOS)
import Testing
import CoreGraphics
@testable import SwiftTerm

/// When a drag-select scrolls, which way, and how fast.
///
/// The drag used to compute a speed and then never start the timer that
/// consumed it, so text more than a screen above could not be selected by
/// dragging at all.
@Suite("Selection autoscroll")
struct SelectionAutoScrollTests {
    private let height: CGFloat = 480
    private let cell: CGFloat = 16

    private func lines(atY y: CGFloat) -> Int {
        TerminalView.selectionAutoScrollLines(pointY: y, viewHeight: height, cellHeight: cell, rows: 30)
    }

    @Test("Inside the view, including on the edge rows, nothing scrolls")
    func insideDoesNotScroll() {
        // AppKit coordinates: y grows upward, so the top row is near `height`.
        #expect(lines(atY: height - 1) == 0, "the top row selects the top row")
        #expect(lines(atY: 1) == 0, "the bottom row selects the bottom row")
        #expect(lines(atY: height) == 0)
        #expect(lines(atY: 0) == 0)
    }

    @Test("Above the view scrolls back into history")
    func aboveScrollsUp() {
        #expect(lines(atY: height + 1) < 0)
    }

    @Test("Below the view scrolls forward")
    func belowScrollsDown() {
        // The old timer called scrollUp for both directions.
        #expect(lines(atY: -1) > 0)
    }

    @Test("The further outside, the faster")
    func speedGrowsWithDistance() {
        let near = abs(lines(atY: height + 1))
        let middle = abs(lines(atY: height + cell * 4))
        let far = abs(lines(atY: height + cell * 20))
        #expect(near < middle)
        #expect(middle < far)
        #expect(far == 30, "top speed is a screenful per tick")
    }

    @Test("Up and down are symmetric")
    func symmetric() {
        for rows in [1, 3, 7, 15] {
            let offset = cell * CGFloat(rows)
            #expect(lines(atY: height + offset) == -lines(atY: -offset))
        }
    }

    @Test("A view with no cell size yet never scrolls")
    func unmeasuredViewIsInert() {
        #expect(TerminalView.selectionAutoScrollLines(pointY: -100, viewHeight: height, cellHeight: 0, rows: 30) == 0)
    }
}
#endif

#if os(macOS)
import AppKit

/// The drag itself, in a real view: holding the pointer above the terminal
/// has to scroll history into view *and* carry the selection with it.
@MainActor
@Suite("Selection autoscroll in a view", .serialized)
struct SelectionAutoScrollViewTests {

    private func makeView() -> (TerminalView, NSWindow) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.allowMouseReporting = false
        for line in 1...500 {
            view.feed(text: "line \(line)\r\n")
        }
        return (view, window)
    }

    private func drag(_ view: TerminalView, to point: CGPoint, in window: NSWindow) {
        let location = view.convert(point, to: nil)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDragged, location: location, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )!
        view.mouseDragged(with: event)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    @Test("Holding the pointer above the view scrolls back and extends the selection")
    func holdingAboveScrollsBack() {
        let (view, window) = makeView()
        var held = true
        view.isPrimaryMouseButtonHeld = { held }
        let terminal = view.getTerminal()
        let bottom = terminal.displayBuffer.yDisp
        #expect(bottom > 100, "the fixture needs scrollback to scroll into")

        // Start inside the view, then move above it and hold still.
        drag(view, to: CGPoint(x: 20, y: 200), in: window)
        drag(view, to: CGPoint(x: 20, y: view.bounds.height + 40), in: window)
        spin(0.6)

        let scrolled = terminal.displayBuffer.yDisp
        #expect(scrolled < bottom, "the view scrolled into history with the pointer still")
        let selectedTop = min(view.selection.start.row, view.selection.end.row)
        #expect(selectedTop == scrolled, "the selection's edge follows the visible top row")

        // Letting go stops it.
        held = false
        spin(0.15)
        let settled = terminal.displayBuffer.yDisp
        spin(0.3)
        #expect(terminal.displayBuffer.yDisp == settled, "no scrolling once the button is up")
    }

    @Test("Coming back inside the view stops autoscroll")
    func returningInsideStops() {
        let (view, window) = makeView()
        view.isPrimaryMouseButtonHeld = { true }
        let terminal = view.getTerminal()

        drag(view, to: CGPoint(x: 20, y: view.bounds.height + 40), in: window)
        spin(0.3)
        drag(view, to: CGPoint(x: 20, y: 200), in: window)
        let settled = terminal.displayBuffer.yDisp
        spin(0.3)
        #expect(terminal.displayBuffer.yDisp == settled)
    }

    @Test("Dragging below the view scrolls forward, not back")
    func belowScrollsForward() {
        let (view, window) = makeView()
        view.isPrimaryMouseButtonHeld = { true }
        let terminal = view.getTerminal()
        view.scrollUp(lines: 200)
        let start = terminal.displayBuffer.yDisp

        drag(view, to: CGPoint(x: 20, y: 200), in: window)
        drag(view, to: CGPoint(x: 20, y: -40), in: window)
        spin(0.4)
        #expect(terminal.displayBuffer.yDisp > start)
        view.isPrimaryMouseButtonHeld = { false }
        spin(0.1)
    }
}
#endif
