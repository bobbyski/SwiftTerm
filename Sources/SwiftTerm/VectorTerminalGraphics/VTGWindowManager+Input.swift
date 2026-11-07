import Foundation

/// Pointer input for VTG windows (WINDOW_PLAN.md 3.6).
///
/// Keys need no routing: every window shares the program's one input, and the
/// program set the focus itself, so it knows which window a key is for. The
/// pointer is different — only the terminal knows which window is under it.
extension VTGWindowManager {
    /// Offer a mouse event at a root canvas point to the topmost window under it.
    ///
    /// - Returns: True when the point is over a window. The root must then not
    ///   see the event, whether or not the window's program subscribed: a
    ///   window hides what is below it from the pointer as it does from the eye.
    @discardableResult
    public func handleMouse(type: VTGMouseEventType,
                            button: Int,
                            at point: VTGPoint,
                            modifiers: String,
                            scrollX: Int? = nil,
                            scrollY: Int? = nil) -> Bool {
        // A drag or release while a button is held goes to the window the
        // press began in, wherever the pointer is now.
        if type == .drag || type == .up, let capture = mouseCapture {
            if type == .up {
                mouseCapture = nil
            }
            if let window = windows[capture.id] {
                return deliverMouse(to: window, framePart: capture.framePart, type: type, button: button,
                                    at: point, modifiers: modifiers, scrollX: scrollX, scrollY: scrollY)
            }
        }
        guard let hit = window(at: point) else {
            return false
        }
        var framePart: String?
        if hit.contentPoint == nil {
            let cell = cellSize()
            let layout = hit.window.frame.layout(cellWidth: cell.width, cellHeight: cell.height)
            framePart = layout.titleBar.map { Self.contains($0, point) } == true ? "title" : "border"
        }
        if type == .down {
            mouseCapture = (hit.window.id, framePart)
        }
        return deliverMouse(to: hit.window, framePart: framePart, type: type, button: button,
                            at: point, modifiers: modifiers, scrollX: scrollX, scrollY: scrollY)
    }

    private func deliverMouse(to window: VTGWindow, framePart: String?, type: VTGMouseEventType, button: Int,
                              at point: VTGPoint, modifiers: String, scrollX: Int?, scrollY: Int?) -> Bool {
        let cell = cellSize()
        let layout = window.frame.layout(cellWidth: cell.width, cellHeight: cell.height)
        // On the border or title bar: the window's, not its content's. A
        // program that asked (`windowEvents`) hears about it, in main-canvas
        // points, so it can drag or raise the window.
        if let framePart {
            if reportsFrameEvents {
                sendVTG("windowMouse", [("id", window.id),
                                        ("part", framePart),
                                        ("type", type.rawValue),
                                        ("button", String(button)),
                                        ("x", String(Int(point.x.rounded(.down)))),
                                        ("y", String(Int(point.y.rounded(.down)))),
                                        ("modifiers", modifiers)])
            }
            return true
        }
        let local = VTGPoint(x: point.x - layout.content.x, y: point.y - layout.content.y)
        let snapshot = VTGMouseSnapshot(
            x: Int(local.x.rounded(.down)),
            y: Int(local.y.rounded(.down)),
            cellX: Int(local.x / max(1, cell.width)) + 1,
            cellY: Int(local.y / max(1, cell.height)) + 1,
            modifiers: modifiers
        )
        window.surface.session.sendMouseEvent(type: type, button: button, snapshot: snapshot,
                                              scrollX: scrollX, scrollY: scrollY)
        return true
    }
}
