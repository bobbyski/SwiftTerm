import Foundation
import Testing

@testable import SwiftTerm

/// Touches as the mouse (BASIC-25): what each gesture sends to a program
/// that reads the mouse.
@Suite("Touches as the mouse")
struct TouchMouseInterpreterTests {
    private typealias T = TouchMouseInterpreter

    private func at(_ col: Int, _ row: Int) -> T.Location {
        T.Location(cell: Position(col: col, row: row), pixel: Position(col: col * 8, row: row * 16))
    }

    @Test("A tap is a left click where the finger lifted, and nothing before")
    func tap() {
        var mouse = T()
        #expect(mouse.began(touches: 1, at: at(3, 4)).isEmpty)
        #expect(mouse.ended(remaining: 0, at: at(3, 4)) == [
            .press(button: T.left, at: at(3, 4)), .release(button: T.left, at: at(3, 4)),
        ])
        #expect(mouse.endedAsTap)
    }

    @Test("A finger moving moves the pointer with no button, then clicks where it lifts")
    func hoverThenClick() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(1, 1))
        #expect(mouse.moved(to: at(2, 1)) == [.motion(button: nil, at: at(2, 1))])
        #expect(mouse.moved(to: at(2, 1)).isEmpty, "the same cell again is not a move")
        #expect(mouse.moved(to: at(5, 2)) == [.motion(button: nil, at: at(5, 2))])
        #expect(mouse.ended(remaining: 0, at: at(5, 2)) == [
            .press(button: T.left, at: at(5, 2)), .release(button: T.left, at: at(5, 2)),
        ])
        #expect(!mouse.endedAsTap, "a moved finger does not also count as a focusing tap")
    }

    @Test("A second finger makes it a right click, when both have lifted")
    func twoFingers() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(4, 4))
        #expect(mouse.began(touches: 2, at: at(4, 4)).isEmpty)
        #expect(mouse.ended(remaining: 1, at: at(4, 4)).isEmpty, "one finger still down")
        #expect(mouse.ended(remaining: 0, at: at(4, 4)) == [
            .press(button: T.right, at: at(4, 4)), .release(button: T.right, at: at(4, 4)),
        ])
    }

    @Test("A third finger makes it the middle button")
    func threeFingers() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(0, 0))
        _ = mouse.began(touches: 2, at: at(0, 0))
        _ = mouse.began(touches: 3, at: at(0, 0))
        _ = mouse.ended(remaining: 2, at: at(0, 0))
        _ = mouse.ended(remaining: 1, at: at(0, 0))
        #expect(mouse.ended(remaining: 0, at: at(0, 0)) == [
            .press(button: T.middle, at: at(0, 0)), .release(button: T.middle, at: at(0, 0)),
        ])
    }

    @Test("Two fingers dragged scroll a step a row, down scrolling back, and end without a click")
    func twoFingerScroll() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(2, 2))
        _ = mouse.began(touches: 2, at: at(2, 2))
        #expect(mouse.scrolled(centreY: 100, cellHeight: 16, at: at(2, 2)).isEmpty, "the first sample anchors it")
        #expect(mouse.scrolled(centreY: 110, cellHeight: 16, at: at(2, 2)).isEmpty, "under a row is not a step")
        #expect(mouse.scrolled(centreY: 133, cellHeight: 16, at: at(2, 2)) == [
            .wheel(up: true, at: at(2, 2)), .wheel(up: true, at: at(2, 2)),
        ])
        #expect(mouse.scrolled(centreY: 115, cellHeight: 16, at: at(2, 2)) == [.wheel(up: false, at: at(2, 2))])
        #expect(mouse.moved(to: at(9, 9)).isEmpty, "the pointer does not wander while scrolling")
        _ = mouse.ended(remaining: 1, at: at(2, 2))
        #expect(mouse.ended(remaining: 0, at: at(2, 2)).isEmpty)
    }

    @Test("A second finger holds the pointer still, before any scroll starts")
    func secondFingerHoldsPointer() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(2, 2))
        _ = mouse.began(touches: 2, at: at(2, 2))
        _ = mouse.scrolled(centreY: 100, cellHeight: 16, at: at(2, 2))
        #expect(mouse.moved(to: at(2, 3)).isEmpty, "the drift before a row's travel is not a move")
        _ = mouse.ended(remaining: 1, at: at(2, 3))
        #expect(mouse.ended(remaining: 0, at: at(2, 3)) == [
            .press(button: T.right, at: at(2, 3)), .release(button: T.right, at: at(2, 3)),
        ])
    }

    @Test("One finger never scrolls")
    func oneFingerDoesNotScroll() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(2, 2))
        _ = mouse.scrolled(centreY: 0, cellHeight: 16, at: at(2, 2))
        #expect(mouse.scrolled(centreY: 200, cellHeight: 16, at: at(2, 2)).isEmpty)
    }

    @Test("Press and hold, then drag, is a drag with the button down and released on lift")
    func pressHoldDrag() {
        var mouse = T()
        _ = mouse.began(touches: 1, at: at(1, 1))
        #expect(mouse.held(at: at(1, 1)) == [.press(button: T.left, at: at(1, 1))])
        #expect(mouse.moved(to: at(6, 3)) == [.motion(button: T.left, at: at(6, 3))])
        #expect(mouse.ended(remaining: 0, at: at(6, 3)) == [.release(button: T.left, at: at(6, 3))],
                "the release is the end of the drag, not another click")
    }

    @Test("Holding after moving, or with two fingers, does not press")
    func holdOnlyFromStill() {
        var moved = T()
        _ = moved.began(touches: 1, at: at(1, 1))
        _ = moved.moved(to: at(4, 1))
        #expect(moved.held(at: at(4, 1)).isEmpty)

        var two = T()
        _ = two.began(touches: 1, at: at(1, 1))
        _ = two.began(touches: 2, at: at(1, 1))
        #expect(two.held(at: at(1, 1)).isEmpty)
    }

    @Test("A mouse or trackpad pointer presses on down and releases on up")
    func pointer() {
        var mouse = T()
        #expect(mouse.began(touches: 1, at: at(2, 2), pointerButton: T.right) == [.press(button: T.right, at: at(2, 2))])
        #expect(mouse.moved(to: at(3, 2)) == [.motion(button: T.right, at: at(3, 2))])
        #expect(mouse.ended(remaining: 0, at: at(3, 2)) == [.release(button: T.right, at: at(3, 2))])
    }

    @Test("Cancelled touches click nothing, but a held button is let go")
    func cancelled() {
        var tap = T()
        _ = tap.began(touches: 1, at: at(1, 1))
        #expect(tap.cancelled(at: at(1, 1)).isEmpty)

        var drag = T()
        _ = drag.began(touches: 1, at: at(1, 1))
        _ = drag.held(at: at(1, 1))
        #expect(drag.cancelled(at: at(2, 2)) == [.release(button: T.left, at: at(2, 2))])
    }

    @Test("The button codes are xterm's: left 0, middle 1, right 2")
    func buttonCodes() {
        #expect(T.left == 0)
        #expect(T.middle == 1)
        #expect(T.right == 2)
    }
}
