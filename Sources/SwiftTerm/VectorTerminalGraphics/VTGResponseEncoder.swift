import Foundation

/// Encodes host-to-client VectorTerminal Graphics APC responses.
///
/// This intentionally stays free of AppKit or process-writing code. SwiftTerm
/// owns the protocol strings; embedders still provide platform facts such as
/// canvas size, mouse position, and whether a child process is running.
public enum VTGResponseEncoder {
    /// Encode a `VTG;capabilities?` response.
    public static func capabilities(
        canvas: VTGCanvasSize,
        renderer: String = "overlay",
        primitives: [String] = defaultPrimitives,
        formats: [String] = defaultFormats,
        spriteFeatures: [String] = defaultSpriteFeatures,
        colors: [String] = defaultColors,
        commands: [String] = defaultCommands,
        planned: [String] = plannedCommands,
        events: [String] = defaultEvents
    ) -> String {
        apc(
            "capabilities",
            [
                ("protocol", protocolName),
                ("schema", capabilitiesSchema),
                ("version", version),
                ("renderer", renderer),
                ("canvasWidth", String(canvas.width)),
                ("canvasHeight", String(canvas.height)),
                ("commands", commands.joined(separator: "|")),
                ("planned", planned.joined(separator: "|")),
                ("primitives", primitives.joined(separator: "|")),
                ("formats", formats.joined(separator: "|")),
                ("sprites", spriteFeatures.joined(separator: "|")),
                ("layers", VTGLayerModel.advertisedRange),
                ("defaultLayer", String(VTGLayerModel.defaultDrawingLayer)),
                ("layerScroll", "true"),
                ("layerAlpha", "1-4"),
                ("clip", "layer-rect"),
                ("hit", "rect-layered"),
                ("events", events.joined(separator: "|")),
                ("colors", colors.joined(separator: "|"))
            ]
        )
    }

    /// Encode `VTG;canvas?` or `VTG;size?` responses.
    public static func canvasResponse(commandName: String, canvas: VTGCanvasSize) -> String {
        apc(commandName, [("width", String(canvas.width)), ("height", String(canvas.height))])
    }

    /// Encode a resize event for clients subscribed through `resizeEvents`.
    public static func resize(canvas: VTGCanvasSize) -> String {
        canvasResponse(commandName: "resize", canvas: canvas)
    }

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

    private static func apc(_ commandName: String, _ fields: [(String, String)]) -> String {
        let parameters = fields
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: ",")
        let suffix = parameters.isEmpty ? "" : ",\(parameters)"
        return "\u{1B}_VTG;\(commandName)\(suffix)\u{1B}\\"
    }
}
