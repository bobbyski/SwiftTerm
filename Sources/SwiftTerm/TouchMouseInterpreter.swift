//
//  TouchMouseInterpreter.swift
//
//  What touches mean as the mouse, for a program that has asked for mouse
//  reports — the rules, with nothing of UIKit in them, so they can be tested
//  anywhere. The iOS view feeds it touches and sends what it answers.
//
import Foundation

/// Turns touches into mouse reports.
///
/// **One finger** is the left button, clicked when it lifts: putting it down
/// starts tracking, moving it reports the pointer moving (no button held),
/// and lifting it clicks — press and release — where it lifted.
///
/// **Press and hold, then drag**, is a drag with the button down: a finger
/// held still for a moment presses the left button there, moving it then
/// drags with the button held, and lifting it releases the button — no
/// extra click.
///
/// **More fingers** choose the button, Mac and iPad style: a second finger
/// down before the first lifts makes the click a right click, a third makes
/// it the middle. The click comes when the last finger lifts.
///
/// **Two or more fingers moved together scroll**, as on a trackpad: each
/// cell's height of travel is one wheel step, fingers moving down scroll
/// back (up), and a gesture that scrolled ends without a click.
///
/// **A mouse or trackpad pointer** on the iPad is a real mouse: its button
/// is pressed when it goes down, held while it drags, and released when it
/// lifts.
struct TouchMouseInterpreter {
    /// xterm's button codes.
    static let left = 0
    static let middle = 1
    static let right = 2

    /// Where a touch is: the cell it is over, and its pixel position for
    /// the pixel-precise mouse protocol.
    struct Location: Equatable {
        var cell: Position
        var pixel: Position
    }

    enum Report: Equatable {
        /// The pointer moved over a new cell; `button` is the one held, nil
        /// for none.
        case motion(button: Int?, at: Location)
        case press(button: Int, at: Location)
        case release(button: Int, at: Location)
        /// One wheel step: up scrolls back.
        case wheel(up: Bool, at: Location)
    }

    private(set) var isTracking = false
    private var fingers = 0
    private var heldButton: Int?
    private var last: Location?
    private var moved = false
    private var isScrolling = false
    private var scrollAnchorY: Double?
    /// Whether the gesture that just ended was a plain one-finger tap — the
    /// touch that, with no program reading the mouse, would have focused the
    /// terminal or brought its keyboard back.
    private(set) var endedAsTap = false

    /// A touch went down. `touches` is how many are down now, this one
    /// included; `pointerButton` is set for a mouse or trackpad pointer.
    mutating func began(touches: Int, at location: Location, pointerButton: Int? = nil) -> [Report] {
        guard !isTracking else {
            fingers = max(fingers, touches)
            return []
        }
        isTracking = true
        fingers = touches
        last = location
        moved = false
        isScrolling = false
        scrollAnchorY = nil
        endedAsTap = false
        heldButton = pointerButton
        if let pointerButton {
            return [.press(button: pointerButton, at: location)]
        }
        return []
    }

    /// The one finger has been held still long enough: press the left button
    /// where it is, so what follows is a drag. Nothing once the finger has
    /// moved, a second finger is down, or a button is already held.
    mutating func held(at location: Location) -> [Report] {
        guard isTracking, fingers == 1, !moved, heldButton == nil else { return [] }
        heldButton = Self.left
        last = location
        return [.press(button: Self.left, at: location)]
    }

    /// The first finger, or the pointer, moved. Once a second finger is down
    /// the pointer stays put: two fingers are a right click or a scroll, and
    /// the first finger drifting before a scroll starts is not a move.
    mutating func moved(to location: Location) -> [Report] {
        guard isTracking, !isScrolling, fingers < 2, location.cell != last?.cell else { return [] }
        last = location
        moved = true
        return [.motion(button: heldButton, at: location)]
    }

    /// Several fingers are down and their centre is at `centreY` points;
    /// `cellHeight` is one row. A scroll starts once they have travelled a
    /// full row, and every further row is another step.
    mutating func scrolled(centreY: Double, cellHeight: Double, at location: Location) -> [Report] {
        guard isTracking, heldButton == nil, fingers >= 2, cellHeight > 0 else { return [] }
        guard let anchor = scrollAnchorY else {
            scrollAnchorY = centreY
            return []
        }
        let rows = Int((centreY - anchor) / cellHeight)
        guard rows != 0 else { return [] }
        isScrolling = true
        moved = true
        scrollAnchorY = anchor + Double(rows) * cellHeight
        // Fingers moving down pull the content down: that is scrolling back.
        return Array(repeating: .wheel(up: rows > 0, at: location), count: abs(rows))
    }

    /// A touch lifted, leaving `remaining` down. The click, if there is one,
    /// comes when the last one lifts.
    mutating func ended(remaining: Int, at location: Location) -> [Report] {
        guard isTracking, remaining == 0 else { return [] }
        isTracking = false
        if let heldButton {
            self.heldButton = nil
            return [.release(button: heldButton, at: location)]
        }
        guard !isScrolling else { return [] }
        endedAsTap = fingers == 1 && !moved
        let button = fingers >= 3 ? Self.middle : (fingers == 2 ? Self.right : Self.left)
        return [.press(button: button, at: location), .release(button: button, at: location)]
    }

    /// The system took the touches away. Nothing is clicked; a pointer's
    /// held button is let go, so the program is not left holding it.
    mutating func cancelled(at location: Location) -> [Report] {
        guard isTracking else { return [] }
        isTracking = false
        defer { heldButton = nil }
        if let heldButton {
            return [.release(button: heldButton, at: location)]
        }
        return []
    }
}
