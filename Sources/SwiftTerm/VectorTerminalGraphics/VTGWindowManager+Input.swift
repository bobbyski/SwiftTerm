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
        guard let hit = window(at: point) else {
            return false
        }
        // On the border or title bar: the window's, not its content's. A
        // program that asked (`windowEvents`) hears about it, in main-canvas
        // points, so it can drag or raise the window.
        guard let local = hit.contentPoint else {
            if reportsFrameEvents {
                let cell = cellSize()
                let layout = hit.window.frame.layout(cellWidth: cell.width, cellHeight: cell.height)
                let onTitle = layout.titleBar.map { Self.contains($0, point) } ?? false
                sendVTG("windowMouse", [("id", hit.window.id),
                                        ("part", onTitle ? "title" : "border"),
                                        ("type", type.rawValue),
                                        ("button", String(button)),
                                        ("x", String(Int(point.x.rounded(.down)))),
                                        ("y", String(Int(point.y.rounded(.down)))),
                                        ("modifiers", modifiers)])
            }
            return true
        }
        let cell = cellSize()
        let snapshot = VTGMouseSnapshot(
            x: Int(local.x.rounded(.down)),
            y: Int(local.y.rounded(.down)),
            cellX: Int(local.x / max(1, cell.width)) + 1,
            cellY: Int(local.y / max(1, cell.height)) + 1,
            modifiers: modifiers
        )
        hit.window.surface.session.sendMouseEvent(type: type, button: button, snapshot: snapshot,
                                                  scrollX: scrollX, scrollY: scrollY)
        return true
    }
}
