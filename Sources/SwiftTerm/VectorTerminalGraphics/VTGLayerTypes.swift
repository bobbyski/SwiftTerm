import Foundation

/// Defines the VTG compositing layer contract shared by the parser, scene, and
/// host response encoder.
///
/// Layer -1 is the under-text graphics plane. Layer 0 is reserved for the
/// future true text/graphics plane where VTG primitives can mingle with
/// terminal cells. Layers 1 through 4 are overlay layers that render above the
/// terminal and may scroll independently for parallax-style effects.
public enum VTGLayerModel {
    /// Graphics plane rendered beneath terminal glyphs.
    public static let underTextLayer = -1

    /// Shared text/graphics plane reserved for true Phase 10 mingling.
    public static let textPlaneLayer = 0

    /// First overlay layer. This is the default for current VTG drawing.
    public static let firstOverlayLayer = 1

    /// Last supported overlay layer. Keep this intentionally small.
    public static let lastOverlayLayer = 4

    /// Default layer for commands that omit `layer=`.
    public static let defaultDrawingLayer = firstOverlayLayer

    /// All supported layer numbers.
    public static let supportedRange = underTextLayer...lastOverlayLayer

    /// Layers that can be independently scrolled in the current overlay model.
    public static let scrollableRange = firstOverlayLayer...lastOverlayLayer

    /// Human-readable range advertised through `VTG;capabilities?`.
    public static let advertisedRange = "\(underTextLayer)-\(lastOverlayLayer)"

    /// Clamp an arbitrary wire value into the supported VTG layer range.
    public static func clamped(_ value: Int) -> Int {
        min(supportedRange.upperBound, max(supportedRange.lowerBound, value))
    }

    /// Return whether the layer may currently receive an overlay scroll offset.
    public static func isScrollable(_ layer: Int) -> Bool {
        scrollableRange.contains(layer)
    }

    /// Return whether the layer belongs to the under-text plane, future shared
    /// text/graphics plane, or current overlay stack.
    public static func compositingPlane(for layer: Int) -> VTGCompositingPlane {
        switch layer {
        case underTextLayer:
            return .underText
        case textPlaneLayer:
            return .textPlane
        default:
            return .overlay
        }
    }
}

/// High-level VTG compositing buckets used by the retained scene.
///
/// This is intentionally smaller than the layer model. Layer `-1` is the
/// renderer-integrated under-text plane, layer `0` is the future text/graphics
/// mingling plane, and layers `1...4` are the overlay stack.
public enum VTGCompositingPlane: Equatable {
    case underText
    case textPlane
    case overlay
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
