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
