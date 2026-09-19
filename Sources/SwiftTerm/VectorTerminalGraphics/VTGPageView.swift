#if os(macOS)
import AppKit

/// Transparent AppKit view that composites the visible VTG Page Mode page.
///
/// It sits above the VTG overlay (or between the terminal text and the
/// overlay, for `pageBegin,over=text`) and draws the page's scrolled window:
/// background, then each visible layer by z, clipped to the page's extent and
/// its viewport. Like the overlay, it never takes mouse hits — input reaches
/// the terminal view, which reports page coordinates in VTG mouse events.
public final class VTGPageView: NSView {
    /// The page to draw, or `nil` for nothing.
    public var page: VTGPage? {
        didSet {
            needsDisplay = true
        }
    }

    /// Reuses the overlay's primitive drawing so a page renders every VTG
    /// primitive exactly as the base scene does. Never added to a window.
    private let painter = VTGOverlayView(frame: .zero)

    /// Rasterized layers, keyed by the scene they show.
    ///
    /// A layer marked `cache=1`, or borrowed from the other page by
    /// reference, is drawn once and reused until its scene's revision moves.
    /// Keyed by scene, so a background shared by both pages is rasterized
    /// once for both — the point of sharing it.
    private struct LayerCache {
        weak var scene: VTGGraphicsScene?
        var revision: UInt64
        var size: CGSize
        var image: CGLayer
        /// Draw pass this raster was last used in, for eviction.
        var lastUsed: UInt64
    }
    private var layerCaches: [ObjectIdentifier: LayerCache] = [:]
    private var drawPass: UInt64 = 0

    /// What each layer cost to draw directly, the last time it was, and at
    /// which revision. A layer is only worth rasterizing if drawing it costs
    /// more than blitting it.
    private struct LayerCost {
        var seconds: Double
        var revision: UInt64
    }
    private var layerCosts: [ObjectIdentifier: LayerCost] = [:]

    /// Above this, a layer marked `cache=1` (or borrowed) is rasterized.
    ///
    /// Measured on a 1200x800 view: a background of 400 circles draws in
    /// ~1.3 ms and blits in ~2.3 ms, so caching it would cost time; at 4000
    /// circles it draws in ~13 ms and blits in ~6.7 ms, so caching halves it.
    /// The crossover is near a millisecond of drawing, and it is measured per
    /// layer rather than guessed from what the layer contains.
    public static var rasterizeAboveSeconds = 0.0015

    /// Pages larger than this are drawn directly rather than cached, so a
    /// long growable document does not become a giant bitmap. Reported to
    /// applications through `pageLimits?`.
    public static let maximumCachedArea = CGFloat(VTGPageCacheLimits.maximumArea)

    /// Rasters kept at once. Reported through `pageLimits?`.
    public static let maximumCachedLayers = VTGPageCacheLimits.maximumLayers

    /// How many layers were drawn from the cache in the last pass, and how
    /// many had to be rasterized. For tests and diagnostics.
    public private(set) var lastCacheHits = 0
    public private(set) var lastCacheMisses = 0

    public override var isFlipped: Bool {
        true
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let page else {
            return
        }
        draw(page: page, in: context, bounds: bounds)
    }

