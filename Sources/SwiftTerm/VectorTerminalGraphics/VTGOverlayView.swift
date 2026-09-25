#if os(macOS) || os(iOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Transparent overlay view that renders retained VTG primitives.
public final class VTGOverlayView: VTGPlatformView {
    /// The locked screen's size in VTG pixels, when a program locked one.
    ///
    /// Drawing then happens in those pixels and is scaled up to the view — a
    /// 320×200 screen in a 960×600 view draws at ×3, every pixel a 3×3 block.
    public var lockedCanvas: VTGCanvasSize? {
        didSet {
            guard lockedCanvas != oldValue else { return }
            vtgSetNeedsDisplay()
        }
    }

    /// Current retained VTG scene to draw.
    public var scene: VTGGraphicsScene? {
        didSet {
            vtgSetNeedsDisplay()
        }
    }

    #if os(macOS)
    /// Use top-left origin so VTG pixel coordinates match terminal screenshots.
    ///
    /// UIKit draws from the top left already, which is why the whole drawing
    /// layer ports without a coordinate flip.
    public override var isFlipped: Bool {
        true
    }
    #endif

    public override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        vtgUseTransparentLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        vtgUseTransparentLayer()
    }

    #if os(macOS)
    /// Ignore mouse hits so input continues to flow to the terminal view.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
    #else
    /// Ignore touches so input continues to flow to the terminal view.
    ///
    /// Returning nil is the same contract AppKit's `hitTest` has here: this
    /// view is never the target, whatever is underneath is.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
    #endif

    /// Draw all retained VTG primitives into the current graphics context.
    public override func draw(_ dirtyRect: CGRect) {
        guard let context = vtgCurrentCGContext(),
              let scene else {
            return
        }

        drawLocked(in: context, bounds: bounds) { canvasBounds in
            draw(scene: scene, plane: overlayCompositingPlane, in: context, bounds: canvasBounds)
        }
    }

    /// Draw retained VTG scene primitives into a caller-supplied Core Graphics
    /// context.
    ///
    /// `plane == nil` draws every retained primitive. Passing `.underText`,
    /// `.textPlane`, or `.overlay` lets terminal renderers and overlays split
    /// the same scene without duplicating parser or scene-state logic.
    public func draw(
        scene: VTGGraphicsScene,
        plane: VTGCompositingPlane?,
        in context: CGContext,
        bounds: CGRect
    ) {
        context.saveGState()
        let plan = scene.renderPlan(
            plane: plane,
            canvas: VTGRenderCanvas(width: bounds.width, height: bounds.height)
        )
        for entry in plan.entries {
            context.saveGState()
            context.setAlpha(entry.alpha)
            if let clip = entry.clip {
                context.clip(to: CGRect(x: clip.x, y: clip.y, width: clip.width, height: clip.height))
            }
            if let viewport = entry.viewport {
                context.clip(to: CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height))
                context.translateBy(x: viewport.x, y: viewport.y)
                context.scaleBy(x: viewport.scaleX, y: viewport.scaleY)
            }
            context.translateBy(x: entry.offset.x, y: entry.offset.y)
            drawPrimitive(entry.primitive, in: context, scene: scene)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// Runs `body` with the context scaled so drawing is in locked-screen
    /// pixels, or unchanged when no screen is locked.
    func drawLocked(in context: CGContext, bounds: CGRect, _ body: (CGRect) -> Void) {
        guard let locked = lockedCanvas, locked.width > 0, locked.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            body(bounds)
            return
        }
        let canvasBounds = CGRect(x: 0, y: 0, width: CGFloat(locked.width), height: CGFloat(locked.height))
        context.saveGState()
        context.scaleBy(x: bounds.width / canvasBounds.width, y: bounds.height / canvasBounds.height)
        body(canvasBounds)
        context.restoreGState()
    }

    private var overlayCompositingPlane: VTGCompositingPlane? {
        return .overlay
    }
}
#endif
