import Foundation

/// Floating-point pixel dimensions for renderer planning.
///
/// `VTGCanvasSize` is intentionally integer based because it is used on the
/// wire. Renderers often know their backing size as floating-point view bounds,
/// so the render plan keeps that precision until a backend needs to quantize.
public struct VTGRenderCanvas: Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ canvas: VTGCanvasSize) {
        self.init(width: Double(canvas.width), height: Double(canvas.height))
    }
}

/// One resolved primitive plus the layer state a renderer needs to draw it.
///
/// This deliberately keeps scene traversal, layer order, clipping, alpha,
/// scrolling, and fixed-viewport state in one place. CoreGraphics, Metal, SVG,
/// and future renderers should consume this resolved shape rather than copying
/// layer math into every backend.
public struct VTGRenderPlanEntry: Equatable {
    public var primitive: VTGPrimitive
    public var layer: Int
    public var alpha: Double
    public var offset: VTGLayerOffset
    public var clip: VTGLayerClip?
    public var viewport: VTGViewportTransform?

    public init(
        primitive: VTGPrimitive,
        layer: Int,
        alpha: Double,
        offset: VTGLayerOffset,
        clip: VTGLayerClip?,
        viewport: VTGViewportTransform?
    ) {
        self.primitive = primitive
        self.layer = layer
        self.alpha = alpha
        self.offset = offset
        self.clip = clip
        self.viewport = viewport
    }
}

/// Renderer-neutral plan for drawing a committed VTG scene.
public struct VTGRenderPlan: Equatable {
    public var canvas: VTGRenderCanvas
    public var plane: VTGCompositingPlane?
    public var entries: [VTGRenderPlanEntry]

    public init(canvas: VTGRenderCanvas, plane: VTGCompositingPlane?, entries: [VTGRenderPlanEntry]) {
        self.canvas = canvas
        self.plane = plane
        self.entries = entries
    }
}

public extension VTGGraphicsScene {
    /// Build a renderer-neutral plan for the requested compositing plane.
    ///
    /// Passing `nil` includes every retained primitive. Passing `.underText`,
    /// `.textPlane`, or `.overlay` lets renderer hooks split layer -1, layer 0,
    /// and overlay layers while preserving identical ordering and layer-state
    /// resolution.
    func renderPlan(plane: VTGCompositingPlane? = nil, canvas: VTGRenderCanvas) -> VTGRenderPlan {
        let primitives = plane.map { renderPrimitives(in: $0) } ?? renderPrimitives
        let entries = primitives.map { primitive in
            let layer = self.layer(for: primitive)
            return VTGRenderPlanEntry(
                primitive: primitive,
                layer: layer,
                alpha: alpha(for: layer),
                offset: offset(for: layer),
                clip: clip(for: layer),
                viewport: viewportTransform(
                    for: layer,
                    canvasWidth: canvas.width,
                    canvasHeight: canvas.height
                )
            )
        }
        return VTGRenderPlan(canvas: canvas, plane: plane, entries: entries)
    }

    /// Convenience overload for callers that already have an integer wire
    /// canvas size.
    func renderPlan(plane: VTGCompositingPlane? = nil, canvas: VTGCanvasSize) -> VTGRenderPlan {
        renderPlan(plane: plane, canvas: VTGRenderCanvas(canvas))
    }
}
