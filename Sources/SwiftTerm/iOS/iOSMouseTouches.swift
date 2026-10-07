//
//  iOSMouseTouches.swift
//
//  Touches as the mouse on iPhone and iPad, for a program that has turned on
//  mouse reporting. The rules are TouchMouseInterpreter's; this feeds it the
//  touches and sends xterm mouse reports for what it answers.
//
#if os(iOS) || os(visionOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Follows the touches on a terminal while its program reads the mouse.
///
/// It recognises the moment a finger goes down, so the terminal's own taps,
/// long press and scrolling stand aside for the gesture — the program is
/// reading the mouse, and a touch is its mouse. When the program does not
/// read the mouse it fails at once and touches work as they always have.
final class MouseTouchTracker: UIGestureRecognizer {
    weak var terminalView: TerminalView?

    private var interpreter = TouchMouseInterpreter()
    private var active: Set<UITouch> = []
    private var primary: UITouch?
    private var scrollWasEnabled: Bool?
    /// Pressing and holding presses the button; this waits for the hold.
    private var holdTimer: Timer?
    private var holdStart: CGPoint?
    /// How far a finger may wander and still count as held still: a finger
    /// is never perfectly still, and a cell is the wrong yardstick for that.
    private let holdSlop: CGFloat = 10

    init(terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(target: nil, action: nil)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let terminalView else {
            state = .failed
            return
        }
        if primary == nil {
            guard terminalView.reportsTouchesAsMouse(event), let first = touches.first else {
                state = .failed
                return
            }
            primary = first
            // The terminal scrolling under a finger the program is reading
            // would move what the program is pointing at.
            scrollWasEnabled = terminalView.isScrollEnabled
            terminalView.isScrollEnabled = false
        }
        active.formUnion(touches)
        guard let primary else { return }
        var pointerButton: Int?
        if primary.type == .indirectPointer {
            pointerButton = event.buttonMask.contains(.secondary)
                ? TouchMouseInterpreter.right : TouchMouseInterpreter.left
        }
        let reports = interpreter.began(
            touches: active.count,
            at: terminalView.mouseLocation(of: primary),
            pointerButton: pointerButton
        )
        terminalView.sendMouseReports(reports)
        if active.count == 1, pointerButton == nil, state == .possible {
            startHoldTimer(for: primary, in: terminalView)
        } else {
            // A second finger is a right click or a scroll, never a drag.
            cancelHoldTimer()
        }
        state = state == .possible ? .began : .changed
    }

