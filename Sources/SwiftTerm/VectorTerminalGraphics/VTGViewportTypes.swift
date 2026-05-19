import Foundation

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
