import Foundation

/// Mouse-event response generation for `VTGHostController`.
extension VTGHostController {
    /// Return a VTG mouse response when the current mouse mode accepts `type`.
    public func mouseResponse(
        type: VTGMouseEventType,
        button: Int,
        snapshot: VTGMouseSnapshot,
        canvas: VTGCanvasSize? = nil,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) -> String? {
        _ = expirePendingFrameIfNeeded()
        guard sendsMouseEvents, acceptsMouseEvent(type: type) else {
            return nil
        }
        let point = VTGPoint(x: Double(snapshot.x), y: Double(snapshot.y))
        let viewportPosition = canvas.flatMap {
            scene.viewportMousePosition(at: point, canvasWidth: Double($0.width), canvasHeight: Double($0.height))
        }
        let hit = canvas.flatMap {
            scene.hitRegion(at: point, canvasWidth: Double($0.width), canvasHeight: Double($0.height))
        } ?? scene.hitRegion(at: point)
        return VTGResponseEncoder.mouse(
            VTGMouseEventPayload(
                type: type.rawValue,
                button: button,
                x: snapshot.x,
                y: snapshot.y,
                cellX: snapshot.cellX,
                cellY: snapshot.cellY,
                modifiers: snapshot.modifiers,
                scrollX: scrollX,
                scrollY: scrollY,
                hitID: hit?.id,
                targetID: hit?.target,
                viewportLayer: viewportPosition?.layer,
                virtualX: viewportPosition.map { Int($0.x.rounded(.down)) },
                virtualY: viewportPosition.map { Int($0.y.rounded(.down)) }
            )
        )
    }

    /// Return a VTG mouse response for callers that still pass raw event names.
    public func mouseResponse(
        type: String,
        button: Int,
        snapshot: VTGMouseSnapshot,
        canvas: VTGCanvasSize? = nil,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) -> String? {
        guard let type = VTGMouseEventType(rawValue: type) else {
            return nil
        }
        return mouseResponse(
            type: type,
            button: button,
            snapshot: snapshot,
            canvas: canvas,
            scrollX: scrollX,
            scrollY: scrollY
        )
    }

    private func acceptsMouseEvent(type: VTGMouseEventType) -> Bool {
        switch mouseMode {
        case .click:
            return type == .click
        case .raw:
            return type == .down || type == .up || type == .click || type == .scroll
        case .drag:
            return type == .down || type == .up || type == .drag || type == .click || type == .scroll
        case .all:
            return true
        }
    }
}
