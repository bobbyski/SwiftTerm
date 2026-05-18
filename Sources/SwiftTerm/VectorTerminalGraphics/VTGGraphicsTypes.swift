import Foundation


/// Defines the VTG compositing layer contract shared by the parser, scene, and
/// host response encoder.
///
/// Layer 0 is reserved for the future text/graphics plane where VTG primitives
/// can mingle with terminal cells. Layers 1 through 4 are overlay layers that
/// render above the terminal and may scroll independently for parallax-style
/// effects.
public enum VTGLayerModel {
    /// Shared text/graphics plane reserved for Phase 10 renderer integration.
    public static let textPlaneLayer = 0

    /// First overlay layer. This is the default for current VTG drawing.
    public static let firstOverlayLayer = 1

    /// Last supported overlay layer. Keep this intentionally small.
    public static let lastOverlayLayer = 4

    /// Default layer for commands that omit `layer=`.
    public static let defaultDrawingLayer = firstOverlayLayer

    /// All supported layer numbers.
    public static let supportedRange = textPlaneLayer...lastOverlayLayer

    /// Layers that can be independently scrolled in the current overlay model.
    public static let scrollableRange = firstOverlayLayer...lastOverlayLayer

    /// Human-readable range advertised through `VTG;capabilities?`.
    public static let advertisedRange = "\(textPlaneLayer)-\(lastOverlayLayer)"

    /// Clamp an arbitrary wire value into the supported VTG layer range.
    public static func clamped(_ value: Int) -> Int {
        min(supportedRange.upperBound, max(supportedRange.lowerBound, value))
    }

    /// Return whether the layer may currently receive an overlay scroll offset.
    public static func isScrollable(_ layer: Int) -> Bool {
        scrollableRange.contains(layer)
    }
}

