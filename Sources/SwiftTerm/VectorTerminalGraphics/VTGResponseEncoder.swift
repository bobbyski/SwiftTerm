import Foundation

/// Pixel dimensions of the VTG drawing canvas.
public struct VTGCanvasSize: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Mouse or pointer state encoded into a VTG mouse event.
public struct VTGMouseEventPayload: Equatable {
    public var type: String
    public var button: Int
    public var x: Int
    public var y: Int
    public var cellX: Int
    public var cellY: Int
    public var modifiers: String
    public var scrollX: Int?
    public var scrollY: Int?
    public var hitID: String?
    public var targetID: String?

    public init(
        type: String,
        button: Int,
        x: Int,
        y: Int,
        cellX: Int,
        cellY: Int,
        modifiers: String,
        scrollX: Int? = nil,
        scrollY: Int? = nil,
        hitID: String? = nil,
        targetID: String? = nil
    ) {
        self.type = type
        self.button = button
        self.x = x
        self.y = y
        self.cellX = cellX
        self.cellY = cellY
        self.modifiers = modifiers
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.hitID = hitID
        self.targetID = targetID
    }
}

/// Encodes host-to-client VectorTerminal Graphics APC responses.
///
/// This intentionally stays free of AppKit or process-writing code. SwiftTerm
/// owns the protocol strings; embedders still provide platform facts such as
/// canvas size, mouse position, and whether a child process is running.
public enum VTGResponseEncoder {
    public static let version = "0.1"

    public static let defaultPrimitives = [
        "pixel",
        "line",
        "draw",
        "curve",
        "triangle",
        "path",
        "rect",
        "circle",
        "ellipse",
        "text",
        "image",
        "sprite"
    ]

    public static let defaultFormats = ["png", "jpeg"]
    public static let defaultSpriteFeatures = ["bitmap", "move", "rotate", "scale"]
    public static let defaultColors = ["hex-rgb", "hex-rgba"]

    /// Encode a `VTG;capabilities?` response.
    public static func capabilities(
        canvas: VTGCanvasSize,
        renderer: String = "overlay",
        primitives: [String] = defaultPrimitives,
        formats: [String] = defaultFormats,
        spriteFeatures: [String] = defaultSpriteFeatures,
        colors: [String] = defaultColors
    ) -> String {
        apc(
            "capabilities",
            [
                ("version", version),
                ("renderer", renderer),
                ("canvasWidth", String(canvas.width)),
                ("canvasHeight", String(canvas.height)),
                ("primitives", primitives.joined(separator: "|")),
                ("formats", formats.joined(separator: "|")),
                ("sprites", spriteFeatures.joined(separator: "|")),
                ("layers", "0-4"),
                ("defaultLayer", "1"),
                ("layerScroll", "true"),
                ("clip", "layer-rect"),
                ("hit", "rect-layered"),
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
        fields.append(("mods", event.modifiers))
        if let hitID = event.hitID {
            fields.append(("hit", hitID))
        }
        if let targetID = event.targetID {
            fields.append(("target", targetID))
        }
        return apc("mouse", fields)
    }

    private static func apc(_ commandName: String, _ fields: [(String, String)]) -> String {
        let parameters = fields
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: ",")
        let suffix = parameters.isEmpty ? "" : ",\(parameters)"
        return "\u{1B}_VTG;\(commandName)\(suffix)\u{1B}\\"
    }
}
