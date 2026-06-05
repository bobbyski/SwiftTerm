#if os(macOS)
import AppKit

/// Transparent AppKit overlay that renders retained VTG primitives.
public final class VTGOverlayView: NSView {
    /// Current retained VTG scene to draw.
    public var scene: VTGGraphicsScene? {
        didSet {
            needsDisplay = true
        }
    }

    /// Use top-left origin so VTG pixel coordinates match terminal screenshots.
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

    /// Ignore mouse hits so input continues to flow to the terminal view.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Draw all retained VTG primitives into the current graphics context.
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let scene else {
            return
        }

        context.saveGState()
        for primitive in scene.renderPrimitives {
            let layer = scene.layer(for: primitive)
            let offset = scene.offset(for: layer)
            context.saveGState()
            context.setAlpha(scene.alpha(for: layer))
            if let clip = scene.clip(for: layer) {
                context.clip(to: CGRect(x: clip.x, y: clip.y, width: clip.width, height: clip.height))
            }
            if let viewport = scene.viewportTransform(
                for: layer,
                canvasWidth: bounds.width,
                canvasHeight: bounds.height
            ) {
                context.clip(to: CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height))
                context.translateBy(x: viewport.x, y: viewport.y)
                context.scaleBy(x: viewport.scaleX, y: viewport.scaleY)
            }
            context.translateBy(x: offset.x, y: offset.y)
            drawPrimitive(primitive, in: context, scene: scene)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
#endif