/// A retained drawing primitive in the VectorTerminal overlay scene.
///
/// Each primitive has an ID so apps can redraw by replacing existing shapes
/// instead of clearing and repainting the entire canvas every frame.
public enum VTGPrimitive: Equatable {
    case pixel(id: String, x: Double, y: Double, color: VTGColor)
    case line(id: String, x1: Double, y1: Double, x2: Double, y2: Double, stroke: VTGColor, width: Double)
    case draw(id: String, points: [VTGPoint], stroke: VTGColor, width: Double)
    case curve(id: String, curve: VTGCurve, stroke: VTGColor, width: Double)
    case triangle(id: String, p1: VTGPoint, p2: VTGPoint, p3: VTGPoint, radius: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case path(id: String, commands: [VTGPathCommand], stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case rect(id: String, x: Double, y: Double, width: Double, height: Double, radius: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case circle(id: String, cx: Double, cy: Double, radius: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case ellipse(id: String, cx: Double, cy: Double, rx: Double, ry: Double, stroke: VTGColor?, fill: VTGColor?, lineWidth: Double)
    case text(id: String, x: Double, y: Double, value: String, color: VTGColor, size: Double)
    case image(id: String, x: Double, y: Double, width: Double, height: Double, format: String, data: Data, base64: String)
    case sprite(id: String, assetID: String, x: Double, y: Double, rotation: Double, scale: Double, anchorX: Double, anchorY: Double)

    public var id: String {
        switch self {
        case .pixel(let id, _, _, _),
             .line(let id, _, _, _, _, _, _),
             .draw(let id, _, _, _),
             .curve(let id, _, _, _),
             .triangle(let id, _, _, _, _, _, _, _),
             .path(let id, _, _, _, _),
             .rect(let id, _, _, _, _, _, _, _, _),
             .circle(let id, _, _, _, _, _, _),
             .ellipse(let id, _, _, _, _, _, _, _),
             .text(let id, _, _, _, _, _),
             .image(let id, _, _, _, _, _, _, _),
             .sprite(let id, _, _, _, _, _, _, _):
            return id
        }
    }
}

/// Uploaded bitmap payload that sprite instances can reference cheaply.
public struct VTGSpriteAsset: Equatable {
    public var id: String
    public var format: String
    public var width: Double
    public var height: Double
    public var data: Data
    public var base64: String

    public init(id: String, format: String, width: Double, height: Double, data: Data, base64: String) {
        self.id = id
        self.format = format
        self.width = width
        self.height = height
        self.data = data
        self.base64 = base64
    }
}

/// Uploaded vector payload that sprite instances can reference cheaply.
///
/// The first pass supports one constrained VTG path per asset. That keeps
/// transforms limited to tracked sprite resources while giving small games and
/// demos lightweight vector ships, cursors, and icons.
public struct VTGVectorSpriteAsset: Equatable {
    public var id: String
    public var width: Double
    public var height: Double
    public var commands: [VTGPathCommand]
    public var stroke: VTGColor?
    public var fill: VTGColor?
    public var lineWidth: Double
    public var payload: String

    public init(id: String, width: Double, height: Double, commands: [VTGPathCommand], stroke: VTGColor?, fill: VTGColor?, lineWidth: Double, payload: String) {
        self.id = id
        self.width = width
        self.height = height
        self.commands = commands
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
        self.payload = payload
    }
}

/// Pixel-space point used by multi-segment VTG draw commands.
public struct VTGPoint: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Pixel-space scroll offset for a VTG graphics layer.
public struct VTGLayerOffset: Equatable {
    public var x: Double
    public var y: Double

    public static let zero = VTGLayerOffset(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Rectangular clip bounds for a VTG graphics layer.
public struct VTGLayerClip: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Fixed-resolution compatibility mode for an overlay graphics layer.
///
/// This is intentionally restricted to overlay layers. Layer 0 contains normal
/// terminal text and scrollback, so scaling it as a virtual pixel surface would
/// make selection, cursor movement, and ANSI layout surprising.
public struct VTGViewportMode: Equatable {
    public enum ScaleMode: String {
        case fit
        case fill
        case integer
        case stretch
    }

    public var layer: Int
    public var width: Double
    public var height: Double
    public var scaleMode: ScaleMode

    public init(layer: Int, width: Double, height: Double, scaleMode: ScaleMode) {
        self.layer = layer
        self.width = width
        self.height = height
        self.scaleMode = scaleMode
    }
}

/// Explicit placement override for a fixed-resolution overlay layer.
public struct VTGViewportScale: Equatable {
    public var layer: Int
    public var scale: Double
    public var x: Double
    public var y: Double

    public init(layer: Int, scale: Double, x: Double, y: Double) {
        self.layer = layer
        self.scale = scale
        self.x = x
        self.y = y
    }
}

/// Concrete renderer transform for drawing one layer's virtual coordinates.
public struct VTGViewportTransform: Equatable {
    public var x: Double
    public var y: Double
    public var scaleX: Double
    public var scaleY: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, scaleX: Double, scaleY: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.width = width
        self.height = height
    }
}

/// Mouse point mapped from live canvas pixels into a fixed viewport layer.
public struct VTGViewportMousePosition: Equatable {
    public var layer: Int
    public var x: Double
    public var y: Double

    public init(layer: Int, x: Double, y: Double) {
        self.layer = layer
        self.x = x
        self.y = y
    }
}

/// Rectangular interactive region registered by a child app.
public struct VTGHitRegion: Equatable {
    public var id: String
    public var target: String?
    public var layer: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var order: Int

    public init(id: String, target: String?, layer: Int, x: Double, y: Double, width: Double, height: Double, order: Int) {
        self.id = id
        self.target = target
        self.layer = layer
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.order = order
    }
}

/// Bezier curve retained by the VTG scene.
public enum VTGCurve: Equatable {
    case quadratic(start: VTGPoint, control: VTGPoint, end: VTGPoint)
    case cubic(start: VTGPoint, control1: VTGPoint, control2: VTGPoint, end: VTGPoint)
}

/// Constrained SVG-like path commands supported by VTG phase 2.
public enum VTGPathCommand: Equatable {
    case move(to: VTGPoint)
    case line(to: VTGPoint)
    case quadratic(control: VTGPoint, end: VTGPoint)
    case cubic(control1: VTGPoint, control2: VTGPoint, end: VTGPoint)
    case close
}

/// RGBA color normalized for AppKit/SwiftUI drawing.
public struct VTGColor: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public static let foreground = VTGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
