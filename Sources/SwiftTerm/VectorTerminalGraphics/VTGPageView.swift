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
            painter.draw(scene: layer.scene, plane: nil, in: context, bounds: layerCanvas)
            if fadesLayer {
                context.endTransparencyLayer()
            }
            context.restoreGState()
        }

        if fadesPage {
            context.endTransparencyLayer()
        }
        context.restoreGState()
    }
}
#endif
