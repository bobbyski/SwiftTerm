import Foundation

/// One page layer, resolved for drawing.
///
/// `plan` is an ordinary ``VTGRenderPlan`` whose entries already carry the
/// page's scroll, the layer's offset, and the clip that keeps the layer inside
/// the page and its viewport — all in canvas coordinates. A backend that can
/// already draw a render plan can draw a page without knowing what a page is.
public struct VTGPageLayerPlan {
    public var layerID: String
    /// The layer's scene, which identifies it for a renderer that caches
    /// rasters: two pages sharing a borrowed layer share this object.
    public var scene: VTGGraphicsScene
    /// Whether the layer asked to be rasterized, or is borrowed (and so
    /// cannot change from this page).
    public var isCacheable: Bool
    /// Where the layer's origin sits in canvas coordinates.
    public var offset: VTGLayerOffset
    /// The region the layer is confined to, in canvas coordinates.
    public var clip: VTGLayerClip?
    /// The page's alpha times the layer's.
    public var alpha: Double
    public var plan: VTGRenderPlan
}

/// A page resolved for drawing: where it sits, what shows through, and its
/// layers in drawing order.
public struct VTGPagePlan {
    public var pageID: String
    /// The page's window on the canvas.
    public var viewport: VTGLayerClip
    /// Where the page itself lands, in canvas coordinates — the part of the
    /// viewport the page actually covers. `nil` when it is scrolled out.
    public var visibleRect: VTGLayerClip?
    public var background: VTGColor?
    public var alpha: Double
    public var layers: [VTGPageLayerPlan]
    /// The background as a plan of its own, for backends that would rather
    /// draw everything through one path.
    public var backgroundPlan: VTGRenderPlan?
}

public extension VTGPage {
    /// Resolve this page for a canvas: viewport, scroll, layer offsets,
    /// clipping, and alpha, once, for every renderer.
    func renderPlan(canvas: VTGRenderCanvas) -> VTGPagePlan {
        let viewport = self.viewport ?? VTGLayerClip(x: 0, y: 0, width: canvas.width, height: canvas.height)
        let origin = VTGLayerOffset(x: viewport.x - scrollX, y: viewport.y - scrollY)
        // The page's own rectangle, clipped to its window on the canvas.
        let minX = max(viewport.x, origin.x)
        let minY = max(viewport.y, origin.y)
        let maxX = min(viewport.x + viewport.width, origin.x + width)
        let maxY = min(viewport.y + viewport.height, origin.y + height)
        let visibleRect: VTGLayerClip? = (maxX > minX && maxY > minY)
            ? VTGLayerClip(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            : nil

        var layerPlans: [VTGPageLayerPlan] = []
        for layer in orderedLayers where layer.isVisible && layer.alpha > 0 {
            let layerOrigin: VTGLayerOffset
            let clip: VTGLayerClip?
            switch layer.scrollMode {
            case .page:
                guard let visibleRect else {
                    continue
                }
                layerOrigin = VTGLayerOffset(x: origin.x + layer.offset.x, y: origin.y + layer.offset.y)
                clip = visibleRect
            case .fixed:
                // Pinned to the window: unmoved by scrolling, and clipped to
                // the viewport rather than to the page.
                layerOrigin = VTGLayerOffset(x: viewport.x + layer.offset.x, y: viewport.y + layer.offset.y)
                clip = viewport
            }
            let alpha = self.alpha * layer.alpha
            let scenePlan = layer.scene.renderPlan(canvas: VTGRenderCanvas(width: width, height: height))
            let entries = scenePlan.entries.map { entry -> VTGRenderPlanEntry in
                var resolved = entry
                resolved.alpha = entry.alpha * alpha
                resolved.offset = VTGLayerOffset(
                    x: entry.offset.x + layerOrigin.x,
                    y: entry.offset.y + layerOrigin.y
                )
                // Clips travel with the offset, so they are expressed
                // relative to it, as they are for ordinary layers.
                let pageClip = clip.map { region in
                    VTGLayerClip(
                        x: region.x - resolved.offset.x,
                        y: region.y - resolved.offset.y,
                        width: region.width,
                        height: region.height
                    )
                }
                resolved.clip = entry.clip.flatMap { own in
                    pageClip.map { Self.intersection(own, $0) } ?? own
                } ?? pageClip
                return resolved
            }
            layerPlans.append(VTGPageLayerPlan(
                layerID: layer.id,
                scene: layer.scene,
                isCacheable: layer.cacheHint || layer.isReadOnly,
                offset: layerOrigin,
                clip: clip,
                alpha: alpha,
                plan: VTGRenderPlan(canvas: canvas, plane: nil, entries: entries)
            ))
        }

        var backgroundPlan: VTGRenderPlan?
        if let background, let visibleRect {
            let rectangle = VTGPrimitive.rect(
                id: "vtg-page-background",
                x: visibleRect.x,
                y: visibleRect.y,
                width: visibleRect.width,
                height: visibleRect.height,
                radius: 0,
                corners: nil,
                stroke: nil,
                fill: background,
                lineWidth: 0,
                lineJoin: nil
            )
            backgroundPlan = VTGRenderPlan(
                canvas: canvas,
                plane: nil,
                entries: [VTGRenderPlanEntry(
                    primitive: rectangle,
                    layer: VTGLayerModel.firstOverlayLayer,
                    alpha: alpha,
                    offset: .zero,
                    clip: nil,
                    viewport: nil
                )]
            )
        }

        return VTGPagePlan(
            pageID: id,
            viewport: viewport,
            visibleRect: visibleRect,
            background: background,
            alpha: alpha,
            layers: layerPlans,
            backgroundPlan: backgroundPlan
        )
    }

    private static func intersection(_ a: VTGLayerClip, _ b: VTGLayerClip) -> VTGLayerClip {
        let minX = max(a.x, b.x)
        let minY = max(a.y, b.y)
        let maxX = min(a.x + a.width, b.x + b.width)
        let maxY = min(a.y + a.height, b.y + b.height)
        return VTGLayerClip(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
