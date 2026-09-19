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
    public func draw(page: VTGPage, in context: CGContext, bounds: CGRect) {
        let viewportRect = page.viewport.map {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        } ?? bounds
        let pageOrigin = CGPoint(x: viewportRect.minX - page.scrollX, y: viewportRect.minY - page.scrollY)
        let pageRect = CGRect(origin: pageOrigin, size: CGSize(width: page.width, height: page.height))
        let visiblePage = pageRect.intersection(viewportRect)
        guard !viewportRect.isEmpty else {
            return
        }

        context.saveGState()
        context.clip(to: viewportRect)
        let fadesPage = page.alpha < 1
        if fadesPage {
            context.setAlpha(page.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        if let background = page.background, !visiblePage.isEmpty {
            context.setFillColor(background.cgColor)
            context.fill(visiblePage)
        }

        let layerCanvas = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        drawPass &+= 1
        lastCacheHits = 0
        lastCacheMisses = 0
        for layer in page.orderedLayers where layer.isVisible && layer.alpha > 0 {
            context.saveGState()
            switch layer.scrollMode {
            case .page:
                // Content beyond a fixed axis is clipped at the page edge.
                guard !visiblePage.isEmpty else {
                    context.restoreGState()
                    continue
                }
                context.clip(to: visiblePage)
                context.translateBy(x: pageOrigin.x + layer.offset.x, y: pageOrigin.y + layer.offset.y)
            case .fixed:
                context.translateBy(x: viewportRect.minX + layer.offset.x, y: viewportRect.minY + layer.offset.y)
            }
            let fadesLayer = layer.alpha < 1
            if fadesLayer {
                context.setAlpha(layer.alpha)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            if (layer.cacheHint || layer.isReadOnly),
               let cached = cachedImage(for: layer.scene, size: layerCanvas.size, like: context) {
                // The image was rendered top-left-origin; undo the flip. It
                // may be larger than this page — the page clip trims it.
                let rect = CGRect(origin: .zero, size: cached.size)
                context.translateBy(x: 0, y: rect.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(cached.image, in: rect)
            } else {
                painter.draw(scene: layer.scene, plane: nil, in: context, bounds: layerCanvas)
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

    /// Keep the rasters this pass used, then the most recently used of the
    /// rest, up to the advertised limit. A page that is no longer shown keeps
    /// its raster for a while: the other buffer is about to want it back.
    private func evictStaleCaches() {
        layerCaches = layerCaches.filter { $0.value.scene != nil }
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
