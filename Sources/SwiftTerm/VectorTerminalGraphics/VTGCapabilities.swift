import Foundation

public extension VTGResponseEncoder {
    /// Wire protocol name used in capability discovery.
    static let protocolName = "VTG"

    /// Version of the VTG command protocol advertised to child processes.
    static let version = "1.5.2"

    /// Versioned shape of the `capabilities` response fields.
    ///
    /// The response is still a flat APC key/value list so older clients can
    /// continue to read individual fields. This schema identifier gives newer
    /// clients a stable way to decide whether fields such as `commands`,
    /// `planned`, and `events` are present.
    static let capabilitiesSchema = "vtg.capabilities.v1"

    static let defaultPrimitives = [
        "pixel",
        "clearRect",
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

    /// Primitives currently implemented by the native under-text Metal pass.
    ///
    /// This is intentionally narrower than `defaultPrimitives`. Overlay layers
    /// support the full retained primitive set, while layer `-1` only supports
    /// shapes that can be emitted by the Metal primitive helper today.
    static let defaultUnderTextPrimitives = [
        "pixel",
        "line",
        "draw",
        "curve",
        "triangle",
        "path",
        "rect",
        "circle",
        "ellipse"
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
        "graphicsVisible",
        "graphicsVisible?",
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
        "clearRect",
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
