#if os(iOS)
import UIKit

/// Touch input for VTG programs on iOS.
///
/// The Mac reports VTG mouse events from `LocalProcessVectorTerminalView`,
/// because that is where AppKit delivers them. iOS has no process view and no
/// mouse, so this is the design the plan left open (IPAD_PLAN.md, Phase 3)
/// rather than a port:
///
/// - **A tap is a click.** It is sent as down, up and click, and the host
///   controller drops whichever of those the program's mouse mode did not ask
///   for — exactly as it does for a real mouse.
/// - **A drag is a drag only when the program asked for drags** (`drag` or
///   `all`). Otherwise a finger scrolls the terminal, as it always has.
/// - **A drag over a scrollable page scrolls the page first**, which is the
///   Mac's wheel rule: the page gets the gesture before the terminal does.
///
/// There is no hover event in VTG, so the iPad pointer's hover reports
/// nothing; UIKit's pointer interaction on `TerminalView` still shapes the
/// cursor.
///
/// A separate object rather than delegate methods on the view, because
/// `UIScrollView` is the delegate of its own pan recognizer and a
/// `gestureRecognizerShouldBegin` on the view would answer for that too.
final class VTGTouchInput: NSObject, UIGestureRecognizerDelegate {
    private weak var view: VectorTerminalView?
    private let tap = UITapGestureRecognizer()
    private let pan = UIPanGestureRecognizer()

    private enum PanRole {
        case none
        case pageScroll
        case drag
    }

    private var panRole: PanRole = .none
    private var lastTranslation: CGPoint = .zero

    init(view: VectorTerminalView) {
        self.view = view
        super.init()

        tap.addTarget(self, action: #selector(handleTap(_:)))
        tap.delegate = self
        // Taps still reach the terminal — focus, the keyboard, selection —
        // when the program has not asked for the mouse.
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        // The terminal's own scrolling waits for this pan to decline. It
        // declines at once unless VTG wants the gesture, so ordinary
        // scrolling is not delayed in any way a finger can feel.
        view.panGestureRecognizer.require(toFail: pan)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let view else {
            return false
        }
        let session = view.vtgSession
        if recognizer === tap {
            return session.sendsMouseEvents
        }
        guard recognizer === pan else {
            return true
        }
        if session.pageMode?.userScrollEnabled == true {
            panRole = .pageScroll
            return true
        }
        if session.sendsMouseEvents, session.mouseMode == .drag || session.mouseMode == .all {
            panRole = .drag
            return true
        }
        panRole = .none
        return false
    }

    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A tap for the program must not stop the terminal's own tap, which
        // is what brings up the keyboard.
        recognizer === tap
    }

    // MARK: - Handlers

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let view,
              let snapshot = snapshot(at: recognizer.location(in: view)) else {
            return
        }
        let session = view.vtgSession
        // Down and up first, so a `raw` program sees a whole press; the
        // controller discards them for a `click` program, which wants only
        // the click.
        session.sendMouseEvent(type: .down, button: 0, snapshot: snapshot)
        session.sendMouseEvent(type: .up, button: 0, snapshot: snapshot)
        session.sendMouseEvent(type: .click, button: 0, snapshot: snapshot)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view else {
            return
        }
        let location = recognizer.location(in: view)
        switch recognizer.state {
        case .began:
            lastTranslation = .zero
            if panRole == .drag, let snapshot = snapshot(at: location) {
                view.vtgSession.sendMouseEvent(type: .down, button: 0, snapshot: snapshot)
            }
        case .changed:
            let translation = recognizer.translation(in: view)
            let delta = CGPoint(x: translation.x - lastTranslation.x, y: translation.y - lastTranslation.y)
            lastTranslation = translation
            switch panRole {
            case .pageScroll:
                // The finger's movement is the Mac's natural-scrolling delta:
                // content follows the finger.
                let point = viewportPoint(location, in: view)
                _ = view.vtgSession.handlePageUserScroll(
                    at: VTGPoint(x: Double(point.x), y: Double(point.y)),
                    deltaX: Double(delta.x),
                    deltaY: Double(delta.y)
                )
            case .drag:
                if let snapshot = snapshot(at: location) {
                    view.vtgSession.sendMouseEvent(type: .drag, button: 0, snapshot: snapshot)
                }
            case .none:
                break
            }
        case .ended, .cancelled, .failed:
            if panRole == .drag, let snapshot = snapshot(at: location) {
                view.vtgSession.sendMouseEvent(type: .up, button: 0, snapshot: snapshot)
            }
            panRole = .none
        default:
            break
        }
    }

    // MARK: - Coordinates

    /// A location in the view's bounds, moved to the visible viewport.
    ///
    /// The terminal is a `UIScrollView`, so its bounds origin is the scroll
    /// offset; the VTG canvas is the visible rectangle, which is where the
    /// overlay sits.
    private func viewportPoint(_ location: CGPoint, in view: VectorTerminalView) -> CGPoint {
        CGPoint(x: location.x - view.bounds.origin.x, y: location.y - view.bounds.origin.y)
    }

    private func snapshot(at location: CGPoint) -> VTGMouseSnapshot? {
        guard let view else {
            return nil
        }
        let point = viewportPoint(location, in: view)
        let terminal = view.getTerminal()
        // A locked screen reports in its own pixels, so the fraction across
        // the view is scaled into the screen rather than into the window.
        let canvas = view.vtgEventCanvas(
            viewWidth: Double(view.bounds.width),
            viewHeight: Double(view.bounds.height)
        )
        let scaleX = view.bounds.width > 0 ? canvas.width / Double(view.bounds.width) : 1
        let scaleY = view.bounds.height > 0 ? canvas.height / Double(view.bounds.height) : 1
        let mapper = VTGMouseCoordinateMapper(
            columns: terminal.cols,
            rows: terminal.rows,
            canvasWidth: canvas.width,
            canvasHeight: canvas.height
        )
        // UIKit is top-left already: no `bounds.height - y` as on the Mac.
        guard let position = mapper.cellPosition(
            pixelX: Double(point.x) * scaleX,
            pixelY: Double(point.y) * scaleY
        ) else {
            return nil
        }
        return VTGMouseSnapshot(
            x: position.pixelX,
            y: position.pixelY,
            cellX: position.gridCol + 1,
            cellY: position.gridRow + 1,
            modifiers: VTGMouseModifiers()
        )
    }
}
#endif
