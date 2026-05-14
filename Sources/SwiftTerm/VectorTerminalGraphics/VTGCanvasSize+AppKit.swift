#if os(macOS)
import AppKit

public extension VTGCanvasSize {
    /// Return the best available VTG canvas size for an AppKit terminal embedding.
    ///
    /// The overlay is preferred because it is the actual VTG drawing surface.
    /// When it has not been laid out yet, embedders can fall back through the
    /// terminal's containing view, the terminal view itself, and finally the
    /// window content view.
    static func bestAvailable(
        preferredView: NSView?,
        fallbackView: NSView
    ) -> VTGCanvasSize {
        if let size = usableSize(for: preferredView) {
            return VTGCanvasSize(size)
        }
        if let size = usableSize(for: fallbackView.superview) {
            return VTGCanvasSize(size)
        }
        if fallbackView.bounds.width > 0 && fallbackView.bounds.height > 0 {
            return VTGCanvasSize(fallbackView.bounds.size)
        }
        return VTGCanvasSize(fallbackView.window?.contentView?.bounds.size ?? .zero)
    }

    private init(_ size: CGSize) {
        self.init(width: Int(size.width), height: Int(size.height))
    }

    private static func usableSize(for view: NSView?) -> CGSize? {
        guard let view else {
            return nil
        }
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            return nil
        }
        return view.bounds.size
    }
}
#endif
