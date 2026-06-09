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
        underTextPrimitives: [String] = defaultUnderTextPrimitives,
        formats: [String] = defaultFormats,
        rasterFeatures: [String] = defaultRasterFeatures,
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
                ("underText", underTextPrimitives.joined(separator: "|")),
                ("formats", formats.joined(separator: "|")),
                ("raster", rasterFeatures.joined(separator: "|")),
                ("sprites", spriteFeatures.joined(separator: "|")),
                ("layers", VTGLayerModel.advertisedRange),
                ("defaultLayer", String(VTGLayerModel.defaultDrawingLayer)),
                ("textPlane", "reserved"),
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

    static func apc(_ commandName: String, _ fields: [(String, String)]) -> String {
        let parameters = fields
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: ",")
        let suffix = parameters.isEmpty ? "" : ",\(parameters)"
        return "\u{1B}_VTG;\(commandName)\(suffix)\u{1B}\\"
    }
}