    /// Draw a page into a top-left-origin context whose bounds are the
    /// terminal canvas.
    ///
    /// Where the page sits, what it clips to, and how its layers are placed
    /// all come from ``VTGPage/renderPlan(canvas:)``, the same resolution the
    /// GL host draws from.
    public func draw(page: VTGPage, in context: CGContext, bounds: CGRect) {
        let plan = page.renderPlan(canvas: VTGRenderCanvas(width: bounds.width, height: bounds.height))
        let viewportRect = rect(plan.viewport)
        guard !viewportRect.isEmpty else {
            return
        }
        drawPass &+= 1
        lastCacheHits = 0
        lastCacheMisses = 0

        context.saveGState()
        context.clip(to: viewportRect)
        let fadesPage = plan.alpha < 1
        if fadesPage {
            context.setAlpha(plan.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        if let background = plan.background, let visible = plan.visibleRect {
            context.setFillColor(background.cgColor)
            context.fill(rect(visible))
        }

        let layerCanvas = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        for layerPlan in plan.layers {
            context.saveGState()
            if let clip = layerPlan.clip {
                context.clip(to: rect(clip))
            }
            context.translateBy(x: CGFloat(layerPlan.offset.x), y: CGFloat(layerPlan.offset.y))
            // The page's own alpha is applied once, around everything.
            let layerAlpha = fadesPage ? layerPlan.alpha / plan.alpha : layerPlan.alpha
            let fadesLayer = layerAlpha < 1
            if fadesLayer {
                context.setAlpha(layerAlpha)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            if layerPlan.isCacheable,
               isWorthRasterizing(layerPlan.scene),
               let cached = cachedImage(for: layerPlan.scene, size: layerCanvas.size, like: context) {
                // The image was rendered top-left-origin; undo the flip. It
                // may be larger than this page — the page clip trims it.
                let imageRect = CGRect(origin: .zero, size: cached.size)
                context.translateBy(x: 0, y: imageRect.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(cached.image, in: imageRect)
            } else {
                let start = Date()
                painter.draw(scene: layerPlan.scene, plane: nil, in: context, bounds: layerCanvas)
                layerCosts[ObjectIdentifier(layerPlan.scene)] = LayerCost(
                    seconds: Date().timeIntervalSince(start),
                    revision: layerPlan.scene.revision
                )
            }
            if fadesLayer {
                context.endTransparencyLayer()
            }
            context.restoreGState()
        }

        if fadesPage {
            context.endTransparencyLayer()
        }
        context.restoreGState()
        evictStaleCaches()
    }

    private func rect(_ clip: VTGLayerClip) -> CGRect {
        CGRect(x: clip.x, y: clip.y, width: clip.width, height: clip.height)
    }

    /// Whether this layer costs more to draw than to blit. A layer whose
    /// content has changed is drawn once more before deciding again.
    private func isWorthRasterizing(_ scene: VTGGraphicsScene) -> Bool {
        guard let cost = layerCosts[ObjectIdentifier(scene)], cost.revision == scene.revision else {
            return false
        }
        return cost.seconds > Self.rasterizeAboveSeconds
    }

    /// Keep the rasters this pass used, then the most recently used of the
    /// rest, up to the advertised limit. A page that is no longer shown keeps
    /// its raster for a while: the other buffer is about to want it back.
    private func evictStaleCaches() {
        layerCaches = layerCaches.filter { $0.value.scene != nil }
        layerCosts = layerCosts.filter { key, _ in
            layerCaches[key] != nil || layerCosts.count <= Self.maximumCachedLayers * 4
        }
        guard layerCaches.count > Self.maximumCachedLayers else {
            return
        }
        let keep = layerCaches
            .sorted { $0.value.lastUsed > $1.value.lastUsed }
            .prefix(Self.maximumCachedLayers)
            .map(\.key)
        layerCaches = layerCaches.filter { keep.contains($0.key) }
    }

    /// The layer's rasterized scene, re-rendered only when the scene changed
    /// or the page needs more of it than the raster holds.
    ///
    /// Two pages sharing a background are rarely exactly the same size — one
    /// grows by half a pixel to fit a stroke — so any raster that covers the
    /// requested area is reused, and a new one is made as large as both.
    private func cachedImage(
        for scene: VTGGraphicsScene,
        size requested: CGSize,
        like context: CGContext
    ) -> (image: CGLayer, size: CGSize)? {
        guard requested.width > 0, requested.height > 0 else {
            return nil
        }
        let key = ObjectIdentifier(scene)
        var size = CGSize(width: ceil(requested.width), height: ceil(requested.height))
        if let cached = layerCaches[key], cached.scene === scene {
            if cached.revision == scene.revision,
               cached.size.width >= requested.width,
               cached.size.height >= requested.height {
                layerCaches[key]?.lastUsed = drawPass
                lastCacheHits += 1
                return (cached.image, cached.size)
            }
            size = CGSize(width: max(size.width, cached.size.width), height: max(size.height, cached.size.height))
        }
        guard size.width * size.height <= Self.maximumCachedArea else {
            return nil
        }
        guard let image = CGLayer(context, size: size, auxiliaryInfo: nil),
              let imageContext = image.context else {
            return nil
        }
        // Render top-left-origin, as the rest of VTG draws.
        imageContext.translateBy(x: 0, y: size.height)
        imageContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: imageContext, flipped: true)
        painter.draw(scene: scene, plane: nil, in: imageContext, bounds: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        layerCaches[key] = LayerCache(
            scene: scene,
            revision: scene.revision,
            size: size,
            image: image,
            lastUsed: drawPass
        )
        lastCacheMisses += 1
        return (image, size)
    }
}
#endif
