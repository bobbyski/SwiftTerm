import Foundation

extension VTGResponseEncoder {
    /// Encode a native VTG mouse, click, drag, or scroll event.
    public static func mouse(_ event: VTGMouseEventPayload) -> String {
        var fields: [(String, String)] = [
            ("type", event.type),
            ("button", String(event.button)),
            ("x", String(event.x)),
            ("y", String(event.y)),
            ("cellX", String(event.cellX)),
            ("cellY", String(event.cellY))
        ]
        if let scrollX = event.scrollX {
            fields.append(("scrollX", String(scrollX)))
        }
        if let scrollY = event.scrollY {
            fields.append(("scrollY", String(scrollY)))
        }
        if let viewportLayer = event.viewportLayer,
           let virtualX = event.virtualX,
           let virtualY = event.virtualY {
            fields.append(("viewportLayer", String(viewportLayer)))
            fields.append(("virtualX", String(virtualX)))
            fields.append(("virtualY", String(virtualY)))
        }
        fields.append(("mods", event.modifiers))
        if let hitID = event.hitID {
            fields.append(("hit", hitID))
        }
        if let targetID = event.targetID {
            fields.append(("target", targetID))
        }
        return apc("mouse", fields)
    }

    /// Encode a graphics-frame lifecycle response.
    public static func frameEvent(
        _ commandName: String,
        id: String,
        reason: String? = nil,
        timeoutMilliseconds: Int? = nil
    ) -> String {
        var fields = [("id", id)]
        if let reason {
            fields.append(("reason", reason))
        }
        if let timeoutMilliseconds {
            fields.append(("timeout", String(timeoutMilliseconds)))
        }
        return apc(commandName, fields)
    }
}
