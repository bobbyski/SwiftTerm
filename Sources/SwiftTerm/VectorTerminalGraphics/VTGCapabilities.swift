import Foundation

public extension VTGResponseEncoder {
    /// Wire protocol name used in capability discovery.
    static let protocolName = "VTG"

    /// Version of the VTG command protocol advertised to child processes.
    static let version = "0.1"

    /// Versioned shape of the `capabilities` response fields.
    ///
    /// The response is still a flat APC key/value list so older clients can
    /// continue to read individual fields. This schema identifier gives newer
    /// clients a stable way to decide whether fields such as `commands`,
    /// `planned`, and `events` are present.
    static let capabilitiesSchema = "vtg.capabilities.v1"

    static let defaultPrimitives = [
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

    static let defaultFormats = ["png", "jpeg", "indexed"]
    static let defaultRasterFeatures = ["image", "filter"]
    static let defaultSpriteFeatures = ["bitmap", "vector", "indexed", "move", "rotate", "scale", "filter"]
    static let defaultColors = ["hex-rgb", "hex-rgba"]
    static let defaultEvents = ["mouse", "resize", "frame"]

    static let defaultCommands = [
        "begin",
        "present",
        "clear",
        "delete",
        "capabilities?",
        "canvas?",
        "size?",
        "resizeEvents",
        "mouseEvents",
        "defaultLayer",
        "layer",
        "layerScroll",
        "layerAlpha",
        "viewportMode",
        "viewportScale",
        "clip",
        "clipClear",
        "hit",
        "hitClear",
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
        "startFrame",
        "endFrame",
        "cancelFrame",
        "spriteUpload",
        "vectorSpriteUpload",
        "spriteDataUpload",
        "sprite",
        "spriteMove",
        "spriteRotate",
        "spriteAnchor",
        "spriteTransform",
        "spriteRemove",
        "spriteClear"
    ]

    static let plannedCommands: [String] = []
}