    private func startHoldTimer(for touch: UITouch, in terminalView: TerminalView) {
        cancelHoldTimer()
        holdStart = touch.location(in: terminalView)
        let timer = Timer(timeInterval: terminalView.touchMouseHoldDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let terminalView = self.terminalView, let primary = self.primary else { return }
                self.holdTimer = nil
                self.holdStart = nil
                let reports = self.interpreter.held(at: terminalView.mouseLocation(of: primary))
                guard !reports.isEmpty else { return }
                terminalView.sendMouseReports(reports)
                // Felt rather than seen: the button is down, so a drag now drags.
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let terminalView, let primary else { return }
        var reports: [TouchMouseInterpreter.Report] = []
        if active.count >= 2 {
            let centreY = active.reduce(0.0) { $0 + Double($1.location(in: terminalView).y) }
                / Double(active.count)
            reports += interpreter.scrolled(
                centreY: centreY,
                cellHeight: Double(terminalView.cellDimension.height),
                at: terminalView.mouseLocation(of: primary)
            )
        }
        if touches.contains(primary) {
            if let holdStart {
                let point = primary.location(in: terminalView)
                if hypot(point.x - holdStart.x, point.y - holdStart.y) > holdSlop {
                    // It moved before the hold: a hover, clicked on lift.
                    cancelHoldTimer()
                    self.holdStart = nil
                }
            }
            // Within the slop, waiting for the hold, the finger is still as
            // far as the program is concerned — a wobble across a cell edge
            // must not turn a press-and-hold into a hover.
            if holdStart == nil || holdTimer == nil {
                reports += interpreter.moved(to: terminalView.mouseLocation(of: primary))
            }
        }
        terminalView.sendMouseReports(reports)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let terminalView, let primary else { return }
        cancelHoldTimer()
        active.subtract(touches)
        let reports = interpreter.ended(remaining: active.count, at: terminalView.mouseLocation(of: primary))
        terminalView.sendMouseReports(reports)
        guard active.isEmpty else {
            state = .changed
            return
        }
        if interpreter.endedAsTap {
            terminalView.mouseTapEnded()
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelHoldTimer()
        guard let terminalView, let primary else { return }
        terminalView.sendMouseReports(interpreter.cancelled(at: terminalView.mouseLocation(of: primary)))
        state = .cancelled
    }

    override func reset() {
        super.reset()
        cancelHoldTimer()
        holdStart = nil
        if let scrollWasEnabled {
            terminalView?.isScrollEnabled = scrollWasEnabled
        }
        scrollWasEnabled = nil
        active = []
        primary = nil
        interpreter = TouchMouseInterpreter()
    }
}

extension TerminalView {
    /// Whether a touch now is the program's mouse: it has asked for mouse
    /// reports, the user has not turned them off with the key bar's hand
    /// button, and Shift on a hardware keyboard is not asking for the
    /// terminal's own selection instead.
    func reportsTouchesAsMouse(_ event: UIEvent) -> Bool {
        guard allowMouseReporting, terminal.mouseMode != .off else { return false }
        return !(event.modifierFlags.contains(.shift) && !terminal.mouseShiftCapture)
    }

    func mouseLocation(of touch: UITouch) -> TouchMouseInterpreter.Location {
        let hit = calculateTapHit(point: touch.location(in: self))
        let cell = hit.grid.toScreenCoordinate(from: terminal.displayBuffer) ?? hit.grid
        return TouchMouseInterpreter.Location(cell: cell, pixel: hit.pixels)
    }

    /// Sends the interpreter's reports, each only if the program's mouse mode
    /// asked for that kind.
    func sendMouseReports(_ reports: [TouchMouseInterpreter.Report]) {
        let mode = terminal.mouseMode
        for report in reports {
            switch report {
            case .press(let button, let at):
                guard mode.sendButtonPress() else { continue }
                terminal.sendEvent(buttonFlags: mouseButtonFlags(button, release: false),
                                   x: at.cell.col, y: at.cell.row, pixelX: at.pixel.col, pixelY: at.pixel.row)
            case .release(let button, let at):
                guard mode.sendButtonRelease() else { continue }
                terminal.sendEvent(buttonFlags: mouseButtonFlags(button, release: true),
                                   x: at.cell.col, y: at.cell.row, pixelX: at.pixel.col, pixelY: at.pixel.row)
            case .motion(let button, let at):
                if let button {
                    guard mode.sendButtonTracking() else { continue }
                    terminal.sendMotion(buttonFlags: mouseButtonFlags(button, release: false),
                                        x: at.cell.col, y: at.cell.row, pixelX: at.pixel.col, pixelY: at.pixel.row)
                } else {
                    // A move with no button held: only "any event" mode wants it.
                    guard mode.sendMotionEvent() else { continue }
                    terminal.sendMotion(buttonFlags: 3,
                                        x: at.cell.col, y: at.cell.row, pixelX: at.pixel.col, pixelY: at.pixel.row)
                }
            case .wheel(let up, let at):
                guard mode.sendButtonPress() else { continue }
                terminal.sendEvent(buttonFlags: terminal.encodeButton(button: up ? 4 : 5, release: false,
                                                                      shift: false, meta: false, control: false),
                                   x: at.cell.col, y: at.cell.row, pixelX: at.pixel.col, pixelY: at.pixel.row)
            }
        }
    }

    /// A button's flags, with Control from the key bar's ctrl key, which
    /// applies to one click and then lets go.
    private func mouseButtonFlags(_ button: Int, release: Bool) -> Int {
        let control = terminalAccessory?.controlModifier ?? controlModifier ?? false
        if !release {
            terminalAccessory?.controlModifier = false
            controlModifier = false
        }
        return terminal.encodeButton(button: button, release: release, shift: false, meta: false, control: control)
    }

    /// What a plain tap does besides clicking, the same as a tap with no
    /// program reading the mouse: take the keyboard focus, or bring back a
    /// keyboard that was put away.
    func mouseTapEnded() {
        if !isFirstResponder {
            _ = becomeFirstResponder()
        } else if isSoftwareKeyboardHidden && (showsHiddenKeyboardOnTap?() ?? true) {
            isSoftwareKeyboardHidden = false
        }
    }
}
#endif
